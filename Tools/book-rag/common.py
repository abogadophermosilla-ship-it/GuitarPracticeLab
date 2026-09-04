"""Piezas compartidas por el indexador y el servidor de búsqueda.

El índice vive en el disco interno (Application Support) a propósito: los PDF y
el texto extraído están en /Volumes/VST, que no siempre está montado, y la app
ya trata ese volumen como opcional. El índice es dato derivado, así que puede
reconstruirse cuando el volumen vuelva.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import struct
import unicodedata
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

APP_SUPPORT = Path.home() / "Library/Application Support/GuitarPracticeLab"
RAG_DIR = APP_SUPPORT / "RAG"
DB_PATH = RAG_DIR / "libros.sqlite3"

CATALOGO_DIR = Path(
    os.environ.get(
        "BOOKRAG_CATALOG_DIR",
        "/Volumes/VST/Clases/Libros/_catalogo_ejercicios",
    )
).expanduser()
MANIFEST_PATH = CATALOGO_DIR / "manifest.json"
EXTRACTED_DIR = CATALOGO_DIR / "extracted"
EXERCISE_CATALOG_PATH = CATALOGO_DIR / "compiled_ejercicios_guitarra.json"

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
EMBED_MODEL = os.environ.get("BOOKRAG_EMBED_MODEL", "nomic-embed-text:latest")
EMBED_DIM = 768

# nomic-embed-text está entrenado con prefijos de tarea: usar el prefijo correcto
# en documentos y consultas cambia de verdad el recall, no es cosmético.
DOC_PREFIX = "search_document: "
QUERY_PREFIX = "search_query: "

# El modelo declara 2.048 tokens de contexto. ~2.400 caracteres ≈ 600 tokens deja
# margen de sobra y mantiene el chunk lo bastante chico para ser citable.
TARGET_CHARS = 2400
MAX_CHARS = 3400
OVERLAP_CHARS = 350
MIN_PAGE_CHARS = 40


# --------------------------------------------------------------------------
# Base de datos
# --------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS chunks (
    id             INTEGER PRIMARY KEY,
    libro          TEXT NOT NULL,
    archivo        TEXT NOT NULL,
    pagina_inicio  INTEGER NOT NULL,
    pagina_fin     INTEGER NOT NULL,
    es_ocr         INTEGER NOT NULL DEFAULT 0,
    texto          TEXT NOT NULL,
    contexto_busqueda TEXT NOT NULL DEFAULT '',
    hash           TEXT NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_chunks_libro ON chunks(libro);

CREATE TABLE IF NOT EXISTS embeddings (
    chunk_id  INTEGER PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
    modelo    TEXT NOT NULL,
    dim       INTEGER NOT NULL,
    vector    BLOB NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    texto,
    libro,
    content='chunks',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE IF NOT EXISTS catalog_items (
    id             INTEGER PRIMARY KEY,
    libro          TEXT NOT NULL,
    titulo         TEXT NOT NULL,
    pagina         INTEGER NOT NULL,
    tecnica        TEXT NOT NULL,
    dificultad     TEXT NOT NULL,
    descripcion    TEXT NOT NULL,
    tipo           TEXT NOT NULL,
    rol            TEXT NOT NULL,
    leccion        TEXT,
    forma          TEXT,
    tonalidad      TEXT,
    prepara_json   TEXT NOT NULL DEFAULT '[]',
    search_text    TEXT NOT NULL,
    UNIQUE(libro, pagina, titulo, descripcion)
);

CREATE INDEX IF NOT EXISTS idx_catalog_items_libro_pagina
ON catalog_items(libro, pagina);

CREATE VIRTUAL TABLE IF NOT EXISTS catalog_items_fts USING fts5(
    search_text,
    libro,
    content='catalog_items',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE IF NOT EXISTS meta (
    clave TEXT PRIMARY KEY,
    valor TEXT NOT NULL
);
"""


