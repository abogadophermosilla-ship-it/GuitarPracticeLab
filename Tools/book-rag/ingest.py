#!/usr/bin/env python3
"""Construye el índice vectorial sobre el texto completo de los libros.

Uso:
    python3 ingest.py            # incremental: solo trocea/embebe lo que falta
    python3 ingest.py --rebuild  # borra y reconstruye desde cero
    python3 ingest.py --dry-run  # trocea y reporta, sin llamar a Ollama

Es idempotente: cada chunk se identifica por el hash de su texto, así que
volver a correrlo tras actualizar un libro solo procesa lo nuevo.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import common


def descubrir_libros() -> list[tuple[str, Path]]:
    """Pares (título canónico, ruta) de todos los .txt extraídos.

    Se recorre el directorio en vez del manifest: el manifest solo lista lo que
    estaba pendiente en su momento y dejaría fuera los libros ya terminados.
    """
    pares: list[tuple[str, Path]] = []
    for path in sorted(common.EXTRACTED_DIR.glob("*.txt")):
        pares.append((common.titulo_canonico(path), path))
    return pares


def hash_chunk(chunk: common.Chunk) -> str:
    payload = f"{chunk.libro}|{chunk.pagina_inicio}|{chunk.pagina_fin}|{chunk.texto}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def contexto_catalogo(
    chunk: common.Chunk,
    items_por_libro: dict[str, list[common.CatalogItem]],
) -> str:
    relacionados = [
        item
        for item in items_por_libro.get(chunk.libro, [])
        if chunk.pagina_inicio - 1 <= item.pagina <= chunk.pagina_fin + 1
    ]
    if not relacionados:
        return ""
    lineas = ["CONTEXTO ESTRUCTURAL DEL CATÁLOGO:"]
    for item in relacionados:
        tipo = "Pieza/estudio de aplicación" if item.tipo == "pieza_aplicacion" else "Ejercicio preparatorio"
        detalles = " · ".join(
            valor
            for valor in (item.leccion, item.forma, f"Tonalidad {item.tonalidad}" if item.tonalidad else None)
            if valor
        )
        prepara = ", ".join(ref.titulo for ref in item.prepara)
        lineas.append(
            f"- {tipo}: {item.titulo} (p. {item.pagina}). "
            f"{item.descripcion} Técnica: {item.tecnica}. {item.rol}"
            f"{' ' + detalles + '.' if detalles else ''}"
            f"{' Preparado por: ' + prepara + '.' if prepara else ''}"
        )
    return "\n".join(lineas)


def sincronizar_catalogo(conn, items: list[common.CatalogItem]) -> None:
    """Reemplaza solo las fichas derivadas; los chunks y sus IDs permanecen estables."""
    conn.execute("DELETE FROM catalog_items_fts")
    conn.execute("DELETE FROM catalog_items")
    for item in items:
        cur = conn.execute(
            """INSERT INTO catalog_items
               (libro, titulo, pagina, tecnica, dificultad, descripcion, tipo, rol,
                leccion, forma, tonalidad, prepara_json, search_text)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                item.libro,
                item.titulo,
                item.pagina,
                item.tecnica,
                item.dificultad,
                item.descripcion,
                item.tipo,
                item.rol,
                item.leccion,
                item.forma,
                item.tonalidad,
                json.dumps(
                    [vars(ref) for ref in item.prepara], ensure_ascii=False
                ),
                item.search_text,
            ),
        )
        conn.execute(
            "INSERT INTO catalog_items_fts(rowid, search_text, libro) VALUES (?, ?, ?)",
            (cur.lastrowid, item.search_text, item.libro),
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true", help="reconstruir desde cero")
    parser.add_argument("--dry-run", action="store_true", help="no llamar a Ollama")
    args = parser.parse_args()

    if not common.EXTRACTED_DIR.exists():
        print(
            f"ERROR: no encuentro {common.EXTRACTED_DIR}\n"
            "¿Está montado /Volumes/VST?",
            file=sys.stderr,
        )
        return 1

    conn = common.connect()

    if args.rebuild:
        conn.executescript(
            """DELETE FROM embeddings;
               DELETE FROM chunks;
               DELETE FROM chunks_fts;
               DELETE FROM catalog_items_fts;
               DELETE FROM catalog_items;"""
        )
        conn.commit()
        print("Índice vaciado.\n")

    # ---------------------------------------------------------------- troceado
    libros = descubrir_libros()
    print(f"Libros a procesar: {len(libros)}\n")

    raws: dict[str, str] = {
        libro: path.read_text(encoding="utf-8", errors="replace")
        for libro, path in libros
    }
    catalogo = common.cargar_catalogo_estructurado(raws)
    items_por_libro: dict[str, list[common.CatalogItem]] = {}
    for item in catalogo:
        items_por_libro.setdefault(item.libro, []).append(item)
    if not args.dry_run:
        sincronizar_catalogo(conn, catalogo)
        conn.commit()
    piezas = sum(item.tipo == "pieza_aplicacion" for item in catalogo)
    print(
        f"Catálogo estructural: {len(catalogo)} ítems · "
        f"{piezas} piezas/estudios de aplicación\n"
    )

    sin_titulo = [
        p.name
        for _, p in libros
        if p.name not in common.TITULOS_CANONICOS and not p.with_suffix(".json").exists()
    ]
    nuevos = 0
    total_chunks = 0
    for libro, path in libros:
        raw = raws[libro]
        es_ocr = "_OCR" in path.name
        chunks = common.chunk_book(libro, path.name, raw, es_ocr)
        total_chunks += len(chunks)

        insertados = 0
        for chunk in chunks:
            digest = hash_chunk(chunk)
            contexto = contexto_catalogo(chunk, items_por_libro)
            if args.dry_run:
                existe = conn.execute(
                    "SELECT 1 FROM chunks WHERE hash = ?", (digest,)
                ).fetchone()
                insertados += 0 if existe else 1
                continue

            existente = conn.execute(
                "SELECT id, contexto_busqueda FROM chunks WHERE hash = ?", (digest,)
            ).fetchone()
            if existente:
                if existente["contexto_busqueda"] != contexto:
                    conn.execute(
                        "UPDATE chunks SET contexto_busqueda = ? WHERE id = ?",
                        (contexto, existente["id"]),
                    )
                    # El contexto va delante del texto al embeber; si cambió, ese vector ya no
                    # representa el documento enriquecido y debe regenerarse.
                    conn.execute(
                        "DELETE FROM embeddings WHERE chunk_id = ?", (existente["id"],)
                    )
                continue

            cur = conn.execute(
                """INSERT OR IGNORE INTO chunks
                   (libro, archivo, pagina_inicio, pagina_fin, es_ocr, texto,
                    contexto_busqueda, hash)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    chunk.libro,
                    chunk.archivo,
                    chunk.pagina_inicio,
                    chunk.pagina_fin,
                    int(chunk.es_ocr),
                    chunk.texto,
                    contexto,
                    digest,
                ),
            )
            if cur.rowcount:
                insertados += 1
                conn.execute(
                    "INSERT INTO chunks_fts(rowid, texto, libro) VALUES (?, ?, ?)",
                    (cur.lastrowid, chunk.texto, chunk.libro),
                )
        if not args.dry_run:
            conn.commit()
        nuevos += insertados
        marca = " (OCR)" if es_ocr else ""
        print(f"  {len(chunks):5d} chunks  (+{insertados:4d} nuevos)  {libro}{marca}")

    print(f"\nTotal troceado: {total_chunks} chunks · {nuevos} nuevos")

    if sin_titulo:
        print(
            "\nAVISO: estos archivos no están en TITULOS_CANONICOS y quedaron con "
            "un título derivado del nombre de archivo (las citas no cruzarán con "
            "Biblioteca hasta agregarlos a common.py):"
        )
        for nombre in sin_titulo:
            print(f"  - {nombre}")

    if args.dry_run:
        print("\n--dry-run: no se escribió nada en el índice.")
        return 0

    # ------------------------------------------------------------- embeddings
    pendientes = conn.execute(
        """SELECT c.id, c.texto, c.contexto_busqueda FROM chunks c
           LEFT JOIN embeddings e ON e.chunk_id = c.id
           WHERE e.chunk_id IS NULL OR e.modelo != ?
           ORDER BY c.id"""
        , (common.EMBED_MODEL,)
    ).fetchall()

    if not pendientes:
        print("\nTodos los chunks ya tienen embedding. Nada que hacer.")
        _resumen(conn)
        return 0

    print(f"\nEmbebiendo {len(pendientes)} chunks con {common.EMBED_MODEL}...")
    inicio = time.monotonic()
    fallidos = 0

    for i, row in enumerate(pendientes, start=1):
        try:
            texto_embedding = (
                f"{row['contexto_busqueda']}\n\nTEXTO DEL LIBRO:\n{row['texto']}"
                if row["contexto_busqueda"]
                else row["texto"]
            )
            vector = common.embed(texto_embedding, is_query=False)
        except RuntimeError as exc:
            fallidos += 1
            print(f"  ! chunk {row['id']}: {exc}", file=sys.stderr)
            if fallidos >= 10:
                print(
                    "\nDemasiados fallos seguidos. ¿Ollama sigue vivo? "
                    "El progreso ya guardado se conserva; volver a correr retoma "
                    "donde quedó.",
                    file=sys.stderr,
                )
                conn.commit()
                return 1
            continue

        fallidos = 0
        conn.execute(
            "INSERT OR REPLACE INTO embeddings (chunk_id, modelo, dim, vector) "
            "VALUES (?, ?, ?, ?)",
            (row["id"], common.EMBED_MODEL, len(vector), common.pack_vector(vector)),
        )

        if i % 50 == 0 or i == len(pendientes):
            conn.commit()
            transcurrido = time.monotonic() - inicio
            ritmo = i / transcurrido if transcurrido else 0
            restante = (len(pendientes) - i) / ritmo if ritmo else 0
            print(
                f"  {i}/{len(pendientes)}  ({ritmo:.1f}/s, "
                f"~{restante / 60:.1f} min restantes)"
            )

    conn.execute(
        "INSERT OR REPLACE INTO meta (clave, valor) VALUES ('ultima_ingesta', ?)",
        (time.strftime("%Y-%m-%dT%H:%M:%S"),),
    )
    conn.execute(
        "INSERT OR REPLACE INTO meta (clave, valor) VALUES ('modelo_embedding', ?)",
        (common.EMBED_MODEL,),
    )
    conn.commit()
    _resumen(conn)
    return 0


def _resumen(conn) -> None:
    chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    vectores = conn.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]
    libros = conn.execute("SELECT COUNT(DISTINCT libro) FROM chunks").fetchone()[0]
    tamano = common.DB_PATH.stat().st_size / 1024 / 1024
    print(
        f"\nÍndice listo: {chunks} chunks · {vectores} vectores · {libros} libros "
        f"· {tamano:.1f} MB\n{common.DB_PATH}"
    )


if __name__ == "__main__":
    raise SystemExit(main())
