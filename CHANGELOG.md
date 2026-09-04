# Changelog

Todas las entradas notables de GuitarPracticeLab se documentan en este archivo.

> Este archivo se creó recién el 2026-07-31 — no incluye el historial de funciones ya construidas
> antes de esa fecha (Test Integral, Progreso, Grabaciones, catálogo de ejercicios, etc.). Pedile a
> Claude Code que lo reconstruya si lo querés completo.

## 2026-09-04

### Agregado — Conversaciones separadas y práctica guiada

- **Profesor IA tiene conversaciones independientes.** Crear, seleccionar, renombrar y eliminar una
  conversación ya no mezcla su historial con las demás. Los mensajes existentes se conservan en
  “Conversación anterior”; una respuesta que está en curso vuelve a la conversación donde se pidió,
  aunque el usuario cambie de chat. El esquema sube a `SchemaV7` y la exportación JSON conserva la
  relación conversación–mensaje.
- **“Iniciar plan” ejecuta el día completo.** Hoy abre las tareas compatibles en el orden del plan;
  al cerrar cada tramo, “Guardar y siguiente” registra su sesión y continúa con la siguiente sin
  obligar a volver al Dashboard. Mástil conserva su entrenador especializado.
- **Evaluación práctica con micrófono.** Habilidades ofrece una línea base inicial y revisiones
  mensuales breves. El análisis local mide señal, ataques, regularidad, continuidad y recorrido de
  afinación según el reto, y guarda evidencia objetiva de ejecución/retención sin subir audio.
- **Laboratorio de ritmo.** Academia agrega una pestaña Ritmo para negras, corcheas, tresillos,
  semicorcheas, quintillos y seisillos. Mide el adelanto/atraso de cada toque, puede silenciar cada
  cuarto compás y guarda la sesión con BPM, figura y precisión.
- **Comparación con toma de referencia.** Grabaciones permite elegir otra ejecución del mismo pasaje;
  compara secuencia de notas, cobertura y proporciones rítmicas aunque ambas estén a distinto tempo.
  Sin referencia mantiene el puntaje conservador de tempo y regularidad.

### Cambiado — Menos ruido para el uso diario

- Tareas abre en “Hoy” y permite alternar entre pendientes, próximas y completadas, además de buscar.
  Sesiones pasa al bloque “Más” del menú sin perder ninguna función.
- La sincronización de catálogos, evidencias y coach se mueve después del primer frame y se ejecuta
  una sola vez por apertura, reduciendo trabajo síncrono al iniciar.
- **Tests: 161 → 172.** Cobertura nueva para separación/migración de conversaciones, calendario y
  puntuación de audio, comparación con referencia y matemática de la rejilla rítmica. Suite completa sin fallos.

## 2026-09-03

### Agregado — Búsqueda externa confiable en Profesor IA

- Cuando el alumno pide explícitamente buscar en Internet, la conversación estándar activa Google
  Search grounding en Gemini, prioriza fuentes primarias y autoritativas, contrasta evidencia cuando
  corresponde y conserva debajo de la respuesta los enlaces que la API marcó como soporte real.
- Las preguntas normales continúan usando solo el contexto RAG personal. Una búsqueda externa nunca
  cae silenciosamente al modelo local y falla de forma explícita si no obtiene fuentes verificables.
- El modo Avanzado también debe usar su herramienta web ante una petición externa y aplicar los
  mismos criterios de autoridad, contraste, atribución y resistencia a instrucciones dentro de páginas.

### Cambiado — Plan diario y duraciones del repertorio

- Seleccionar el nombre de una tarea en Hoy o Tareas abre su ejercicio, canción, concepto, clase o
  módulo de origen; las tareas manuales abren el cronómetro ya seleccionadas. El cronómetro también
  respeta la tarea recién pulsada si había un borrador de otra sesión, cerrando antes ese tramo.
- La rutina adaptativa de memorización del mástil baja a 7 minutos y el calentamiento cromático a
  6 minutos, incluida la migración de tareas pendientes, instrucciones y planes generados por IA.
- Repertorio sincroniza automáticamente con la API pagada de Gemini las canciones nuevas,
  renombradas o no comprobadas en 30 días. Un botón permite forzar el lote completo; las respuestas
  inciertas se descartan y las tareas diarias vinculadas recalculan su presupuesto.

### Cambiado — Gemini 3.8 Flash como proveedor principal

- El modelo predeterminado pasa a `gemini-3.8-flash`; las instalaciones que conservaban un modelo
  predeterminado 3.5, 3.6 o 3.7 migran una vez, sin reemplazar identificadores personalizados.
- Si 3.8 se satura o agota su tiempo, la misma llamada se intenta una vez con `gemini-3.7-flash`
  antes de recurrir al respaldo local.
- El medidor de consumo reconoce las tarifas de 3.8, incluidos entrada en caché, salida y tokens de
  razonamiento, para que el tope mensual siga protegiendo el gasto.

## 2026-08-22

### Cambiado — Menos fricción para empezar y cerrar una práctica

- **Hoy prioriza el plan.** El plan diario y el acompañamiento aparecen antes que métricas y
  gráficos. La primera apertura muestra un onboarding corto para fijar tiempo disponible e
  instrumento habitual; el Test Integral pasa a ser opcional y puede retomarse por partes.
- **Menú lateral más compacto.** Las 17 secciones se conservan, pero quedan agrupadas en cuatro
  bloques desplegables: Día a día, Aprende, Acompañamiento y Más. El bloque secundario parte cerrado.
- **Cronómetro en tres etapas.** Preparar concentra tarea, instrumento y objetivo; Practicar deja a
  la vista reloj, método y metrónomo; Cerrar pide la evaluación y notas antes de guardar.
- **Respaldos verificables.** Se publican solo después de completar la copia, incluyen un manifiesto
  con tamaño y SHA-256 por componente y se validan antes de restaurar. Guardar a mano informa los
  errores en vez de descartarlos silenciosamente.
- **Solicitudes Gemini coordinadas.** Dos solicitudes idénticas simultáneas comparten la misma
  operación y el caché efímero de 60 segundos usa la clave exacta del modelo y el prompt.
- **Accesibilidad y lenguaje.** Controles solo con icono y gráficos principales tienen descripciones
  para VoiceOver; los textos de acción se unifican en español neutro.
- **Tests: 124 → 127.** Cobertura nueva para respaldo completo y alterado, solicitud Gemini en vuelo
  y conteo inicial de la sección activa. Suite completa sin fallos.

## 2026-08-18

### Agregado — Enriquecimiento en lote del catálogo de Biblioteca con IA local

