#!/usr/bin/env python3
"""Servidor local de búsqueda sobre el índice de libros.

Escucha solo en 127.0.0.1 (igual que el gateway de Hermes y LiteLLM): es un
servicio personal, no tiene autenticación y no debe salir de la máquina.

    GET /health
    GET /search?q=...&k=8&libro=...&modo=hibrido|vectorial|lexico

La búsqueda es híbrida a propósito. Los nombres de la guitarra son literales
("sweep picking", "Mixolydian", "hammer-on") y la coincidencia léxica exacta los
encuentra mejor que la semántica; pero una pregunta como "cómo suelto la mano
derecha en pasajes rápidos" no comparte ni una palabra con el texto que la
responde. Cada método falla donde el otro acierta, así que se fusionan por RRF.
"""

from __future__ import annotations

import json
import functools
import re
import sqlite3
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

import common

HOST = "127.0.0.1"
PORT = 8643
RRF_K = 60  # constante estándar de Reciprocal Rank Fusion
POOL = 40  # candidatos que aporta cada método antes de fusionar


class Indice:
    """Vectores en memoria + acceso al SQLite. Se recarga si el índice cambia."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._mtime: float | None = None
        self._ids: np.ndarray = np.zeros(0, dtype=np.int64)
        self._matriz: np.ndarray = np.zeros((0, common.EMBED_DIM), dtype=np.float32)
        self.cargar()

    def cargar(self) -> None:
        with self._lock:
            if not common.DB_PATH.exists():
                raise RuntimeError(
                    f"No existe el índice en {common.DB_PATH}. "
                    "Corré primero: python3 ingest.py"
                )
            mtime = common.DB_PATH.stat().st_mtime
            if self._mtime == mtime:
                return

            conn = common.connect(read_only=True)
            filas = conn.execute(
                "SELECT chunk_id, vector FROM embeddings ORDER BY chunk_id"
            ).fetchall()
            conn.close()

            if not filas:
                self._ids = np.zeros(0, dtype=np.int64)
                self._matriz = np.zeros((0, common.EMBED_DIM), dtype=np.float32)
                self._mtime = mtime
                return

            self._ids = np.array([f["chunk_id"] for f in filas], dtype=np.int64)
            matriz = np.vstack(
                [np.frombuffer(f["vector"], dtype=np.float32) for f in filas]
            )
            # Se normaliza una sola vez al cargar: así el coseno de cada consulta
            # es un simple producto punto.
            normas = np.linalg.norm(matriz, axis=1, keepdims=True)
            normas[normas == 0] = 1.0
            self._matriz = (matriz / normas).astype(np.float32)
            self._mtime = mtime

    def buscar_vectorial(self, vector: list[float], limite: int) -> list[int]:
        self.cargar()
        with self._lock:
            if self._matriz.shape[0] == 0:
                return []
            consulta = np.asarray(vector, dtype=np.float32)
            norma = np.linalg.norm(consulta) or 1.0
            puntajes = self._matriz @ (consulta / norma)
            limite = min(limite, puntajes.shape[0])
            mejores = np.argpartition(-puntajes, limite - 1)[:limite]
            mejores = mejores[np.argsort(-puntajes[mejores])]
            return [int(self._ids[i]) for i in mejores]

    @property
    def total(self) -> int:
        return int(self._matriz.shape[0])


INDICE: Indice | None = None

TERMINO = re.compile(r"[\wáéíóúüñÁÉÍÓÚÜÑ#♯♭'-]+", re.UNICODE)


def consulta_fts(texto: str) -> str:
    """Convierte texto libre en una consulta FTS5 segura.

    Se citan los términos uno a uno y se unen con OR: si se pasara el texto del
    usuario tal cual, cualquier comilla, paréntesis o guion suelto lo haría
    explotar como sintaxis de FTS5.
    """
    terminos = [t for t in TERMINO.findall(texto) if len(t) > 1]
    if not terminos:
        return ""
    return " OR ".join('"' + t.replace('"', '""') + '"' for t in terminos[:24])


def buscar_lexico(conn: sqlite3.Connection, texto: str, limite: int) -> list[int]:
    consulta = consulta_fts(texto)
    if not consulta:
        return []
    try:
        filas = conn.execute(
            """SELECT rowid FROM chunks_fts
               WHERE chunks_fts MATCH ?
               ORDER BY bm25(chunks_fts, 1.0, 0.4)
               LIMIT ?""",
            (consulta, limite),
        ).fetchall()
    except sqlite3.OperationalError:
        return []
    return [int(f["rowid"]) for f in filas]


def buscar_catalogo_lexico(
    conn: sqlite3.Connection, texto: str, limite: int
) -> list[int]:
    """Busca también en títulos y fichas pedagógicas y los proyecta a su chunk real.

    Así una consulta como "canción de cierre para practicar bends" encuentra Bending the Blues
    aunque esas palabras no aparezcan juntas en el OCR. El resultado sigue siendo un pasaje real y
    citable: la ficha solo ayuda a encontrarlo, nunca lo reemplaza.
    """
    consulta = consulta_fts(texto)
    if not consulta:
        return []
    try:
        items = conn.execute(
            """SELECT ci.libro, ci.pagina
               FROM catalog_items_fts fts
               JOIN catalog_items ci ON ci.id = fts.rowid
               WHERE catalog_items_fts MATCH ?
               ORDER BY bm25(catalog_items_fts, 1.0, 0.35)
               LIMIT ?""",
            (consulta, limite),
        ).fetchall()
    except sqlite3.OperationalError:
        return []

    chunks: list[int] = []
    vistos: set[int] = set()
    for item in items:
        chunk = conn.execute(
            """SELECT id FROM chunks
               WHERE libro = ?
               ORDER BY CASE
                   WHEN ? BETWEEN pagina_inicio AND pagina_fin THEN 0
                   ELSE min(abs(pagina_inicio - ?), abs(pagina_fin - ?))
               END, pagina_inicio
               LIMIT 1""",
            (item["libro"], item["pagina"], item["pagina"], item["pagina"]),
        ).fetchone()
        if chunk and int(chunk["id"]) not in vistos:
            vistos.add(int(chunk["id"]))
            chunks.append(int(chunk["id"]))
    return chunks


@functools.lru_cache(maxsize=128)
def embedding_consulta(texto: str) -> tuple[float, ...]:
    """Evita volver a llamar a Ollama al regresar a una búsqueda reciente."""
    return tuple(common.embed(texto, is_query=True))


def contenidos_del_chunk(conn: sqlite3.Connection, fila: sqlite3.Row) -> list[dict]:
    try:
        items = conn.execute(
            """SELECT titulo, pagina, tecnica, dificultad, descripcion, tipo, rol,
                      leccion, forma, tonalidad, prepara_json
               FROM catalog_items
               WHERE libro = ? AND pagina BETWEEN ? AND ?
               ORDER BY pagina, id""",
            (fila["libro"], fila["pagina_inicio"] - 1, fila["pagina_fin"] + 1),
        ).fetchall()
    except sqlite3.OperationalError:
        return []
    return [
        {
            "titulo": item["titulo"],
            "pagina": item["pagina"],
            "tecnica": item["tecnica"],
            "dificultad": item["dificultad"],
            "descripcion": item["descripcion"],
            "tipo": item["tipo"],
            "rol": item["rol"],
            "leccion": item["leccion"],
            "forma": item["forma"],
            "tonalidad": item["tonalidad"],
            "prepara": json.loads(item["prepara_json"] or "[]"),
        }
        for item in items
    ]


def fusionar(rankings: list[list[int]], pesos: list[float]) -> list[tuple[int, float]]:
    """Reciprocal Rank Fusion: combina por posición, no por puntaje.

    Es lo correcto acá porque el coseno y BM25 viven en escalas distintas y no
    comparables; normalizarlas para sumarlas sería inventar una equivalencia.
    """
    acumulado: dict[int, float] = {}
    for ranking, peso in zip(rankings, pesos):
        for posicion, chunk_id in enumerate(ranking):
            acumulado[chunk_id] = acumulado.get(chunk_id, 0.0) + peso / (
                RRF_K + posicion + 1
            )
    return sorted(acumulado.items(), key=lambda par: -par[1])


def buscar(texto: str, k: int, libro: str | None, modo: str) -> dict:
    assert INDICE is not None
    conn = common.connect(read_only=True)
    try:
        rankings: list[list[int]] = []
        pesos: list[float] = []

        if modo in ("hibrido", "vectorial"):
            vector = embedding_consulta(texto)
            rankings.append(INDICE.buscar_vectorial(vector, POOL))
            pesos.append(1.0)

        if modo in ("hibrido", "lexico"):
            rankings.append(buscar_lexico(conn, texto, POOL))
            pesos.append(1.0)
            rankings.append(buscar_catalogo_lexico(conn, texto, POOL))
            # La ficha estructural está curada y sus títulos no sufren el ruido del OCR.
            pesos.append(1.15)

        fusionados = fusionar(rankings, pesos)
        if not fusionados:
            return {"consulta": texto, "modo": modo, "resultados": []}

        ids = [cid for cid, _ in fusionados]
        marcadores = ",".join("?" * len(ids))
        filas = conn.execute(
            f"""SELECT id, libro, archivo, pagina_inicio, pagina_fin, es_ocr, texto
                FROM chunks WHERE id IN ({marcadores})""",
            ids,
        ).fetchall()
        por_id = {f["id"]: f for f in filas}

        resultados = []
        for chunk_id, puntaje in fusionados:
            fila = por_id.get(chunk_id)
            if fila is None:
                continue
            if libro and libro.lower() not in fila["libro"].lower():
                continue
            resultados.append(
                {
                    "id": fila["id"],
                    "libro": fila["libro"],
                    "archivo": fila["archivo"],
                    "pagina_inicio": fila["pagina_inicio"],
                    "pagina_fin": fila["pagina_fin"],
                    "es_ocr": bool(fila["es_ocr"]),
                    "puntaje": round(puntaje, 6),
                    "cita": _cita(fila),
                    "texto": fila["texto"],
                    "contenidos": contenidos_del_chunk(conn, fila),
                }
            )
            if len(resultados) >= k:
                break

        return {"consulta": texto, "modo": modo, "resultados": resultados}
    finally:
        conn.close()


def _cita(fila: sqlite3.Row) -> str:
    """Etiqueta de cita, en el mismo formato que ya usa el Profesor IA."""
    if fila["pagina_inicio"] == fila["pagina_fin"]:
        paginas = f"p. {fila['pagina_inicio']}"
    else:
        paginas = f"pp. {fila['pagina_inicio']}-{fila['pagina_fin']}"
    return f"{fila['libro']}, {paginas}"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _responder(self, codigo: int, cuerpo: dict) -> None:
        datos = json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(datos)))
        self.end_headers()
        self.wfile.write(datos)

    def do_GET(self) -> None:  # noqa: N802  (nombre impuesto por BaseHTTPRequestHandler)
        partes = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(partes.query)

        if partes.path == "/health":
            conn = common.connect(read_only=True)
            try:
                chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
                libros = conn.execute(
                    "SELECT COUNT(DISTINCT libro) FROM chunks"
                ).fetchone()[0]
                try:
                    items_catalogo = conn.execute(
                        "SELECT COUNT(*) FROM catalog_items"
                    ).fetchone()[0]
                    piezas = conn.execute(
                        "SELECT COUNT(*) FROM catalog_items WHERE tipo = 'pieza_aplicacion'"
                    ).fetchone()[0]
                except sqlite3.OperationalError:
                    items_catalogo = 0
                    piezas = 0
                meta = {
                    f["clave"]: f["valor"]
                    for f in conn.execute("SELECT clave, valor FROM meta").fetchall()
                }
            finally:
                conn.close()
            assert INDICE is not None
            self._responder(
                200,
                {
                    "estado": "ok",
                    "chunks": chunks,
                    "vectores": INDICE.total,
                    "libros": libros,
                    "items_catalogo": items_catalogo,
                    "piezas_aplicacion": piezas,
                    "modelo_embedding": common.EMBED_MODEL,
                    **meta,
                },
            )
            return

        if partes.path == "/search":
            texto = (params.get("q") or [""])[0].strip()
            if not texto:
                self._responder(400, {"error": "falta el parámetro q"})
                return
            try:
                k = max(1, min(25, int((params.get("k") or ["8"])[0])))
            except ValueError:
                k = 8
            libro = (params.get("libro") or [None])[0]
            modo = (params.get("modo") or ["hibrido"])[0]
            if modo not in ("hibrido", "vectorial", "lexico"):
                modo = "hibrido"

            try:
                self._responder(200, buscar(texto, k, libro, modo))
            except RuntimeError as exc:
                # Casi siempre: Ollama apagado. Se responde 503 para que la app
                # distinga "el servicio está, el motor no" de un error de datos.
                self._responder(503, {"error": str(exc)})
            return

        self._responder(404, {"error": "ruta desconocida"})

    def log_message(self, formato: str, *args) -> None:
        sys.stderr.write(f"{self.address_string()} - {formato % args}\n")


def main() -> int:
    global INDICE
    try:
        INDICE = Indice()
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"book-rag escuchando en http://{HOST}:{PORT}  "
        f"({INDICE.total} vectores cargados)"
    )
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
