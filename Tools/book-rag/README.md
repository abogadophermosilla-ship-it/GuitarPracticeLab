# book-rag — índice del texto completo de los libros

Servicio local que le da al Profesor IA acceso al **texto real** de los 19 libros de método,
no solo a los resúmenes del catálogo.

## Qué problema resuelve

Antes de esto, la app conocía los libros de dos formas, y ninguna llegaba al contenido:

1. **Catálogo importado** (`LibraryExercise`, `LibraryConcept`): 1.561 ejercicios y 963
   conceptos, cada uno con un `resumen` o `descripcion` de una o dos líneas. Sirve para saber
   *que existe* un ejercicio en la página 112, no para explicar lo que dice esa página.
2. **`LibraryBook.matchingPages`**: coincidencia de subcadena sobre el texto del PDF, que
   además devuelve **los primeros 160 caracteres de la página**, no el fragmento que coincidió.
   En los libros traducidos de Stetina eso significaba devolver el crédito del traductor.

Ninguna de las dos entiende una pregunta que no comparta literalmente las palabras del libro.

Este servicio indexa texto extraído de libros que el usuario aporta y lo recupera por significado
**y** por término exacto a la vez. El repositorio no incluye libros, PDFs ni texto extraído.

## Cómo funciona

- **Troceado por página.** La página es la unidad porque es lo que la app necesita para citar
  ("Fretboard Freedom, p. 112"). Las páginas cortas se agrupan hasta ~2.400 caracteres y se
  guarda el rango completo; una página larga se parte por párrafos con solape.
- **Limpieza.** Se descartan páginas en blanco e índices (se reconocen por los puntos guía), se
  quitan los encabezados y pies que se repiten en casi todas las páginas del libro (el crédito
  del traductor aparecía en las 54 páginas de Heavy Metal Lead Guitar I) y se colapsan las
  frases que el extractor de PDF duplicó. Esto redujo el corpus de 1.334 a 1.186 chunks sin
  perder contenido.
- **Embeddings** con `nomic-embed-text` vía Ollama, usando sus prefijos de tarea
  (`search_document:` / `search_query:`). El texto se normaliza antes de embeberlo: la
  tablatura consume un token por guion y hace que Ollama devuelva HTTP 500 al pasarse de los
  2.048 tokens del modelo.
- **Búsqueda híbrida.** Similitud coseno + FTS5/BM25, fusionadas por Reciprocal Rank Fusion.
  Los nombres de la guitarra son literales ("sweep picking", "Mixolydian") y la búsqueda léxica
  los encuentra mejor; una pregunta como "cómo suelto la mano derecha en pasajes rápidos" no
  comparte una palabra con el texto que la responde y solo la vectorial la alcanza.

## Dónde vive cada cosa

| Qué | Dónde |
|---|---|
| Código | `Tools/book-rag/` (excluido del bundle en `project.yml`) |
| Índice | `~/Library/Application Support/GuitarPracticeLab/RAG/libros.sqlite3` (~11 MB) |
| Texto fuente | `$BOOKRAG_CATALOG_DIR/extracted/` |
| Cliente Swift | `BookPassageService.swift` |

El índice vive en el disco interno a propósito: el texto fuente puede estar en un volumen externo
que no siempre está montado. El índice es dato derivado y se puede reconstruir cuando el volumen
vuelva.

## Uso

Primero indica dónde está el catálogo. Debe contener `manifest.json`, la carpeta `extracted/` y,
si está disponible, `compiled_ejercicios_guitarra.json`:

```bash
export BOOKRAG_CATALOG_DIR="$HOME/Documents/GuitarPracticeLab/BookCatalog"
```

Reconstruir o actualizar el índice (necesita Ollama corriendo y la fuente montada):

```bash
python3 Tools/book-rag/ingest.py
```

Es incremental: identifica cada chunk por el hash de su texto, así que volver a correrlo
después de agregar o reprocesar un libro solo trabaja sobre lo nuevo. `--rebuild` fuerza todo
desde cero; `--dry-run` reporta el troceado sin escribir ni llamar a Ollama.

Levantar el servidor a mano:

```bash
python3 Tools/book-rag/server.py
```

Para que arranque con la sesión, copia
`ai.guitarpracticelab.book-rag.plist.example`, reemplaza sus cuatro marcadores por rutas absolutas y
guarda el resultado en `~/Library/LaunchAgents/ai.guitarpracticelab.book-rag.plist`. Después:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.guitarpracticelab.book-rag.plist
```

## API

Escucha solo en `127.0.0.1:8643` (8642 es el gateway de Hermes). No tiene autenticación: es un
servicio personal y no debe salir de la máquina.

- `GET /health` → conteos, modelo de embedding y fecha de la última ingesta.
- `GET /search?q=...&k=8&libro=...&modo=hibrido|vectorial|lexico`

## Degradación

Si el servicio está apagado o Ollama no responde, `BookPassageService.searchQuietly` devuelve
`[]` y el Profesor IA arma el contexto exactamente como lo hacía antes de que existiera el
índice. **La app nunca debe romperse por la ausencia de este servicio.** Al integrar nuevas
funciones, usar `searchQuietly` y no `search` en cualquier ruta que arme contexto para el modelo.

## Limitación conocida

En los libros traducidos de Stetina el extractor de PDF partió palabras al duplicar el texto
("parén tesis", "lo s"), así que el colapso de repeticiones —que compara palabra por palabra—
no alcanza a esos casos y queda algo de duplicación en el pasaje. No impide recuperar la página
correcta, pero gasta contexto. Arreglarlo pediría comparar a nivel de caracteres, con riesgo de
mutilar texto legítimo; se dejó como está a propósito.

Los cuatro libros escaneados (`*_OCR.txt`) traen ruido de reconocimiento óptico, sobre todo en
tablaturas y diagramas de acordes. Los pasajes de esos libros se marcan con `es_ocr` y el
contexto que recibe el modelo lo advierte explícitamente, para que no cite basura como si fuera
literal. Si algún día hace falta más precisión, en
`_catalogo_ejercicios/images/<libro>/page_NNNN.png` están las páginas como imagen y
`qwen3-vl` podría releerlas.