- **Nuevo botón en Configuración, "Enriquecer catálogo de Biblioteca".** Recorre los ejercicios y
  conceptos que todavía no tienen vínculo de habilidad propuesto por IA y le pide al modelo local
  `qwen3.8-unsloth:ud-q4-k-xl` (`LocalModelTier.qwen38_27b`, agregado solo para esta tarea) cuáles
  practica cada uno. El resultado (`LibraryExercise`/`LibraryConcept.aiSkillIDs`) se suma al matching
  por texto que ya usaba `SkillAssessmentCoachService`, sin reemplazarlo — mejora la evidencia real
  detrás de Perfil de dominio y "Comprobar ahora" donde el vocabulario del catálogo no calzaba
  literalmente con el nombre de la habilidad.
- Corre siempre en el gateway local (`AIOrchestrator.localBackend(forcing:)`, nuevo) y nunca intenta
  Gemini — clasificar miles de ítems por la API pagada no tenía sentido. Solo se inicia a mano (nunca
  automático, para no competir con Logic Pro por RAM/GPU sin avisar), se puede pausar en cualquier
  momento y retoma donde quedó, incluso entre reinicios de la app, porque el progreso vive en los
  propios modelos (`aiSkillsEnrichedAt`).

## 2026-08-16

### Cambiado — Rendimiento del catálogo, tope de gasto y robustez del respaldo local

- **El catálogo deja de cargarse nueve veces.** Quedaban nueve `@Query` sin filtro sobre
  `LibraryExercise` (1.561 filas) y `LibraryConcept` (963) en Buscar, Academia, Repertorio, Progreso,
  el detalle de una habilidad, la autoevaluación, Profesor IA y Profesor Avanzado. Cada uno ordenaba
  el catálogo completo al abrir la pantalla y lo volvía a traer ante cualquier cambio del store,
  incluso guardar una sesión. Ahora las pantallas que lo necesitan al renderizar lo comparten
  (`LibraryLookup.Catalog`, invalidado por conteo) y las que solo lo usan para armar un prompt lo
  piden recién al ejecutar la acción.
- **Tope mensual de gasto en Gemini.** Configuración registraba el consumo pero no lo frenaba. Ahora
  acepta un tope en dólares: al alcanzarlo la app sigue funcionando con el gateway local, y si el
  gateway está apagado la función avisa con el monto exacto en vez de gastar.
- **Ventana anti-doble-cobro de 60 s.** Dos llamadas idénticas seguidas (doble clic en "Generar", una
  vista que se recompone y relanza su tarea) ya no se pagan dos veces. No es un caché de resultados:
  "sugerir de nuevo" un minuto después sigue dando una respuesta distinta.
- **El respaldo local ya no falla por el formato.** `JSONAIParser` acepta el JSON dentro de un bloque
  de código o precedido de prosa, que es como responden los modelos de Ollama. Antes eso daba
  "respuesta inválida" justo cuando Gemini no estaba disponible.
- **Uso de las secciones, en Configuración.** Conteo local de aperturas por sección del menú (17 hoy),
  ordenado de más a menos usada, con las nunca abiertas en 0. Sin red ni IA, reiniciable. Es para
  decidir con datos propios qué parte de la app merece trabajo y cuál sobra, antes de seguir sumando.
- **Tests: 103 → 124.** Nuevos: parseo de respuestas de IA mal formadas (bloque de código, prosa,
  JSON truncado, campos faltantes), migración real de un store `SchemaV1` en disco hasta `SchemaV5`, y
  el conteo de uso por sección.
- **Archivos partidos.** `InventoryViews.swift` (1.205 líneas, cuatro pantallas sin relación) se
  separó en `InstrumentsView`, `StudioView`, `SkillsView` y `ProgressOverviewView`; `LibraryView` y
  `RepertoireView` soltaron sus paneles y su formulario de canción a archivo propio.

### Agregado — El Profesor IA lee el texto real de los libros (RAG vectorial)

- Nuevo servicio local `Tools/book-rag`: indexa el texto **completo** de los 19 libros de método
  (2.366 páginas ya extraídas en `_catalogo_ejercicios/extracted/`) en 1.186 pasajes con embeddings
  `nomic-embed-text`, y los recupera por búsqueda híbrida (coseno + FTS5/BM25 fusionados por RRF).
  Índice en `~/Library/Application Support/GuitarPracticeLab/RAG/libros.sqlite3` (~11 MB).
- Hasta ahora la app solo veía **resúmenes de una o dos líneas** de cada ejercicio y concepto del
  catálogo. `LibraryBook.matchingPages` sí tocaba el PDF, pero hacía coincidencia de subcadena y
  devolvía los primeros 160 caracteres de la página, no el fragmento que coincidía — en los libros
  traducidos de Stetina eso devolvía el crédito del traductor. Ninguna de las dos vías entendía una
  pregunta que no compartiera literalmente las palabras del libro.
- `LearningContextBuilder.build` acepta `bookPassages:` y agrega una sección **PASAJES TEXTUALES DE
  LOS LIBROS**, con la misma etiqueta de cita (`Libro, p. N`) que ya usaban las demás fuentes, así
  que las citas del chat siguen cruzando con Biblioteca.
- Alcanza a Profesor IA (chat), Semana, Escalera, Videos, Groove y Profesor IA → Avanzado.
- Limpieza de la fuente: se quitan encabezados y pies repetidos en casi todas las páginas de un
  libro, índices, páginas en blanco y las frases que el extractor de PDF duplicó. El corpus bajó de
  1.334 a 1.186 chunks sin perder contenido.
- Los pasajes de los cuatro libros escaneados se marcan como OCR en el propio contexto, para que el
  modelo no cite ruido de reconocimiento óptico como si fuera texto literal.
- **Degradación:** si el servicio o Ollama están apagados, `BookPassageService.searchQuietly`
  devuelve `[]` y el contexto queda idéntico a como era antes. La app no depende del índice.
- `project.yml` excluye `Tools/**` para que el servicio en Python no termine dentro del bundle.

## 2026-08-15

### Cambiado — Gemini pagado principal con respaldo local

- Toda la IA generativa, excepto **Profesor IA → Avanzado**, usa la clave pagada de Gemini como
  primer intento. Hermes permanece sin cambios en Avanzado.
- El modelo predeterminado pasa a `gemini-3.7-flash`; instalaciones que conservaban 3.5/3.6 se
  migran una vez y el campo sigue editable en Configuración.
- Ollama deja de ser el proveedor primario, pero se conserva como respaldo automático cuando el
  modelo apropiado cabe en memoria y el gateway está disponible. Los motores locales de audio no
  cambian.
- Configuración elimina la segunda clave de la capa gratuita y muestra un medidor mensual de
  llamadas, tokens y costo estimado a partir de `usageMetadata`, incluidos tokens de razonamiento.