def connect(read_only: bool = False) -> sqlite3.Connection:
    RAG_DIR.mkdir(parents=True, exist_ok=True)
    if read_only and DB_PATH.exists():
        conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    else:
        conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    if not read_only:
        conn.executescript(SCHEMA)
        # Migración aditiva del índice existente. Es dato derivado, pero agregar la columna evita
        # obligar a borrar 1.186 embeddings solo para adoptar el contexto estructural; ingest.py
        # invalida únicamente los vectores cuyo contexto cambió.
        columnas = {
            fila["name"] for fila in conn.execute("PRAGMA table_info(chunks)").fetchall()
        }
        if "contexto_busqueda" not in columnas:
            conn.execute(
                "ALTER TABLE chunks ADD COLUMN contexto_busqueda TEXT NOT NULL DEFAULT ''"
            )
    return conn


def pack_vector(values: list[float]) -> bytes:
    return struct.pack(f"<{len(values)}f", *values)


def unpack_vector(blob: bytes) -> list[float]:
    return list(struct.unpack(f"<{len(blob) // 4}f", blob))


# --------------------------------------------------------------------------
# Embeddings
# --------------------------------------------------------------------------


DASH_RUN = re.compile(r"[-–—]{4,}")
PUNCT_RUN = re.compile(r"([^\w\s])\1{3,}")

# Tope duro de caracteres que se le manda al modelo de embedding. Va bastante
# por debajo de lo que permitirían 2.048 tokens de texto normal, justamente
# porque el texto de estos libros no es normal.
EMBED_CHAR_CAP = 1800


def texto_para_embedding(text: str) -> str:
    """Normaliza el texto ANTES de embeberlo (no altera lo que se guarda).

    La tablatura tokeniza malísimo: en `e|----------5---7---|` casi cada guion
    se lleva un token, así que una página de tabs revienta los 2.048 tokens del
    modelo con solo ~2.400 caracteres (Ollama devuelve HTTP 500). Y aunque
    entre, esos guiones no aportan nada semántico: solo diluyen el vector.

    Colapsar las corridas conserva la señal que sí importa (que es tablatura,
    en qué cuerda, con qué trastes y qué articulaciones) y deja espacio para la
    prosa que la acompaña, que es lo que de verdad hace recuperable el chunk.
    El texto original se guarda intacto para mostrar y citar.
    """
    normalizado = DASH_RUN.sub("---", text)
    normalizado = PUNCT_RUN.sub(r"\1\1", normalizado)
    normalizado = WHITESPACE.sub(" ", normalizado)
    normalizado = BLANK_RUN.sub("\n\n", normalizado).strip()
    if len(normalizado) > EMBED_CHAR_CAP:
        normalizado = normalizado[:EMBED_CHAR_CAP]
    return normalizado


def _pedir_embedding(text: str, timeout: int) -> list[float] | None:
    payload = json.dumps({"model": EMBED_MODEL, "prompt": text}).encode()
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/embeddings",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError:
        # Casi siempre es desborde de contexto; el llamador reintenta más corto.
        return None
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise RuntimeError(f"Ollama no respondió en {OLLAMA_URL}: {exc}") from exc

    return data.get("embedding") or None