- Las respuestas de Profesor IA muestran y conservan una etiqueta con el proveedor efectivo:
  `Gemini 3.7 Flash` o el modelo local que entró como respaldo. En Videos, la etiqueta del plan se
  presenta separada de los resultados, que continúan verificados mediante YouTube Data API.

## 2026-08-14

### Cambiado — Semana usa la API Gemini de pago

- **Profesor IA → Semana** deja la clave separada de la API Gratuita y usa la misma clave y modelo
  Gemini del proyecto con facturación que el chat del Profesor. No existe fallback silencioso a la
  API gratuita ni al gateway local.

## 2026-08-13

### Agregado — Catálogo evolutivo y dificultad objetiva del repertorio

- "Agregar canción" deja de aceptar coincidencias parciales mientras se escribe: identifica por
  título, artista y parte de guitarra normalizados, evitando asignar la primera canción parecida.
- Las canciones nuevas se analizan una sola vez en seis dimensiones observables; una fórmula local
  fija calcula la nota final. Se intenta Gemini gratuito para conocimiento musical y se usa la IA
  local si no está disponible.
- Cada ficha guarda fuente, confianza, desglose, explicación y fecha. Solo resultados de confianza
  suficiente entran al catálogo evolutivo; después se reutilizan sin nuevas llamadas de IA.
- Al agregar o editar una banda, "Ampliar catálogo" analiza en lote entre cinco y ocho canciones
  representativas. La dificultad también puede confirmarse manualmente y queda auditada como tal.
- `SchemaV4` incorpora `SongDifficultyRecord` mediante migración ligera y las canciones conservan
  una copia de su evaluación para búsquedas, exportaciones y servicios de coaching.

### Agregado — Entrenamiento adaptativo de notas del mástil con guitarra

- Nueva sección **Mástil** para practicar con la guitarra en mano. Formula preguntas de nota+cuerda
  y recorridos de una misma nota por las seis cuerdas entre los trastes 1 y 13.
- El micrófono reconoce localmente frecuencia, nota y octava con análisis YIN; la actividad no se
  valida mediante un botón. Requiere una nota por vez y muestra nivel de entrada, afinación en cents
  y feedback inmediato de la posición esperada.
- Al cambiar de consigna espera dos buffers de silencio antes de volver a escuchar, de modo que el
  sustain de la respuesta anterior no conteste automáticamente la siguiente; el tiempo de respuesta
  tampoco corre mientras pide silenciar. Se eliminaron las preguntas cuerda+traste→nota porque la
  posición indicada permitía acertar tocándola sin haber identificado su nombre.
- El diagnóstico y los niveles 1–3 trabajan notas naturales en las seis cuerdas. Al llegar al nivel 4
  se incorporan gradualmente sostenidos y bemoles, alternando sus nombres enarmónicos.
- Las primeras 18 respuestas calibran el nivel. Después, cada nota/cuerda conserva precisión,
  velocidad, racha y BPM dominado; los fallos reaparecen dos preguntas más tarde con la consigna
  invertida y una sesión estable aumenta tempo y dificultad.
- Se crea una tarea prioritaria de al menos 10 minutos todos los días. Completar el reloj registra
  una sesión, programa automáticamente la tarea de mañana y conserva el tempo recomendado; terminar
  antes guarda el aprendizaje por nota, pero mantiene la tarea pendiente.
- `SchemaV3` agrega el perfil y progreso del mástil mediante migración ligera. La exportación JSON
  sube a formato 5 e incluye ambos, y nueve pruebas cubren geometría del diapasón, adaptación,
  persistencia/recurrencia y detección de tonos de guitarra con armónicos.

## 2026-08-12

### Agregado — Mapa de dominio basado en evidencia

- El Test Integral deja de ser la única medida: su resultado queda visible como estimación inicial
  separada y cada habilidad calcula además un dominio demostrado en seis dimensiones —
  Reconocimiento, Comprensión, Ejecución, Aplicación musical, Transferencia y Retención — con nivel
  de confianza y trazabilidad hasta la fuente.
- Nuevo `SkillEvidence` persistente y `SkillMasteryEngine` 100% determinístico. Recibe señales del
  test, sesiones, BPM/repeticiones/tensión/contexto, pruebas en frío, progreso de Biblioteca y
  Repertorio, flashcards, preguntas de Academia y Entrenamiento de oído. El mismo tipo de fuente no
  puede sustituir dimensiones ausentes y una técnica no llega a Consolidado sin aplicación,
  transferencia y retención suficientes.
- Habilidades muestra el perfil completo, prerrequisitos curriculares, evidencia faltante y el botón
  **Comprobar ahora**. Este crea una tarea de 5-10 minutos con habilidad, dimensión y criterio de
  éxito explícitos, usando Biblioteca o Repertorio cuando hay material relacionado.
- Tareas, cronómetro, sesiones, recurrencia y exportación conservan el objetivo verificable. Un logro
  durante el estudio vuelve automáticamente como revisión en frío; completar o editar la sesión
  actualiza la misma evidencia sin duplicarla, y eliminarla retira también su evidencia.
- Grabaciones → **Analizar toma** permite elegir una habilidad y registrar evidencia objetiva de
  Ejecución o Aplicación musical. Solo puntúa coincidencia de tempo y regularidad entre ataques;
  muestra notas y bends, pero no los califica sin una referencia musical objetivo.
- Hermes continúa sin permisos de escritura, pero ahora recibe el perfil y el grafo de prerrequisitos.
  Puede devolver una tarjeta de reto estructurada que el usuario debe **Descartar**, **Agregar al
  plan** o **Practicar ahora**; recién esa confirmación escribe en SwiftData.
- `SchemaV2` agrega el libro mayor con migración ligera y backfill idempotente de respuestas,
  catálogo y sesiones existentes. La exportación JSON sube a formato 4 e incluye el libro mayor; el
  CSV agrega dimensión y criterio. Ocho pruebas nuevas cubren reglas de dominio, persistencia,
  propuestas de Hermes, audio objetivo y revisión en frío.

### Mejorado — Rangos de logros de Hierro a Challenger

- Cada logro tiene ahora un rango propio calculado desde su progreso: Hierro, Bronce, Plata, Oro,
  Platino, Esmeralda y Diamante recorren las divisiones IV, III, II y I; Maestro, Gran Maestro y
  Challenger cierran la escalera. Challenger solo se alcanza al completar el objetivo.
- Progreso muestra el rango con color, la barra de avance y el siguiente rango alcanzable con su
  requisito exacto. Los logros ya ganados conservan sus IDs y aparecen en Challenger.

### Agregado — Profesor IA avanzado con Hermes