def embed(text: str, *, is_query: bool = False, timeout: int = 120) -> list[float]:
    """Un embedding vía Ollama, con recorte progresivo si el modelo lo rechaza."""
    prefix = QUERY_PREFIX if is_query else DOC_PREFIX
    cuerpo = texto_para_embedding(text)

    for divisor in (1, 2, 4):
        recortado = cuerpo[: max(200, len(cuerpo) // divisor)]
        vector = _pedir_embedding(prefix + recortado, timeout)
        if vector:
            return vector

    raise RuntimeError(
        f"Ollama rechazó el texto incluso recortado a "
        f"{max(200, len(cuerpo) // 4)} caracteres"
    )


# --------------------------------------------------------------------------
# Limpieza y troceado del texto extraído
# --------------------------------------------------------------------------

PAGE_MARKER = re.compile(r"^=====\s*PAGE\s+(\d+)\s*=====\s*$", re.MULTILINE)
DOT_LEADER = re.compile(r"\.{4,}")
WHITESPACE = re.compile(r"[ \t]+")
BLANK_RUN = re.compile(r"\n{3,}")


@dataclass
class Page:
    numero: int
    texto: str


@dataclass
class Chunk:
    libro: str
    archivo: str
    pagina_inicio: int
    pagina_fin: int
    es_ocr: bool
    texto: str


@dataclass
class CatalogReference:
    titulo: str
    pagina: int


@dataclass
class CatalogItem:
    libro: str
    titulo: str
    pagina: int
    tecnica: str
    dificultad: str
    descripcion: str
    tipo: str
    rol: str
    leccion: str | None
    forma: str | None
    tonalidad: str | None
    prepara: list[CatalogReference]

    @property
    def search_text(self) -> str:
        if self.tipo == "pieza_aplicacion":
            etiquetas = (
                "pieza canción tema estudio repertorio didáctico aplicación integradora "
                "cierre práctico lección composición completa"
            )
        else:
            etiquetas = "ejercicio aislado práctica técnica preparación recurso"
        preparacion = " ".join(ref.titulo for ref in self.prepara)
        return " ".join(
            parte
            for parte in (
                self.titulo,
                self.tecnica,
                self.descripcion,
                etiquetas,
                self.rol,
                self.leccion,
                self.forma,
                self.tonalidad,
                preparacion,
            )
            if parte
        )


def parse_pages(raw: str) -> list[Page]:
    """Separa el .txt en páginas usando los marcadores `===== PAGE N =====`."""
    pages: list[Page] = []
    matches = list(PAGE_MARKER.finditer(raw))
    for i, match in enumerate(matches):
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(raw)
        pages.append(Page(numero=int(match.group(1)), texto=raw[start:end]))
    return pages


def is_toc_like(text: str) -> bool:
    """Índices y tablas de contenido: puro ruido, sobre todo en los OCR.

    Se reconocen por los puntos guía (`Introducción.......12`), que casi no
    aparecen en el cuerpo de un libro de guitarra.
    """
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) < 4:
        return False
    with_leaders = sum(1 for ln in lines if DOT_LEADER.search(ln))
    return with_leaders / len(lines) > 0.30


def clean_line(line: str) -> str | None:
    """Descarta líneas que el OCR dejó como basura ilegible.

    No toca las líneas de tablatura (`e|---5---7---|`): tienen poca proporción
    de letras pero sí significan algo para un guitarrista, así que se detectan
    aparte y se conservan.
    """
    line = WHITESPACE.sub(" ", line).strip()
    if not line:
        return ""

    # Tablatura: cuerda + barra + guiones/números. Se conserva tal cual.
    if re.match(r"^[eEADGBb]?\s*\|[-—0-9hpb/\\~*|() ]{6,}$", line):
        return line

    letters = sum(ch.isalpha() for ch in line)
    if len(line) >= 12 and letters / len(line) < 0.45:
        return None

    # Runs de puntos guía sobrantes de un índice que se coló.
    return DOT_LEADER.sub(" ", line).strip() or ""


def collapse_stutter(text: str) -> str:
    """Colapsa repeticiones inmediatas de la misma frase.

    El extractor de PDF duplica el texto en negrita, así que quedan cosas como
    "Practíca los Practíca los Practíca los bends de dos trastes". Repetido en
    cada página, esto le da al embedding una señal falsa de énfasis y consume
    contexto que debería llevar contenido.

    Se colapsa solo la repetición ADYACENTE: una frase que reaparece más
    adelante en la página suele ser pedagogía real (un libro de método repite a
    propósito) y borrarla sería perder contenido.
    """
    salida_lineas: list[str] = []
    for linea in text.splitlines():
        palabras = linea.split()
        # De frases largas a cortas: colapsar primero el n-grama grande evita
        # que un colapso de una palabra rompa la repetición mayor que lo contiene.
        # Hasta 20 palabras: en este corpus hay frases enteras duplicadas (una de
        # 16 palabras en Heavy Metal Lead Guitar I). Veinte palabras idénticas
        # seguidas nunca son intencionales, así que el techo alto no arriesga
        # borrar contenido real.
        for n in range(20, 0, -1):
            if len(palabras) < 2 * n:
                continue
            resultado: list[str] = []
            i = 0
            while i < len(palabras):
                patron = palabras[i : i + n]
                if i + 2 * n <= len(palabras) and palabras[i + n : i + 2 * n] == patron:
                    resultado.extend(patron)
                    j = i + n
                    while j + n <= len(palabras) and palabras[j : j + n] == patron:
                        j += n
                    i = j
                else:
                    resultado.append(palabras[i])
                    i += 1
            palabras = resultado
        salida_lineas.append(" ".join(palabras))
    return "\n".join(salida_lineas)


def detectar_boilerplate(paginas: list[str], umbral: float = 0.35) -> set[str]:
    """Encabezados y pies que se repiten en casi todas las páginas de un libro.

    Ejemplos reales de este corpus: "Traducción: Christian Carvajal" aparece en
    las 54 páginas de Heavy Metal Lead Guitar I, y "MIGUITARRAELECTRICA.COM" en
    74 de 75. Sin quitarlos, cada vector del libro carga la misma señal inútil.

    Solo se consideran líneas cortas: un párrafo que se repite en un tercio del
    libro es contenido del método, no un pie de página.
    """
    if len(paginas) < 5:
        return set()

    conteo: dict[str, int] = {}
    for pagina in paginas:
        unicas = {ln.strip() for ln in pagina.splitlines() if ln.strip()}
        for linea in unicas:
            if len(linea) <= 90:
                conteo[linea] = conteo.get(linea, 0) + 1

    minimo = max(3, int(len(paginas) * umbral))
    return {linea for linea, n in conteo.items() if n >= minimo}


def clean_page(text: str, boilerplate: set[str] | None = None) -> str:
    kept: list[str] = []
    for line in text.splitlines():
        cleaned = clean_line(line)
        if cleaned is None:
            continue
        if boilerplate and cleaned.strip() in boilerplate:
            continue
        kept.append(cleaned)
    out = BLANK_RUN.sub("\n\n", "\n".join(kept)).strip()
    return collapse_stutter(out)


# --------------------------------------------------------------------------
# Estructura pedagógica del catálogo
# --------------------------------------------------------------------------

PIECE_WORDS = re.compile(
    r"\b(pieza(?: musical)?|estudio|canci[oó]n|tonada|tema completo|composici[oó]n)\b",
    re.IGNORECASE,
)
LESSON = re.compile(r"\blecci[oó]n\s+(\d+)\b", re.IGNORECASE)
KEY = re.compile(
    r"\b(?:tono|tonalidad)\s+(?:de|en)\s+"
    r"([A-G](?:[#♯b♭])?(?:\s+(?:mayor|menor))?)\b",
    re.IGNORECASE,
)
BAR_FORM = re.compile(r"\b(\d{1,3})\s*[- ]?compases\b", re.IGNORECASE)


def normalizar_identidad(text: str) -> str:
    """Normalización fuerte solo para cruzar títulos entre JSON y OCR."""
    descompuesto = unicodedata.normalize("NFKD", text)
    sin_tildes = "".join(ch for ch in descompuesto if not unicodedata.combining(ch))
    return " ".join(re.findall(r"[a-z0-9]+", sin_tildes.lower()))


def _paginas_por_numero(raw: str) -> dict[int, str]:
    return {pagina.numero: pagina.texto for pagina in parse_pages(raw)}


def _contexto_de_item(paginas: dict[int, str], numero: int) -> str:
    # La explicación suele terminar en la página del catálogo y la partitura empezar en la
    # siguiente. Incluir una página a cada lado conserva ambas sin confundir lecciones lejanas.
    return "\n".join(paginas.get(n, "") for n in range(max(1, numero - 1), numero + 2))


def _tiene_encabezado_de_partitura(titulo: str, contexto: str) -> bool:
    """Detecta el título grande que encabeza una partitura o tablatura completa.

    Es la señal que corrige casos como Bending the Blues: el catálogo lo describía como
    "Ejercicio de bends", pero el libro imprime BENDING THE BLUES como título de un estudio.
    No basta con que el título aparezca citado en la prosa; debe ocupar su propia línea y estar
    escrito mayoritariamente en mayúsculas.
    """
    esperado = normalizar_identidad(titulo)
    if not esperado:
        return False
    for linea in contexto.splitlines():
        limpia = linea.strip().strip("“”\"'@©&0123456789 ")
        if normalizar_identidad(limpia) != esperado:
            continue
        letras = [ch for ch in limpia if ch.isalpha()]
        if letras and sum(ch.isupper() for ch in letras) / len(letras) >= 0.70:
            return True
    return False


def _leccion_cercana(paginas: dict[int, str], numero: int) -> str | None:
    # Ocho páginas alcanzan para las lecciones más largas del corpus. No se mira el comienzo del
    # libro para que una entrada del índice no se confunda con el encabezado real de la lección.
    desde = max(5, numero - 8)
    encontradas: list[str] = []
    for n in range(desde, numero + 1):
        for linea in paginas.get(n, "").splitlines():
            # Solo encabezados aislados. Las frases "como vimos en la Lección 20" son referencias
            # retrospectivas y antes podían pisar el encabezado real de la Lección 21.
            match = re.fullmatch(
                r"\s*lecci[oó]n\s+(\d+)\s*", linea, re.IGNORECASE
            )
            if match:
                encontradas.append(match.group(1))
    return f"Lección {encontradas[-1]}" if encontradas else None


def _forma_musical(texto: str) -> str | None:
    normalizado = normalizar_identidad(texto)
    match = BAR_FORM.search(texto)
    if not match:
        # El guion de fin de línea del OCR deja a veces "12-\ncompases".
        match = re.search(r"\b(\d{1,3})\s*-?\s*\n?\s*compases\b", texto, re.IGNORECASE)
    if not match:
        return None
    compases = int(match.group(1))
    return f"Blues de {compases} compases" if "blues" in normalizado else f"Forma de {compases} compases"


def cargar_catalogo_estructurado(
    raw_por_libro: dict[str, str],
    path: Path = EXERCISE_CATALOG_PATH,
) -> list[CatalogItem]:
    """Fusiona el catálogo curado con señales de estructura tomadas del texto completo.

    El JSON aporta títulos, página, técnica y descripción. El texto del libro aporta lo que antes
    se perdía: si el material es una partitura/estudio de aplicación, en qué lección vive, su forma
    y tonalidad. Todo se resuelve de forma determinista durante la ingesta; el servidor no necesita
    el volumen externo montado para devolver luego esos detalles.
    """
    if not path.exists():
        return []
    try:
        entradas = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []

    paginas_por_libro = {
        libro: _paginas_por_numero(raw) for libro, raw in raw_por_libro.items()
    }
    items: list[CatalogItem] = []
    for entrada in entradas:
        libro = str(entrada.get("libro", "")).strip()
        titulo = str(entrada.get("titulo_ejercicio", "")).strip()
        pagina = int(entrada.get("pagina") or 0)
        descripcion = str(entrada.get("descripcion", "")).strip()
        paginas = paginas_por_libro.get(libro, {})
        contexto = _contexto_de_item(paginas, pagina)
        es_pieza = bool(PIECE_WORDS.search(descripcion)) or _tiene_encabezado_de_partitura(
            titulo, contexto
        )

        texto_detalle = f"{descripcion}\n{contexto}"
        forma = _forma_musical(texto_detalle) if es_pieza else None
        tonalidad_match = KEY.search(texto_detalle) if es_pieza else None
        tonalidad = tonalidad_match.group(1).strip() if tonalidad_match else None
        leccion = _leccion_cercana(paginas, pagina)
        rol = (
            "Cierre práctico de la lección: integra recursos técnicos dentro de una pieza completa."
            if es_pieza and leccion
            else "Estudio integrador o repertorio didáctico."
            if es_pieza
            else "Ejercicio de preparación técnica o conceptual."
        )
        items.append(
            CatalogItem(
                libro=libro,
                titulo=titulo,
                pagina=pagina,
                tecnica=str(entrada.get("tecnica", "")).strip(),
                dificultad=str(entrada.get("dificultad", "")).strip(),
                descripcion=descripcion,
                tipo="pieza_aplicacion" if es_pieza else "ejercicio",
                rol=rol,
                leccion=leccion,
                forma=forma,
                tonalidad=tonalidad,
                prepara=[],
            )
        )

    # Una pieza cierra lo trabajado desde la pieza anterior. Se limita a cinco páginas y tres
    # ejercicios para ofrecer orientación útil sin inventar una dependencia curricular rígida.
    por_libro: dict[str, list[CatalogItem]] = {}
    for item in items:
        por_libro.setdefault(item.libro, []).append(item)
    for libro_items in por_libro.values():
        libro_items.sort(key=lambda item: item.pagina)
        desde_ultima_pieza = 0
        for i, item in enumerate(libro_items):
            if item.tipo != "pieza_aplicacion":
                continue
            candidatos = [
                anterior
                for anterior in libro_items[desde_ultima_pieza:i]
                if anterior.tipo == "ejercicio"
                and anterior.pagina >= item.pagina - 5
                and (not item.leccion or anterior.leccion == item.leccion)
            ]
            item.prepara = [
                CatalogReference(titulo=anterior.titulo, pagina=anterior.pagina)
                for anterior in candidatos[-3:]
            ]
            desde_ultima_pieza = i + 1
    return items


def split_long(text: str) -> list[str]:
    """Parte una página larga por párrafos, con solape para no cortar una idea."""
    if len(text) <= MAX_CHARS:
        return [text]

    paragraphs = [p for p in re.split(r"\n\s*\n", text) if p.strip()]
    pieces: list[str] = []
    current = ""
    for para in paragraphs:
        if current and len(current) + len(para) + 2 > TARGET_CHARS:
            pieces.append(current.strip())
            current = current[-OVERLAP_CHARS:] + "\n\n" + para
        else:
            current = f"{current}\n\n{para}" if current else para
    if current.strip():
        pieces.append(current.strip())

    # Un párrafo suelto más largo que el máximo (tablatura corrida, por ejemplo):
    # se corta duro, sin intentar respetar estructura que no existe.
    final: list[str] = []
    for piece in pieces:
        while len(piece) > MAX_CHARS:
            final.append(piece[:MAX_CHARS])
            piece = piece[MAX_CHARS - OVERLAP_CHARS:]
        if piece.strip():
            final.append(piece.strip())
    return final


def chunk_book(libro: str, archivo: str, raw: str, es_ocr: bool) -> list[Chunk]:
    """Agrupa páginas consecutivas hasta el tamaño objetivo.

    Se agrupa en vez de trocear por longitud fija porque la página es la unidad
    que la app necesita para citar ("Fretboard Freedom, p. 112"). Un chunk que
    cruza páginas guarda el rango completo.
    """
    paginas = parse_pages(raw)

    # Primera pasada: hay que ver el libro entero para saber qué líneas son
    # encabezado/pie. No se puede decidir página por página.
    limpias_provisorias = [clean_page(p.texto) for p in paginas]
    boilerplate = detectar_boilerplate(
        [t for t in limpias_provisorias if len(t) >= MIN_PAGE_CHARS]
    )

    chunks: list[Chunk] = []
    buffer: list[str] = []
    buffer_len = 0
    inicio: int | None = None
    fin: int | None = None

    def flush() -> None:
        nonlocal buffer, buffer_len, inicio, fin
        if not buffer or inicio is None or fin is None:
            return
        texto = "\n\n".join(buffer).strip()
        if texto:
            chunks.append(
                Chunk(
                    libro=libro,
                    archivo=archivo,
                    pagina_inicio=inicio,
                    pagina_fin=fin,
                    es_ocr=es_ocr,
                    texto=texto,
                )
            )
        buffer, buffer_len, inicio, fin = [], 0, None, None

    for page in paginas:
        texto = clean_page(page.texto, boilerplate)
        if len(texto) < MIN_PAGE_CHARS or is_toc_like(texto):
            continue

        if len(texto) > MAX_CHARS:
            flush()
            for piece in split_long(texto):
                chunks.append(
                    Chunk(
                        libro=libro,
                        archivo=archivo,
                        pagina_inicio=page.numero,
                        pagina_fin=page.numero,
                        es_ocr=es_ocr,
                        texto=piece,
                    )
                )
            continue

        if buffer_len + len(texto) > TARGET_CHARS:
            flush()

        buffer.append(texto)
        buffer_len += len(texto)
        inicio = page.numero if inicio is None else inicio
        fin = page.numero

    flush()
    return chunks


# Título canónico por archivo extraído.
#
# Se fija a mano en vez de leerlo del manifest porque el manifest y el catálogo
# ya importado en Biblioteca no coinciden en dos casos, y la cita del RAG tiene
# que caer sobre el MISMO nombre que usa la app para que crucen:
#   - miguitarraelectrica: el manifest le agrega "(MIGUITARRAELECTRICA)".
#   - breakthrough_blues / improvisacion_munones: no tienen texto_fuente en el
#     manifest (se procesaron antes de crearlo), así que caerían en un título
#     inventado a partir del nombre de archivo.
#
# Además, el catálogo trae dos libros duplicados por inconsistencia de acentos
# ("Teoria/Teoría Básica...", "Triadas para Munones/Muñones..."). Aquí se elige
# la forma acentuada, que es la que tiene la gran mayoría de los ejercicios.
TITULOS_CANONICOS: dict[str, str] = {
    "blues_a_tu_alcance_OCR.txt": "Blues a tu alcance",
    "breakthrough_blues.txt": (
        "Breakthrough Blues-Rock Rhythm Fills - Jeff McErlain (TrueFire)"
    ),
    "fretboard_freedom.txt": "Fretboard Freedom - Troy Nelson",
    "guitar_aerobics.txt": "Guitar Aerobics",
    "heavy_metal_guitar_tricks.txt": "Heavy Metal Guitar Tricks",
    "heavy_metal_lead_guitar_1.txt": "Heavy Metal Lead Guitar Vol I - Troy Stetina",
    "heavy_metal_lead_guitar_2.txt": "Heavy Metal Lead Guitar Vol II - Troy Stetina",
    "improvisacion_munones.txt": "Improvisación para Muñones v1.05",
    "john_ganapes_blues_rhythms_OCR.txt": "John Ganapes - Blues Rhythms You Can Use",
    "john_ganapes_more_blues_OCR.txt": "John Ganapes - More Blues You Can Use",
    "metal_rhythm_guitar_1.txt": "Metal Rhythm Guitar Volume I - Troy Stetina",
    "metal_rhythm_guitar_2.txt": "Metal Rhythm Guitar Volume II - Troy Stetina",
    "miguitarraelectrica.txt": "Teoría Básica Para Guitarristas Principiantes",
    "shred_guitar.txt": "Shred Guitar - Paul Hanson",
    "shred_guitar_OCR.txt": "Shred Guitar - Paul Hanson",
    "speed_mechanics.txt": "Speed Mechanics For The Lead Guitar",
    "speed_mechanics_anexo.txt": "Speed Mechanics For The Lead Guitar",
    "speed_thrash_metal.txt": "Speed And Thrash Metal",
    "stwkms.txt": "Secrets To Writing Killer Metal Songs",
    "total_rock_guitar.txt": "Total Rock Guitar",
    "triadas_munones.txt": "Triadas para Muñones V1.2",
}


def titulo_canonico(path: Path) -> str:
    """Título del libro para un .txt extraído.

    Se busca primero un sidecar `<nombre>.json` con `{"titulo": "..."}`: es lo
    que escribe la app al importar un libro desde la Biblioteca, y permite que
    la cita del RAG caiga sobre el mismo título que el usuario ya ve ahí, sin
    tener que tocar el mapa de abajo a mano por cada libro nuevo.

    Si no hay sidecar y el archivo tampoco está en el mapa, se deriva del
    nombre y se sigue adelante: es preferible indexarlo con un título
    imperfecto a dejarlo fuera del índice en silencio. `ingest.py` lo reporta.
    """
    sidecar = path.with_suffix(".json")
    if sidecar.exists():
        try:
            titulo = json.loads(sidecar.read_text(encoding="utf-8")).get("titulo")
        except (json.JSONDecodeError, OSError):
            titulo = None
        if titulo:
            return titulo

    conocido = TITULOS_CANONICOS.get(path.name)
    if conocido:
        return conocido
    return path.stem.replace("_OCR", "").replace("_", " ").title()