- Nuevo modo **Avanzado** dentro de Profesor IA. Usa la API Runs de Hermes como chat separado, sin
  cambiar el Profesor Gemini, Ollama ni las funciones estructuradas existentes.
- Respuesta por streaming SSE, progreso de herramientas, cancelación real del run y conversación
  persistente en Application Support. El contexto se arma con el RAG existente de clases,
  habilidades, Biblioteca, repertorio, sesiones y tareas.
- Primera versión deliberadamente de solo lectura: Hermes no recibe acceso directo a SwiftData y
  cualquier solicitud de aprobación se deniega. El perfil recomendado deshabilita terminal,
  archivos, ejecución de código, cron y delegación.
- Configuración independiente para host/clave de Hermes, guardada en Llavero, y comprobación tanto
  del gateway como de un proveedor autenticado. Se agregaron tests del parser SSE, normalización
  segura de host y persistencia del historial.

## 2026-08-10

### Agregado — 3 nuevos usos de IA: resumen semanal, mensaje de insignia, equipo/tono

- **Progreso → "Resumen de la semana"**: botón (solo si hay al menos 4 sesiones en la ventana,
  mismo piso que usa "Rutina") junto a la racha actual que pide a la IA local 2-4 oraciones narrando
  cómo estuvo la semana de práctica, a partir de las mismas señales ya calculadas por
  `RoutineAnalytics` (`RoutineCoachService.narrateWeek`, nunca inventa números). Solo lectura, bajo
  demanda, no se guarda.
- **Insignias → mensaje personalizado**: el popover de cualquier insignia ya ganada suma un botón
  "Generar mensaje" que pide a la IA local 1-2 oraciones de felicitación citando la insignia real y
  la racha actual (`BadgeCoachService.swift`, archivo nuevo). Bajo demanda, no automático — no hay
  detección de "insignia recién ganada" ni notificación flotante, se pide al tocar cualquier insignia
  ganada, vieja o nueva.
- **Repertorio → "Sugerir equipo/tono"**: en el formulario de una canción, nuevo botón que pide a la
  IA local una recomendación de ampli/pedales/ajustes de 2-4 oraciones citando solo el equipo
  (`StudioAsset`) e instrumentos (`Instrument`) reales del alumno (`GearCoachService.swift`, archivo
  nuevo). Solo lectura, no se guarda en las notas de la canción.

### Agregado — Minutos por habilidad en Progreso

- **Progreso → "Minutos por habilidad"**: nueva tarjeta con selector Hoy/Esta semana/Este mes que
  muestra cuánto practicaste cada habilidad puntual del catálogo (ej. "Alternate picking"), no solo
  la categoría amplia (Técnica). Una sesión se resuelve a una habilidad cuando está vinculada a un
  ejercicio o concepto de Biblioteca cuyo campo técnica/categoría matchea el nombre de una habilidad
  (`ProgressAnalytics.resolvedSkill`, mismo emparejamiento por texto que ya usa `suggestedExercises`
  para evidencia práctica) — sesiones de registro libre, repertorio, Academia, Profesor IA o Clases
  no se resuelven a ninguna habilidad puntual, solo cuentan en las métricas de categoría existentes.

### Agregado — Entrenamiento de oído e Insignias

- **Entrenamiento de oído** (Academia de teoría → pestaña "Oído"): reconocimiento de 11 intervalos
  melódicos y 5 calidades de acorde, con audio sintetizado en el momento (`EarTrainingAudioEngine`,
  mismo patrón de `AVAudioSourceNode` que el metrónomo — sin archivos ni IA) a partir de una raíz
  aleatoria en cada pregunta. Repetición espaciada con caja Leitner sobre los 16 ítems fijos
  (`EarTrainingProgress` + `EarTrainingScheduler`, copia literal del mecanismo de las flashcards de
  teoría), sesión de 12 preguntas con feedback inmediato, y una vista de precisión por ítem.
  `EarTrainingStats` guarda la racha de aciertos consecutiva (actual y mejor) para las insignias.
- **Sistema de insignias** (Progreso → nueva sección "Insignias"): ~75 insignias 100% determinísticas
  (sin IA) en 8 categorías — Constancia (rachas y "vuelta al ruedo"), Técnica (una por habilidad en
  Avanzado + nivel promedio + "Especialista"), Teoría (una por módulo Consolidado + flashcards + nivel
  promedio), Repertorio (canciones dominadas, sección completa, banda favorita, setlist de banda
  tributo), Biblioteca (ejercicios dominados, "Explorador", libro completo), Sesiones (horas totales,
  "Metrónomo firme"), Oído (primer ejercicio, racha de aciertos, intervalos/acordes dominados) y Meta
  ("Semana integral", "Coleccionista"). Catálogo puro en `BadgeCatalog.swift`; `BadgeEvaluator.swift`
  otorga (`EarnedBadge`, nunca revoca) evaluando en los mismos puntos donde ya se registraban subidas
  de nivel (`ProgressTracker.recordIfLevelUp`) más el guardado de una sesión y el fin de una sesión de
  flashcards/oído. La UI (grilla en `InventoryViews.swift`) es de solo lectura, nunca inserta.
- 13 tests nuevos en `Tests/` (matemática MIDI→Hz, repetición espaciada de oído, otorgamiento de
  insignias sin duplicados con un `ModelContainer` en memoria) — 40 tests en total.

## 2026-08-09

### Agregado — Tareas de Biblioteca/Repertorio persistentes hasta Dominado, luego revisión cada 15 días

- Una tarea vinculada a un ejercicio de Biblioteca o canción de Repertorio (`sourceKind
  .library`/`.repertoire`) ahora se vuelve a agendar sola al completarse, mientras el ítem
  vinculado no esté "Dominado": todos los días si está en aprendizaje/consolidación/tempo
  reducido. Antes, una vez marcada como hecha, la tarea no volvía a aparecer.
- Al marcar un ejercicio o canción como "Dominado" (en Biblioteca o Repertorio), el estado
  guardado pasa solo a "Revisión periódica" (`ExerciseStatus.periodicReview`, ya existía en el
  modelo pero no se usaba); desde ahí, la tarea se reagenda cada 15 días en vez de a diario. El
  hito de "Dominado" en Progreso se sigue registrando igual.
- Tareas manuales o sugeridas como texto libre (sin origen) no cambian: sin ciclo de dominio.
- Lógica nueva en `RecurringPracticeScheduler.swift` (función pura `nextOccurrence`, testeada en
  `Tests/RecurringPracticeSchedulerTests.swift`, mismo patrón que `PracticeReminderPlanner`) +
  `RecurringPracticeService` (resuelve el origen vía SwiftData y crea la próxima tarea, sin
  duplicar si ya hay una pendiente). Se engancha al completar una tarea desde el timer
  (`PracticeTimerView.swift`) o desde el check de Tareas/Dashboard (`TaskRow` en
  `DashboardView.swift`). `PracticeTask` suma `completedAt: Date?`.

## 2026-08-07

### Agregado — Respaldo, recuperación, metrónomo y 6 mejoras más

**Datos (lo que faltaba y era riesgo real):**

- **Respaldo y exportación** (Configuración → "Respaldo y exportación"): respaldo automático semanal
  del store completo, respaldo manual (⌘⇧B), lista de los 8 más recientes con tamaño y borrado, y
  exportación a JSON legible + CSV de sesiones a la carpeta que elijas (`DataBackupService.swift`,
  `DataExportService.swift`). Antes no había ninguna salida de datos ni copia de seguridad.
- **Esquema versionado y pantalla de recuperación**: `SchemaV1` + `AppMigrationPlan`
  (`AppSchema.swift`). El `fatalError` del arranque —la app se cerraba sola si el store no abría—
  se reemplazó por `DatabaseRecoveryView`, que muestra el error, lista los respaldos y restaura +
  reinicia. El store dañado se conserva con sufijo `.danado-<fecha>`, nunca se borra. El respaldo
  automático corre **antes** de abrir el store, para que sea del estado previo a cualquier migración.
- **Target de tests** (`Tests/`, 22 pruebas): recordatorios, CSV de exportación, componentes del
  store, analítica de práctica, rachas y cajas de Leitner. Se corren con
  `xcodebuild -scheme GuitarPracticeLab-Mac test`.

**Corregido:**

- **El cronómetro contaba ticks, no tiempo real**: sumaba un segundo por disparo del `Timer`, así que
  toda pausa del hilo principal (una llamada al gateway) o del sistema descontaba minutos de la
  sesión. Ahora cuenta con reloj de pared (`runStartedAt` + acumulado). Además, cerrar la ventana con
  una práctica en curso la perdía entera: ahora queda un borrador y se recupera **en pausa** al
  volver a abrir el timer.
- **Voseo rioplatense mezclado con tuteo** en ~25 textos de la interfaz y, sobre todo, en los prompts
  de IA —el chat del Profesor pedía responder en español desde un prompt escrito en voseo—. Todo
  unificado a tuteo neutro, con instrucción explícita en el prompt del chat.
- El respaldo del store copiaba solo `default.store` y dejaba afuera `-wal` y `-shm` (el WAL de esta
  base pesa 1,4 MB de escrituras recientes). Cubierto con una prueba de regresión.

**Agregado:**

- **Metrónomo integrado** en el timer (`MetronomeEngine.swift`): click sintetizado en el hilo de
  audio (no se corre aunque la app esté ocupada), acento por compás (2/4, 3/4, 4/4, 6/8), y subida
  automática de tempo (+N BPM cada N minutos) que avanza solo con el cronómetro corriendo. El tempo
  del metrónomo escribe el BPM final de la sesión, que hasta ahora había que anotar a mano.
- **Reproductor de grabaciones** en el detalle de cada grabación: play/pausa, ±5 s, barra de
  posición y velocidad 0,5× / 0,75× / 1× sin cambiar el tono, para sacar un pasaje de la propia toma
  sin salir a Finder.
- **Recordatorios de práctica** (Configuración → Práctica): la app deduce del historial real los días
  y la hora en que sueles practicar y avisa solo esos días, saltando el aviso si ya practicaste ese
  día (`PracticeReminderService.swift`).
- **Comandos de menú**: ⌘N registrar sesión, ⌘R iniciar práctica, ⌘F buscar, ⌘⇧B respaldar. Reemplazan
  el "Nueva ventana" por defecto, que en una app de una sola ventana no aportaba nada.

**Rendimiento:**

- Varias pantallas declaraban `@Query` sin filtro sobre el catálogo entero (2.240 ejercicios y 1.146
  conceptos) aunque solo necesitaran uno. Ahora usan consultas acotadas (`LibraryLookup.swift`):
  el Dashboard pide el catálogo y los textos de los PDFs solo al generar una recomendación, y los
  selectores de ejercicio de Nueva sesión, Clases y el timer usan un buscador con tope de 25
  resultados en vez de un menú de miles de filas.

## 2026-08-06

### Agregado — Coach de Rutina + 5 mejoras de la auditoría de esta semana

- **Coach de Rutina** (nuevo, Profesor IA → "Rutina"): IA local (nunca Gemini) que analiza patrones
  de varias semanas — racha de días, consistencia por día de semana, balance de categorías en el
  tiempo, tendencia de BPM por ejercicio, frecuencia de subidas de nivel — y sugiere 2-4 ajustes a la
  RUTINA (no ejercicios puntuales). Toda la agregación es determinística, sin IA
  (`RoutineAnalytics.swift`); el modelo solo recibe los números ya resumidos. Generar y guardar es un
  solo paso atómico. Indicador de racha y última revisión, sin IA, en Progreso.
- El Dashboard ahora ve tu última sesión y tareas pendientes al recomendar (evita repetirlas), y
  filtra los 1561 ejercicios de Biblioteca a los relacionados con tus habilidades débiles en vez de
  mandarlos todos al modelo local.
- La Escalera de habilidades cita tu evidencia práctica real en vez de inventar el punto de partida
  de cada escalón.
- Academia: botón "Generar pregunta con IA" directo desde un concepto de Biblioteca, sin pasar por
  foto/OCR.
- Reeditar una pregunta de autoevaluación en el detalle de una habilidad ahora recalcula el nivel al
  toque, sin esperar a una Autoevaluación completa.

## 2026-08-05

### Agregado — sesiones vinculadas a su origen al iniciar práctica

- El picker "Tarea" del timer de práctica ("Iniciar práctica") agrupa las tareas pendientes por
  origen — Biblioteca, Profesor IA, Repertorio, Academia, Clases, Manual — en vez de una lista
  plana, con "Sesión libre" siempre primero.
- `PracticeSession` suma `sourceKind`/`sourceID` (mismo mecanismo que ya tenía `PracticeTask`): al
  terminar una práctica iniciada desde una tarea, la sesión queda vinculada a ese mismo origen.
  Sesiones cargadas a mano (formulario "Nueva sesión") siguen sin vínculo, sin cambios.
- Sesiones muestra un botón para volver al origen de cada sesión vinculada, mismo patrón que ya
  usaba Tareas vía `AppNavigator`.

## 2026-08-03 (2)

### Agregado — buscador real de ejercicios, vínculo de tareas a su origen, crear tarea desde una Clase

- **Buscador de Biblioteca → Ejercicios**: ahora también busca por el nombre propio del ejercicio
  (campo `exerciseNumber`, donde vive el `titulo_ejercicio` real del catálogo importado — antes solo
  buscaba libro/colección/técnica/notas). Nuevo botón visible "Agregar a tareas" en el detalle de
  cada ejercicio (antes solo existía oculto en el menú contextual).
- **Vínculo de tareas a su origen**: cada tarea en la pestaña Tareas ahora puede mostrar un botón que
  te lleva de vuelta a de dónde salió — Biblioteca (el ejercicio puntual), Repertorio (la canción),
  Academia (el concepto de teoría), Profesor IA (la pestaña) o Clases (la clase). Nuevo
  `AppNavigator` (`@Observable`) coordina el cambio de sección + foco en el ítem entre todas las
  vistas; nuevo `TaskSourceKind` en `PracticeTask` guarda de dónde vino cada una.
- **Academia → Estudiar**: nuevo botón "Agregar a tareas" por concepto, igual que ya tenía Biblioteca.
- **Clases**: nueva forma de crear una tarea directamente desde una clase ("Crear tarea"), con la
  opción de vincularla a un ejercicio puntual de Biblioteca o una canción de Repertorio — si no se
  elige ninguno, la tarea queda vinculada a esa clase.

## 2026-08-03

### Agregado — menú fijo, categorías de sesiones/tareas, buscador de Biblioteca, pestaña Tareas, Ideas/Backlog

- **Menú lateral fijo**: `Biblioteca` (sus 3 modos) y `Academia → Estudiar` abrían cada uno su propio
  `NavigationSplitView` interno, lo que le quitaba la columna del sidebar al `NavigationSplitView`
  externo de la app — por eso el menú "se perdía" al entrar a esos apartados. Reemplazado por un
  `HStack` simple (lista + detalle) en ambos, sin split view propio.
- **Sesiones y Tareas agrupadas en 5 casilleros**: nuevo `PracticeBucket` (Repertorio / Ejercicios /
  Improvisación / Teoría / Otros) que reagrupa las 8 `PracticeCategory` existentes solo para mostrar
  secciones en la lista — no se tocó el modelo de datos ni las categorías guardadas.
- **Pestaña "Tareas" nueva**: lista todas las `PracticeTask` (antes solo se veían las de hoy, en el
  Dashboard), agrupadas por los mismos 5 casilleros. Permite crear una tarea a mano, marcarla
  completa, abrirla en el timer o borrarla. Biblioteca ahora tiene "Agregar a tareas" en el menú
  contextual de cada ejercicio (antes solo existía desde Dashboard, Repertorio, Habilidades, Buscar
  y el chat del Profesor).
- **Buscador de Biblioteca**: la pestaña "Libros PDF" no filtraba nada pese a mostrar el campo de
  búsqueda — el `List` usaba el array sin filtrar. Ahora filtra por título/autor/nombre de archivo,
  igual que ya hacían las pestañas Ejercicios y Conceptos.
- **Ideas / Backlog en Configuración**: nueva sección simple (modelo `BacklogIdea`) para anotar ideas
  de funciones futuras (manejo de software/amplificadores, trabajo rítmico de groove, etc.) sin
  perderlas entre sesiones — no implica que esas funciones ya estén construidas.

## 2026-08-01 (9)

### Agregado — evidencia práctica en Habilidades, sugerencias del Profesor a la semana, Gemini en el chat

- **Habilidades** ahora muestra el mismo card "Tu nivel general" (porcentaje, banda y lectura en
  prosa) que ya existía en Autoevaluación.
- **Evidencia práctica**: `Song` suma `linkedSkillIDs` — un botón "Sugerir habilidades" (IA,
  confirmable) propone qué habilidades refuerza una canción del repertorio (banda tributo o
  cualquier otra), y el usuario confirma. Los ejercicios de Biblioteca se vinculan solo por
  coincidencia de texto entre `technique` y el nombre/detalle de la habilidad, sin IA ni campo
  nuevo (1561 ejercicios ya importados). Cuando una canción o ejercicio vinculado llega a
  "Dominado", el nivel por habilidad en Habilidades (`SkillTopic.status`) se recalcula combinando
  el resultado fijo del Test Integral con esa evidencia: sube como máximo una banda y nunca baja
  por debajo del test. Nuevo campo `statusIsManual` respeta un nivel elegido a mano en el detalle de
  la habilidad hasta la próxima autoevaluación completa. Nueva sección "Evidencia práctica" en el
  detalle de cada habilidad lista las canciones/ejercicios que la sustentan. El % y la banda
  oficiales del Test Integral no cambian — siguen siendo la fórmula fija del documento del usuario.
- **Profesor (chat)**: cuando la respuesta implica algo concreto para practicar, aparece un botón
  "Agregar a esta semana" por sugerencia que crea la tarea directo. El generador de "Semana" ahora
  también considera las conversaciones recientes con el Profesor al armar el plan.
- **Backend del chat del Profesor cambiado a Gemini 3.5 Flash** (el resto de la app — Semana,
  Escalera, Videos, Groove, Dashboard, Repertorio, Biblioteca, Academia — sigue en el gateway
  local): es el único de los 11 usos de IA con desajuste real entre el contexto que maneja (RAG
  completo) y el modelo local más chico que usaba. Decisión del usuario tras el análisis de costos
  de la sesión anterior. Sin clave de Gemini en Configuración, el chat muestra un error pidiendo que
  se agregue — no cae al gateway local en silencio.

## 2026-08-01 (8)

### Agregado — suite completa de IA aplicada al aprendizaje

- Nueva sección **Profesor IA**, respaldada por el gateway local y dividida en cinco herramientas
  compactas:
  - **Profesor**: chat persistente con RAG sobre clases, habilidades, ejercicios, conceptos,
    páginas reales de PDF, repertorio, sesiones y tareas. Las citas devueltas se validan contra el
    contexto antes de mostrarse; si falta evidencia, el prompt obliga a decirlo.
  - **Semana**: un modelo de razonamiento propone un plan de 1–7 días con fecha, minutos, fuente,
    BPM e instrucciones. Es solo una vista previa hasta pulsar “Guardar plan y agregar tareas”.
    `PracticeTask` incorpora `scheduledDate` y el Dashboard muestra hoy más pendientes vencidos.
  - **Escalera**: crea recorridos por prerrequisitos con práctica y criterio medible por escalón.
    Se guarda como `AIArtifact` únicamente después de confirmarlo.
  - **Videos**: la IA diseña la consulta y el criterio pedagógico, pero los resultados y enlaces
    provienen de la API oficial de YouTube. Nueva clave `youtube-data-api-key` en Llavero.
  - **Groove**: genera una grilla de batería, la previsualiza y, al confirmar, escribe un archivo
    MIDI estándar (canal 10, compatible con Logic/Superior Drummer) en
    `VST/Clases/Proyectos/IA GuitarPracticeLab/Grooves` y crea su tarea de práctica.
- **Inteligencia de audio en Grabaciones**: exportaciones WAV/AIFF/MP3/M4A/CAF/FLAC ahora se pueden
  transcribir con timestamps, analizar (duración, notas, rango, ataques, pitch bends/afinación,
  tempo y tonalidad), convertir a MIDI/CSV y separar en stems. Los resultados quedan enlazados a la
  grabación y los archivos pesados permanecen en el disco externo.
- **Transcripción de clases**: nuevo tipo de adjunto “Audio”. MLX Whisper transcribe localmente y el
  gateway propone temas, indicaciones del profesor y próximo objetivo en campos editables; la clase
  no cambia hasta confirmar “Aplicar”.
- **Visión en Academia**: después de recortar una página PDF, Apple Vision hace OCR local y el
  gateway prepara un borrador de opción múltiple, verdadero/falso o completar. La fuente real sigue
  visible y la pregunta solo se guarda tras revisión manual.
- Nuevos modelos SwiftData `AIArtifact`, `TeacherChatMessage` y `WeeklyPracticePlan`; migración
  liviana verificada sobre la base activa. Respaldo previo en
  `~/Library/Application Support/GuitarPracticeLab-backup-before-ai-suite-2026-08-01/`.
- Motores instalados en entornos Python 3.11 aislados bajo
  `~/Library/Application Support/GuitarPracticeLab/AI`: MLX Whisper, Basic Pitch + ONNX Runtime,
  Demucs y Essentia. FFmpeg/FFprobe se reutilizan desde Homebrew. Configuración muestra su estado,
  el modelo Whisper y el bloqueo protector mientras Logic Pro está abierto.

## 2026-08-01 (7)

### Agregado — raíz única de materiales, buscador global y layout compacto

- Nueva sección **Materiales**: recorre directamente `/Volumes/VST/Clases` y sus carpetas
  (`Clases`, `Libros`, `Musica`, `Proyectos`, etc.), permite entrar en subcarpetas y abrir archivos
  con su aplicación nativa. Los archivos permanecen en el disco externo; no se copian a la app.
- La raíz externa es ahora una configuración única y persistente (`LearningMaterialsService`), con
  bookmark de seguridad, estado conectado/desconectado y selector en Configuración. La ubicación
  predeterminada sigue siendo `/Volumes/VST/Clases`.
- `LibraryIntegrationService` ya no tiene una ruta propia hardcodeada: deriva `Libros` de esa raíz
  compartida. Biblioteca muestra el estado de la fuente y un acceso para abrirla en Finder.
- **Clases** abre directamente `VST/Clases/Clases`. **Grabaciones** puede vincular y escanear
  `VST/Clases/Proyectos` con un botón, conservando la posibilidad de elegir otra carpeta.
- Nueva sección **Buscar**: búsqueda dinámica y transversal por Habilidades, 1.561 ejercicios,
  963 conceptos, libros PDF, canciones, sugerencias de repertorio y nombres de archivos externos.
  Los resultados son accionables: agregar al plan de hoy, aceptar una canción sugerida (incluyendo
  su banda favorita) o abrir el archivo/PDF real.
- Layout adaptable a pantallas pequeñas: mínimo de ventana reducido de 1120×720 a 820×560;
  Dashboard, Academia, Habilidades, Progreso, Biblioteca, Clases y Grabaciones apilan controles y
  columnas cuando falta ancho. También se redujeron los tamaños mínimos de las hojas principales.

## 2026-08-01 (6)

### Integrado — Biblioteca local completa

- La base activa de la app estaba vacía aunque los importadores ya existían. Se integraron
  efectivamente **1.561 ejercicios**, **963 conceptos teóricos** y **18 PDFs fuente** desde
  `/Volumes/VST/Clases/Libros`.
- Nuevo `LibraryIntegrationService`: al detectar el volumen local, sincroniza los catálogos y los
  PDFs de forma idempotente. Si el volumen no está montado, la app arranca normalmente; si el
  catálogo crece, agrega solo entradas nuevas.
- Se corrigió la clave de deduplicación de ejercicios: ahora incluye la descripción. El catálogo
  contiene dos “One-Position Runs” reales en la misma página, uno pentatónico menor y otro mayor;
  la clave anterior los colapsaba erróneamente en una sola fila.
- El selector de PDF del integrador elige la coincidencia de nombre más cercana para evitar que
  “Volume I” se vincule a “Volume II”. Se reparó el vínculo de Metal Rhythm Guitar Volume I.
- Antes de la primera integración se creó un respaldo de la base en
  `~/Library/Application Support/GuitarPracticeLab-backup-before-library-2026-08-01/`.

## 2026-08-01 (5)

### Agregado — Fase 3: Academia de Teoría

- Nueva sección **Academia** en la barra lateral, con cuatro vistas: Resumen, Estudiar, Practicar y
  Preguntas. Los 20 módulos siguen siempre accesibles; no hay bloqueos artificiales.
- **Estudiar** reutiliza los 963 conceptos teóricos importados en Biblioteca: búsqueda, resumen,
  categoría, nivel y referencia real a libro/página, con apertura del PDF cuando puede vincularse.
- **Practicar** combina en una sola sesión las 100 preguntas fijas del Test Integral y las preguntas
  creadas por el usuario. Mantiene repetición espaciada Leitner (0/1/3/7/14 días), priorizando fallos
  y volviendo a comprobar periódicamente lo aprendido.
- Nuevos tipos de pregunta: opción múltiple, verdadero/falso y completar palabra/frase. Las
  respuestas de completar ignoran mayúsculas, tildes y espacios sobrantes.
- **Imágenes desde Biblioteca**: el editor permite elegir un PDF y página, renderizarla con PDFKit,
  arrastrar un rectángulo sobre la página y guardar ese recorte PNG dentro de la pregunta. La fuente
  libro+página queda visible al revisar la respuesta.
- Nuevos modelos `AcademyQuestion` y `AcademyQuestionProgress`, más `AcademyScheduler`,
  `PDFPageRenderer` y `PDFCropSelectionView`.

## 2026-08-01 (4)

### Agregado — catálogo de conceptos de teoría en Biblioteca

- **`LibraryConcept.swift`** (nuevo modelo) + **`LibraryConceptImporter.swift`** (nuevo importador,
  mismo patrón que `LibraryExerciseImporter`): importa `compiled_teoria_guitarra.json` (963 conceptos
  de 17 libros, esquema `{libro, titulo, pagina, tipo, categoria, nivel, resumen}`) compilado por la
  sesión paralela. Dedupe por libro+página+título, igual que el catálogo de ejercicios.
- **Biblioteca**: nueva pestaña "Conceptos" (antes solo "Ejercicios"/"Libros PDF"), con lista +
  detalle + botón "Importar conceptos". Distingue "concepto" de "ejercicio teórico" según el campo
  `tipo` del catálogo de origen.
- Este dataset (`_catalogo_ejercicios/results_teoria/`, ver notas de sesiones anteriores) queda
  **fuera** del plan de 3 fases de Academia/Repertorio/Kaos Etiliko — el usuario pidió explícitamente
  que fuera a Biblioteca, no a la Academia.

## 2026-08-01 (3)

### Agregado — Fase 2 de "Academia/Repertorio/Kaos Etiliko"

- **Setlist de banda tributo**: nueva tarjeta fija "Tu banda: <nombre>" arriba de Repertorio, con las
  canciones cuya `Song.band` apunta a la banda marcada `isTributeProject`. Reutiliza `SongCard` y el
  editor de progreso por sección/debilidades de la Fase 1 — no es un sistema aparte.
- **Edición de bandas**: `NewBandView` ahora soporta editar una banda existente (tocando su fila en
  "Bandas favoritas"), no solo crear una — necesario para poder marcar una banda ya existente como
  "Es tu banda (proyecto tributo)".
- Sin modelo ni servicio nuevo — capa fina sobre `Band`/`Song.band` de la Fase 1, como preveía el plan.

## 2026-08-01 (2)

### Agregado — Fase 1 de "Academia/Repertorio/Kaos Etiliko" (plan de 3 fases, ver `.claude/plans/serialized-humming-fox.md`)

- **`Band.swift`** (nuevo modelo SwiftData): bandas favoritas (marcadas automáticamente al aceptar una
  sugerencia de repertorio, o cargadas a mano) y, más adelante (Fase 2), la banda tributo propia del
  usuario (`isTributeProject`).
- **`Song`**: nuevo `sectionProgress: [SongSectionProgress]` (nombre de sección, aprendida sí/no,
  debilidad anotada — ej. "falta el solo") y `band: Band?` opcional. El campo `sections: String`
  libre existente no se tocó.
- **`SongCoachService.swift`** (nuevo): sugiere ejercicios concretos a partir de la debilidad anotada
  en una sección, mismo patrón prompt→JSON que el resto de los servicios de IA de la app.
- **`SkillAssessmentCoachService.suggestRepertoire`**: ahora también recibe las bandas favoritas y las
  prioriza en el prompt, junto con los gustos musicales de texto libre existentes.
- **Repertorio**: nueva tarjeta "Bandas favoritas" (agregar a mano o automático al aceptar una
  sugerencia), editor de progreso por sección y botón "Sugerir ejercicios" por debilidad dentro de
  cada canción.
- **Fix de infraestructura**: `project.yml` excluía solo el `.xcodeproj`, no `.claude/**` ni
  `.git/**` — un worktree de git generado automáticamente por un agente de exploración quedó adentro
  del glob de fuentes y provocó un build roto (recursos duplicados). Se excluyen ambos directorios
  ahora, de forma permanente.

## 2026-08-01

### Cambiado

- **Backend de IA local migrado de Ollama directo a un gateway unificado compatible con OpenAI**
  (`POST {host}/chat/completions`, `Authorization: Bearer {apiKey}`). Nuevo `LocalGatewayService.swift`
  reemplaza a `OllamaService.swift` (**eliminado** — recuperable desde el historial de git, commit
  baseline previo a esta migración, ya que este repo se inicializó con git recién para este cambio).
- `ResourceMonitor.LocalModelTier` pasó de los 4 tags de Ollama (`qwen3:4b/8b/14b`, `qwen3.6:27b`) a
  10 modelos reales del gateway, agrupados en chicos/rápidos/razonamiento (`qwen3-4b/8b/14b`,
  `qwen3-coder-30b`, `qwen3.6-35b`, `gemma-4-26b`, `qwen3.6-27b`, `mistral-small-24b`,
  `deepseek-r1-distill-32b`, y `llama-3.3-70b` definido pero deliberadamente excluido de la selección
  automática — el usuario prefiere invocarlo a mano desde LibreChat). **Las estimaciones de RAM de
  los 10 modelos son provisorias** (fórmula conservadora parámetros×0.9GB + margen fijo, no medidas
  en esta máquina como sí lo estaban las 4 anteriores vía `/api/ps` de Ollama) — ajustar con uso real.
- `AIOrchestrator` ahora lee `UserDefaults["localGatewayHost"]` (antes `"ollamaHost"`) y la API key
  desde `KeychainStore` (`account: "local-gateway-api-key"`).
- `SettingsView`: sección renombrada "Asistente local" (antes "Asistente local (Ollama)"), con un
  campo nuevo para la clave del gateway.
- Sin cambios en `PracticeCoachService.swift`, `SkillAssessmentCoachService.swift`,
  `JSONCompletionBackend` (`AIBackend.swift`), ni en el `Schema` de `GuitarPracticeLabApp.swift` — el
  contrato que consumen esos servicios no cambió, solo el transporte.

## 2026-07-31

### Agregado

- **Flashcards de teoría** (Fase C del plan de integración de Ollama): repaso con repetición
  espaciada simple (caja Leitner, 5 niveles, intervalos 0/1/3/7/14 días) sobre las 100 preguntas de
  teoría del Test Integral ya existentes — sin contenido nuevo, sin IA. Un solo fallo resetea la
  tarjeta a la caja más urgente. Nuevo botón "Flashcards" en Habilidades, visible solo con el área en
  Teoría. Archivos: `TheoryFlashcardProgress.swift`, `TheoryFlashcardScheduler.swift`,
  `TheoryFlashcardsView.swift`.

- **Contexto de equipo/instrumentos en la recomendación de práctica del Dashboard**:
  `PracticeCoachService.recommendation(...)` ahora recibe el equipo/software (`StudioAsset`) y los
  instrumentos (`Instrument`) registrados, y el prompt le indica al modelo que una instrucción
  concreta y no estándar del profesor (por ejemplo "armá un groove en Superior Drummer antes de tocar
  este ejercicio") tiene prioridad sobre elegir automáticamente una habilidad débil genérica. Esa
  instrucción (`specialInstructions`) se muestra destacada en la tarjeta "Asistente de progreso" del
  Dashboard, se guarda en el nuevo campo `PracticeTask.instructions` al tocar "Practicar esto ahora",
  y sigue visible en el timer de práctica.
