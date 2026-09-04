# Estado del proyecto — GuitarPracticeLab

_Última actualización: 2026-09-04 (conversaciones separadas, plan guiado, evaluación práctica y laboratorio de ritmo)._

GuitarPracticeLab-iPad es una app **Mac** (SwiftUI + SwiftData) para llevar el diario de práctica de
guitarra. Un solo target/scheme: `GuitarPracticeLab-Mac`. El nombre de la carpeta menciona iPad por
motivos históricos — el soporte iOS/iPad fue removido a propósito, no está pendiente.

## Funciona hoy

- **Hoy (Dashboard)**: plan de práctica y acompañamiento primero; después, métricas y gráficos. El
  botón “Iniciar plan” encadena todas las tareas compatibles del día en el cronómetro y guarda cada
  tramo antes de pasar al siguiente; el entrenador del mástil mantiene su flujo especializado. La
  primera apertura pide solo metas de tiempo e instrumento habitual; el Test Integral es opcional y
  puede retomarse por partes desde Habilidades. El Dashboard también incluye notas del profesor y "Asistente de
  progreso" (recomendación con botón "Practicar esto ahora") — respaldado por un gateway local
  unificado por defecto (desde 2026-08-01; antes hablaba directo con Ollama), que elige entre modelos
  reales según la tarea y los recursos libres (catálogo podado y remedido el 2026-08-04 tras un
  benchmark propio). La recomendación considera equipo/software e instrumentos registrados, prioriza
  instrucciones concretas y no estándar del profesor sobre elegir una habilidad débil genérica, y
  desde 2026-08-06 también ve tu última sesión y tus tareas pendientes (evita repetirlas) y filtra el
  catálogo de ejercicios a los relacionados con tus habilidades débiles en vez de mandarlo completo.
- **Buscar**: buscador dinámico transversal. Una consulta como "bending" cruza habilidades,
  ejercicios, conceptos teóricos, canciones y sugerencias de repertorio, libros y archivos del
  disco externo. Los resultados permiten agregar práctica al plan, aceptar repertorio u abrir la
  fuente, no son solo texto.
- **Materiales**: explorador integrado de la raíz externa configurable (por defecto
  `/Volumes/VST/Clases`). Permite recorrer y abrir `Clases`, `Libros`, `Musica`, `Proyectos` y las
  demás carpetas sin mover ni duplicar archivos en el disco interno. La misma raíz alimenta
  Biblioteca; Clases abre su carpeta directamente y Grabaciones puede adoptar `Proyectos`.
- **Habilidades → Autoevaluación**: Test Integral fijo, no generado por IA — 18 habilidades de
  técnica (90 preguntas, escala 0-4) + 20 módulos de teoría (100 preguntas, opción única). Cálculo de
  nivel 100% determinístico en Swift. El porcentaje oficial queda visible como **estimación del
  Test Integral**, separado del dominio demostrado; sigue alimentando la escala global de dificultad
  sin presentarse como prueba suficiente de ejecución o aplicación.
- **Habilidades → Perfil de dominio** (nuevo, 2026-08-12): `SkillEvidence` registra cada señal con
  habilidad, dimensión, puntuación, fiabilidad, contexto, fecha, fuente y evaluador. El motor
  determinístico combina Reconocimiento, Comprensión, Ejecución, Aplicación musical, Transferencia y
  Retención, aplica vigencia temporal y reglas de acceso a bandas altas, y muestra una confianza
  Baja/Media/Alta. El detalle incluye las seis barras, prerrequisitos, fuentes reales y la siguiente
  dimensión que falta comprobar. El nivel manual continúa respetándose hasta una nueva
  autoevaluación, pero nunca borra las evidencias.
- **Habilidades → Comprobar ahora** (nuevo, 2026-08-12): genera un reto breve con criterio medible,
  habilidad y dimensión explícitas, usando un ejercicio o canción real cuando existe. Tareas,
  cronómetro y sesiones conservan esos metadatos; una pasada exitosa vuelve a los tres días como
  revisión en frío y sus intervalos crecen al demostrar retención. Editar una sesión actualiza la
  evidencia por clave estable y eliminarla la retira.
- **Habilidades → Evaluación práctica** (nuevo, 2026-09-04): prueba inicial y revisión mensual con
  micrófono. Selecciona retos según nivel y prerrequisitos, analiza localmente ataques, regularidad,
  continuidad y recorrido de afinación, y registra evidencia objetiva de ejecución; la revisión en
  frío también registra retención. No guarda ni sube la grabación.
- **Grabaciones → evidencia objetiva** (nuevo, 2026-08-12): al analizar una toma se puede elegir una
  habilidad y registrar Ejecución o Aplicación musical. Solo la coincidencia con el tempo objetivo y
  la regularidad entre ataques alimentan el dominio; notas, rango y bends quedan visibles en el
  informe, pero no se califican sin una referencia contra la que compararlos.
  Desde 2026-09-04 se puede elegir otra grabación como toma de referencia: el comparador usa la
  secuencia de alturas, cobertura y proporciones entre ataques, por lo que admite interpretaciones
  a distinto tempo sin fingir que puede evaluar musicalidad o bends expresivos.
- **Habilidades → Flashcards de teoría**: repaso con repetición espaciada simple (caja Leitner) sobre
  las 100 preguntas de teoría del Test Integral.
- **Mástil → práctica con guitarra** (nuevo, 2026-08-13): entrenamiento diario que escucha el
  micrófono y comprueba la nota y octava tocadas, sin autocorrección manual. Mezcla consignas de
  nota+cuerda y todas las posiciones de una nota entre los trastes 1-13; deliberadamente no pregunta
  cuerda+traste→nota porque tocar la posición revelada no demuestra haber nombrado la nota. El
  diagnóstico y los niveles 1–3 recorren las seis cuerdas usando solo notas naturales; los sostenidos
  y bemoles, incluidos sus nombres enarmónicos, se desbloquean a partir del nivel avanzado 4. Entre
  consignas exige silenciar la cuerda para que el sustain anterior no produzca otro intento. Las primeras
  18 respuestas diagnostican el nivel; después prioriza las combinaciones nota/cuerda con más fallos
  o mayor demora, reformula un error dos preguntas más tarde y aumenta BPM/nivel cuando la respuesta
  es estable. `FretboardNoteProgress` y `FretboardTrainingProfile` viven en `SchemaV3`; el analizador
  YIN es local (`GuitarPitchDetector`) y la tarea de 7 minutos reaparece cada día.
- **Profesor IA**: centro con chat RAG citable sobre los datos personales y fuentes reales. Desde
  2026-09-04, el chat estándar admite conversaciones independientes con título, creación, selección,
  renombrado y eliminación; cada solicitud recibe solo el historial de su conversación. El historial
  previo se adopta en “Conversación anterior” mediante `SchemaV7`, sin modificar los mensajes. Desde
  2026-09-03, Gemini 3.8 Flash pagado es el proveedor principal del chat, plan semanal y todas las
  funciones generativas; Gemini 3.7 Flash es la alternativa estable inmediata si 3.8 se satura o
  agota su tiempo, y el gateway Ollama se usa como respaldo automático cuando está disponible.
  Si el alumno pide explícitamente buscar en Internet, el chat estándar activa Google Search
  grounding: exige fuentes verificables, prioriza fuentes primarias/autoritativas, muestra enlaces
  persistentes bajo la respuesta y no degrada esa consulta al respaldo local. Las preguntas que no
  lo piden conservan el flujo RAG interno sin búsqueda web.
  La única excepción es Profesor IA Avanzado, que conserva Hermes. El plan semanal también considera
  las conversaciones recientes,
  escalera de habilidades con criterios medibles (desde 2026-08-06 cita la evidencia práctica real de
  cada habilidad en vez de inventar el punto de partida), búsqueda real de videos vía YouTube Data
  API y grooves MIDI adaptativos para Logic/Superior Drummer. Cuando una respuesta del chat implica
  algo concreto para practicar, un botón "Agregar a esta semana" por sugerencia crea la tarea
  directo. **Nuevo, 2026-08-06: "Rutina"** — análisis generativo que procesa patrones de varias
  semanas (racha, consistencia por día de semana, balance de categorías en el tiempo, tendencia de
  BPM por ejercicio, frecuencia de subidas de nivel — todo calculado sin IA en `RoutineAnalytics`) y
  sugiere 2-4 ajustes a la rutina, no ejercicios puntuales; generar y guardar es un solo paso
  atómico. Progreso muestra un indicador de racha y última revisión, sin IA. Todo resultado que
  modifica datos o crea archivos requiere confirmación manual.
- **Profesor IA → Avanzado** (nuevo, 2026-08-12): chat adicional conectado al Runs API de Hermes,
  sin reemplazar el chat Gemini ni las demás herramientas. Recibe un snapshot RAG de solo lectura,
  mantiene historial propio en Application Support, transmite texto y actividad de herramientas por
  SSE y permite detener una ejecución. Cualquier aprobación de herramienta se deniega: Hermes no
  escribe directamente en SwiftData ni en archivos. Sí puede proponer una tarjeta estructurada de
  comprobación basada en el perfil multidimensional y el grafo de prerrequisitos; solo los botones
  confirmables de la app la agregan al plan o abren el cronómetro. Configuración tiene host, clave en
  Llavero y prueba de gateway/proveedor independientes. El perfil local `guitar-practice-lab` se
  ejecuta por launchd en `127.0.0.1:8642`, con terminal/archivos/código/cron/delegación deshabilitados;
  cada instalación todavía debe elegir y autenticar su proveedor con `guitar-practice-lab model`.
- **Academia de Teoría**: sección propia con resumen de retención por módulo, lectura/búsqueda de los
  963 conceptos de Biblioteca, sesiones que mezclan las 100 preguntas fijas con preguntas propias,
  y autoría de opción múltiple, verdadero/falso o completar palabra. Las preguntas pueden incluir un
  recorte creado directamente desde una página de un PDF importado. Todo el pool usa repetición
  espaciada para comprobar periódicamente que lo aprendido no se olvida. Apple Vision puede hacer
  OCR local del recorte y el gateway genera un borrador editable de cualquiera de los tres tipos.
  Desde 2026-08-06, "Generar pregunta con IA" arma un borrador directo desde un concepto de
  Biblioteca (su resumen ya curado), sin pasar por foto/OCR.
  Desde 2026-09-04 incluye un Laboratorio de ritmo que compara cada toque con la rejilla de negras,
  corcheas, tresillos, semicorcheas, quintillos o seisillos, apaga opcionalmente el click cada cuarto
  compás y guarda la precisión como una sesión rítmica.
- **Repertorio**: canciones + archivo Guitar Pro adjunto + sugerencias del asistente. Desde
  2026-08-01: progreso por sección por canción ("sacado intro y
  verso, falta el solo") con sugerencia de ejercicios por debilidad anotada, bandas favoritas (se
  marcan solas al aceptar una sugerencia, o se cargan a mano) que alimentan futuras sugerencias.
  **Nuevo, 2026-08-13**: catálogo evolutivo de dificultad por título+artista+parte, con coincidencia
  exacta normalizada, evaluación en seis dimensiones y fórmula local fija. Una canción desconocida se
  analiza una vez con Gemini pagado o, como respaldo, IA local; guarda fuente/confianza y solo las
  respuestas confiables se reutilizan. Desde una banda se pueden catalogar 5–8 temas en una llamada.
  **Nuevo, 2026-09-03**: la duración exacta del repertorio se completa con Gemini pagado al agregar
  o renombrar una canción y se vuelve a comprobar cada 30 días; el usuario también puede forzar el
  lote completo. Valores dudosos no pisan datos y la tarea diaria vinculada se reajusta al instante.
  **Nuevo, 2026-08-10**: botón "Sugerir equipo/tono" en el formulario de la canción — recomendación de
  Gemini (con respaldo local) recomienda ampli/pedales/ajustes citando solo el equipo real registrado
  (`GearCoachService`), solo lectura.
- **Pasajes textuales de los libros** (nuevo, 2026-08-16): el Profesor IA ya no depende solo de los
  resúmenes del catálogo — puede citar el **texto real** de los 19 libros de método. El servicio
  local `Tools/book-rag` (Python, `127.0.0.1:8643`, launchd opcional) indexa las 2.366 páginas
  extraídas en 1.186 pasajes con embeddings `nomic-embed-text` y los recupera por búsqueda híbrida
  (coseno + FTS5/BM25 fusionados por RRF), porque los nombres de la guitarra son literales pero las
  preguntas del alumno no. `BookPassageService.swift` es el cliente; `LearningContextBuilder` los
  inyecta como sección **PASAJES TEXTUALES DE LOS LIBROS** con la misma etiqueta de cita que el
  resto. Alcanza a chat, Semana, Escalera, Videos, Groove y Avanzado. **Si el servicio o Ollama
  están apagados, `searchQuietly` devuelve `[]` y todo sigue funcionando como antes** — usar siempre
  esa variante, nunca `search`, en rutas que armen contexto. Ver `Tools/book-rag/README.md` para
  reconstruir el índice y para las limitaciones conocidas (OCR y palabras partidas en Stetina).
- **Biblioteca**: ejercicios manuales + catálogo importado de 1561 ejercicios (17 libros) + libros en
  PDF con citas de página reales + catálogo de 963 conceptos de teoría, pestaña "Conceptos" nueva.
  La base activa contiene 1.561 ejercicios, 963 conceptos y 18 PDFs fuente. El
  `LibraryIntegrationService` sincroniza idempotentemente ese corpus desde `Libros`, derivado de la
  raíz compartida de materiales, cuando el volumen está montado y no bloquea el arranque cuando no
  está disponible. Un libro importado desde acá también se indexa para el Profesor IA
  (`BookRAGIndexer`, nuevo 2026-08-18): escribe el texto extraído en el formato de
  `Tools/book-rag/ingest.py` y dispara la ingesta incremental en background, degradando en silencio
  si el PDF no tiene texto extraíble o no hay Python disponible. **Nuevo, 2026-08-18: enriquecimiento
  en lote del catálogo con IA local** — botón en Configuración que recorre ejercicios y conceptos sin
  vínculo de habilidad todavía y propone `aiSkillIDs` con el modelo local dedicado
  `LocalModelTier.qwen38_27b`, sumado (no reemplaza) al matching por texto existente. Nunca usa
  Gemini, solo se inicia a mano, se puede pausar y retoma entre reinicios.
- **Progreso**: tarjetas por materia, sugerencias, hitos de nivel, gráfico mensual. **Nuevo,
  2026-08-10**: tarjeta "Minutos por habilidad" con selector Hoy/Esta semana/Este mes — desglosa la
  práctica por habilidad puntual del catálogo (ej. "Alternate picking"), no solo por categoría
  amplia, resolviendo cada sesión vía el ejercicio/concepto de Biblioteca al que está vinculada.
  También nuevo: botón "Resumen de la semana" junto a la racha actual (IA local narra en 2-4
  oraciones las mismas señales de `RoutineAnalytics`, solo con 4+ sesiones en la ventana) y, en el
  popover de cada insignia ya ganada, botón "Generar mensaje" (IA local felicita citando la insignia y
  la racha real, `BadgeCoachService`) — ambos bajo demanda, solo lectura, sin notificación automática.
- **Grabaciones**: escaneo de la carpeta de Logic Pro, historial de modificaciones y análisis local
  de exportaciones de audio: transcripción con timestamps, audio→MIDI/CSV, notas/rango/timing/pitch
  bend/tempo/tonalidad y separación de stems. Los resultados quedan guardados como `AIArtifact`.
- **Clases**: adjuntos del profesor (PDF/Guitar Pro/DAW/audio/URL) por clase. Un audio puede
  transcribirse localmente y convertirse en una propuesta editable de temas, indicaciones y próximo
  objetivo antes de aplicarla.
- **Sesiones, Instrumentos, Estudio, Configuración**: completos. Configuración tiene una sección
  "Asistente local" (host y clave del gateway, prueba de conexión, RAM/CPU en vivo), Gemini, YouTube
  Data API, Hermes, estado de los motores de audio y la ubicación única de materiales externos.
- **Ventanas compactas**: el mínimo de la ventana principal es 820×560; las pantallas de varias
  columnas y sus hojas principales se apilan o reducen cuando no tienen el ancho de una pantalla
  grande.
- **Menú lateral fijo y compacto** (desde 2026-08-03; reorganizado 2026-08-22): Biblioteca y Academia → Estudiar abrían cada uno su
  propio `NavigationSplitView` interno, que le quitaba la columna del sidebar al de la app — por eso
  el menú se perdía en esos apartados. Reemplazado por un `HStack` (lista + detalle) sin split view
  propio en ambos. Las 17 secciones ahora se agrupan en cuatro bloques desplegables y "Más" parte
  cerrado, sin eliminar ninguna ruta.
- **Sesiones y Tareas agrupadas** (desde 2026-08-03): nuevo `PracticeBucket` reagrupa en la UI las 8
  `PracticeCategory` existentes en 5 casilleros — Repertorio, Ejercicios, Improvisación, Teoría,
  Otros — sin cambiar el modelo de datos ni las categorías guardadas.
- **Pestaña "Tareas"** (nueva, 2026-08-03): lista todas las `PracticeTask` (antes solo se veían las
  de hoy, en el Dashboard), agrupadas por los mismos 5 casilleros. Crear tarea a mano, marcar
  completa, abrir en el timer o borrar. Biblioteca ahora tiene "Agregar a tareas" por ejercicio (los
  demás puntos de creación — Dashboard, Repertorio, Habilidades, Buscar, chat del Profesor — ya
  existían).
- **Buscador de Biblioteca arreglado** (2026-08-03): la pestaña "Libros PDF" no filtraba nada pese a
  mostrar el campo de búsqueda; ahora filtra por título/autor/nombre de archivo igual que Ejercicios
  y Conceptos.
- **Ideas / Backlog en Configuración** (nuevo, 2026-08-03): espacio simple para anotar ideas de
  funciones futuras (software/amplificadores, groove rítmico, etc.) sin perderlas entre sesiones —
  no implica que ya estén construidas.
- **Buscador de ejercicios en Biblioteca** (2026-08-03): la pestaña Ejercicios ahora también busca
  por el nombre propio del ejercicio (`exerciseNumber`, donde vive el título real del catálogo
  importado, ej. "True Blue"), no solo libro/técnica/notas. Botón "Agregar a tareas" ahora visible en
  el detalle del ejercicio, no solo en el menú contextual.
- **Vínculo de tareas a su origen** (nuevo, 2026-08-03): cada tarea en Tareas puede tener un botón
  que abre de dónde salió — el ejercicio puntual en Biblioteca, la canción en Repertorio, el concepto
  en Academia, la pestaña Profesor IA, o la Clase de origen. `AppNavigator` (`@Observable`, inyectado
  en toda la app) coordina el cambio de sección + foco en el ítem; `PracticeTask.sourceKind` guarda
  de dónde vino cada tarea. Academia → Estudiar ganó su propio botón "Agregar a tareas" por concepto.
- **Crear tarea desde una Clase** (nuevo, 2026-08-03): botón "Crear tarea" en cada clase, con opción
  de vincularla a un ejercicio puntual de Biblioteca o una canción de Repertorio — sin elegir
  ninguno, la tarea queda vinculada a esa clase.
- **Sesiones vinculadas a su origen al iniciar práctica** (nuevo, 2026-08-05): el picker "Tarea" del
  timer ("Iniciar práctica") agrupa las tareas pendientes por origen — Biblioteca, Profesor IA,
  Repertorio, Academia, Clases, Manual — con "Sesión libre" siempre primero, en vez de una lista
  plana. `PracticeSession` adoptó `sourceKind`/`sourceID` (mismo mecanismo que `PracticeTask`): la
  sesión resultante queda vinculada a ese mismo origen y Sesiones muestra el mismo botón "volver al
  origen" que ya tenía Tareas. Las sesiones cargadas a mano desde "Nueva sesión" siguen sin vínculo.

- **Entrenamiento de oído** (nuevo, 2026-08-10): Academia de teoría → pestaña "Oído". Reconocimiento
  de 11 intervalos melódicos y 5 calidades de acorde con audio sintetizado en el momento
  (`EarTrainingAudioEngine`, mismo patrón `AVAudioSourceNode` que el metrónomo — sin archivos ni IA),
  raíz aleatoria por pregunta. Repetición espaciada con caja Leitner sobre los 16 ítems fijos
  (`EarTrainingScheduler`, copia del mecanismo de las flashcards de teoría), sesión de 12 preguntas
  con feedback inmediato y vista de precisión por ítem.
- **Insignias** (nuevo, 2026-08-10): Progreso → sección "Insignias". ~75 insignias 100%
  determinísticas (sin IA) en 8 categorías (Constancia, Técnica, Teoría, Repertorio, Biblioteca,
  Sesiones, Oído, Meta) — ver `BadgeCatalog.swift` para el catálogo completo. `BadgeEvaluator.swift`
  otorga (nunca revoca) en los mismos puntos donde ya se registraban subidas de nivel, más guardar
  una sesión o terminar una sesión de flashcards/oído. Desde 2026-08-12 cada logro recorre una
  escalera propia de 31 rangos, de Hierro IV a Challenger, según su progreso hacia el objetivo.
- **Tareas de Biblioteca/Repertorio persistentes hasta Dominado** (nuevo, 2026-08-09): una tarea
  vinculada a un ejercicio o canción se vuelve a agendar sola al completarse mientras el ítem no
  esté "Dominado" (a diario si está en progreso). Al marcar "Dominado", el estado guardado pasa
  solo a "Revisión periódica" (`ExerciseStatus.periodicReview`) y desde ahí la tarea se reagenda
  cada 15 días. Tareas sin origen (manuales o del Profesor) no cambian. Ver `RecurringPracticeScheduler.swift`.
- **Respaldo, exportación y recuperación** (nuevo, 2026-08-07): Configuración tiene "Respaldo y
  exportación" — respaldo automático semanal del store completo (corre *antes* de abrirlo, para que
  sea previo a cualquier migración), respaldo manual (⌘⇧B), los 8 más recientes con tamaño y borrado,
  y exportación a JSON legible + CSV de sesiones. El esquema está versionado (`SchemaV1`/`SchemaV2` +
  `AppMigrationPlan`) y el `fatalError` del arranque se reemplazó por `DatabaseRecoveryView`: si el
  store no abre, la app muestra el error, lista los respaldos y restaura + reinicia, conservando el
  store dañado con sufijo `.danado-<fecha>`. Verificado el 2026-08-07 abriendo una copia de la base
  real con el esquema versionado. `SchemaV3` agrega el progreso adaptativo del mástil y su perfil;
  `SchemaV7` agrega los contenedores del historial de Profesor IA.
  Desde 2026-08-22, cada copia nueva se arma en una carpeta oculta temporal, se publica al final e
  incluye un manifiesto con tamaños y SHA-256; la restauración verifica su integridad antes de tocar
  el store activo. Los respaldos antiguos sin manifiesto siguen aceptándose si tienen el `.store`.
- **Metrónomo y cronómetro confiable** (nuevo, 2026-08-07; flujo por fases 2026-08-22): el timer cuenta con reloj de pared
  (antes sumaba un segundo por tick, así que perdía tiempo cuando el hilo principal se trababa) y
  conserva un borrador de la práctica en curso, que se recupera en pausa si se cierra la ventana. El
  metrónomo (`MetronomeEngine`) sintetiza el click en el hilo de audio, acentúa el primer tiempo del
  compás y puede subir el tempo solo; su BPM escribe el BPM final de la sesión. La interfaz separa
  Preparar, Practicar y Cerrar para no mezclar la selección inicial con la evaluación final.
- **Reproductor de grabaciones y recordatorios** (nuevo, 2026-08-07): el detalle de una grabación
  reproduce el audio (±5 s, posición, 0,5×/0,75×/1× sin cambiar el tono). Configuración → Práctica
  puede activar recordatorios locales, cuyo horario y días salen del historial real de sesiones y
  saltan el aviso del día si ya practicaste.
- **Atajos de menú** (nuevo, 2026-08-07): ⌘N registrar sesión, ⌘R iniciar práctica, ⌘F buscar,
  ⌘⇧B respaldar.
- **Consultas acotadas al catálogo** (2026-08-07; completado 2026-08-16): las pantallas que solo
  necesitaban un ejercicio ya no materializan el catálogo entero. `LibraryLookup` concentra las
  consultas con tope y el `LibraryExercisePicker` reemplaza a los menús de miles de filas de Nueva
  sesión y Clases. El 2026-08-16 se cerraron los nueve `@Query` sin filtro que habían quedado sobre
  `LibraryExercise`/`LibraryConcept`: las pantallas que necesitan el catálogo al renderizar (Buscar,
  Academia, detalle de habilidad, Progreso) lo comparten vía `LibraryLookup.Catalog`, y las que solo
  lo usan para armar un prompt (Profesor IA, Profesor Avanzado, Repertorio, autoevaluación) lo piden
  recién al ejecutar la acción.
- **Tope mensual de gasto en Gemini** (nuevo, 2026-08-16): Configuración → Gemini acepta un tope en
  dólares (0 = sin tope). Al alcanzarlo, `AIOrchestrator` deja de llamar a la API pagada y sigue con
  el gateway local; si el gateway no está disponible, la función avisa con el monto exacto en vez de
  gastar. Se mide con la estimación de `GeminiUsageLedger`, no con la facturación real de Google.
  Además, una ventana de 60 s evita cobrar dos veces la misma llamada idéntica (doble clic, vista que
  se recompone): desde 2026-08-22 también comparte una única operación cuando las llamadas coinciden
  mientras todavía están en vuelo; "sugerir de nuevo" después de la ventana vuelve a consultar.
- **Uso de las secciones** (nuevo, 2026-08-16): Configuración muestra cuántas veces se abrió cada una
  de las 17 secciones del menú, ordenadas de más a menos usada e incluyendo en 0 las que nunca se
  abrieron, con la fecha desde la que se mide y un botón para reiniciar. Conteo local en
  `UserDefaults` (`SectionUsageTracker`), sin red ni IA. Existe para decidir con datos propios qué
  parte de la app merece trabajo, cuál se fusiona y cuál sobra, antes de seguir agregando.
- **Respuestas de IA tolerantes al formato** (2026-08-16): `JSONAIParser` acepta el JSON envuelto en
  un bloque ```` ``` ```` o precedido de prosa, que es como responde el respaldo local de Ollama —
  antes cualquiera de esas dos formas terminaba en "respuesta inválida" justo cuando Gemini no estaba
  disponible. `PracticeCoachService` y `SkillAssessmentCoachService`, que parseaban a mano, ahora usan
  el mismo parser.
- **Target de tests** (nuevo, 2026-08-07; ampliado hasta 2026-09-04): `Tests/` con 172 pruebas
  sobre la lógica determinística (recordatorios, CSV, componentes del store, analítica de práctica,
  rachas, cajas de Leitner de teoría y de oído, matemática MIDI→Hz, otorgamiento de insignias,
  dificultad, Hermes, perfil multidimensional, persistencia de evidencia y revisiones en frío). Desde
  el 2026-08-16 también cubren el parseo de respuestas de IA mal formadas y la migración real de un
  store `SchemaV1` en disco hasta `SchemaV5`; desde 2026-08-22, la integridad de respaldos, la
  coordinación de solicitudes Gemini en vuelo y el conteo inicial del menú; desde 2026-09-04,
  conversaciones del Profesor, evaluación práctica y rejilla rítmica. Se corren con
  `xcodebuild -project GuitarPracticeLab.xcodeproj -scheme GuitarPracticeLab-Mac test`.

## Pendiente

Las cuatro mejoras históricas (gateway unificado, profesor virtual, plan semanal y escalera) y el
roadmap de IA/audio ya están implementados al 2026-08-01. Queda validación manual con material real:

- Guardar/probar la clave del gateway cuando el ecosistema local esté encendido.
- Guardar una clave de YouTube Data API y verificar búsquedas reales desde Profesor IA → Videos.
- Ejecutar por primera vez MLX Whisper y Demucs con un audio real; sus modelos se descargan bajo
  demanda. Probar después con Logic abierto solo si se activa conscientemente el permiso en
  Configuración; por defecto la app bloquea ese procesamiento para proteger el audio.
- Ajustar con uso real los umbrales de recursos y las estimaciones de RAM de modelos del gateway.
- Verificar a oído el metrónomo (que suene y que el acento caiga donde corresponde) y el reproductor
  de grabaciones con un archivo real; ambos compilan y su lógica está probada, pero el audio en sí no
  se puede comprobar sin escucharlo.
- Aceptar el permiso de notificaciones la primera vez que se active "Recordarme practicar" y
  confirmar que llega el aviso.

**Plan completado (2026-08-01, plan completo en `.claude/plans/serialized-humming-fox.md`)**,
distinto de las 4 de arriba — el usuario pidió academia de teoría + evolución de repertorio + setlist
de su banda tributo Kaos Etiliko, en 3 fases:
- **Fase 1 (Repertorio: bandas favoritas + progreso por sección) — DONE, 2026-08-01.**
- **Fase 2 (setlist de banda tributo) — DONE, 2026-08-01.** Tarjeta fija "Tu banda" en Repertorio +
  edición de bandas existentes (para poder marcar `isTributeProject` después de creada la banda).
- **Fase 3 (Academia de Teoría) — DONE, 2026-08-01.** Sección propia en navegación; opción
  múltiple/V-F/completar palabra; recortes de páginas PDF; conceptos de Biblioteca también
  disponibles para estudiar; pool de repetición espaciada combinado. Sin lógica de desbloqueo de
  módulos (acceso libre a los 20, confirmado con el usuario).

`_catalogo_ejercicios/results_teoria/` (conceptos de teoría por libro) — **integrado a Biblioteca el
2026-08-01** vía `compiled_teoria_guitarra.json` (963 conceptos, 17 libros, ya no quedan libros
pendientes de esa sesión paralela). Ver pestaña "Conceptos" en Biblioteca. Sigue **fuera** de la
Fase 3 (Academia) también lo reutiliza en la vista "Estudiar", después de que el usuario aclaró que
el contenido teórico debía estar en ambos lugares.

## Decisiones que no hace falta reabrir

- Solo Mac, sin sync entre dispositivos.
- Gemini 3.8 Flash pagado es el backend generativo principal desde 2026-09-03, con Gemini 3.7 Flash
  como alternativa estable inmediata ante timeout o saturación. El gateway Ollama conserva selección
  dinámica por RAM/CPU y se usa como respaldo automático; los motores de audio siguen siendo locales.
  Profesor IA Avanzado permanece en Hermes y no participa de ese enrutamiento.
- Las preguntas base de autoevaluación son contenido fijo provisto por el usuario, no generado por
  IA. El porcentaje/banda oficiales del Test Integral no se alteran; el dominio demostrado es una
  lectura separada que puede quedar por debajo o por encima porque exige evidencia convergente en
  situaciones reales — ver "Habilidades → Perfil de dominio" arriba.

## Notas de build

- Proyecto generado con `xcodegen` a partir de `project.yml` — nunca editar `.xcodeproj` a mano, y
  correr `xcodegen generate` después de agregar archivos o cambiar settings.
- Este repositorio tiene **git desde 2026-08-01** (se inicializó recién, antes no tenía) — hay un
  commit baseline previo a la migración al gateway por si hace falta recuperar algo (`OllamaService.swift`
  incluido). Seguir committeando cambios significativos para que la red de seguridad sirva.

Ver `CHANGELOG.md` para el detalle cronológico de cambios recientes.

## Entornos locales y respaldo

- Python 3.11 de Homebrew: `/opt/homebrew/bin/python3.11`.
- Motores aislados: `~/Library/Application Support/GuitarPracticeLab/AI/{whisper,basic-pitch,demucs,essentia}`.
- MLX Whisper, Basic Pitch + ONNX, Demucs y Essentia fueron ejecutados con un audio de prueba; la
  app firmada compiló y migró la base activa correctamente.
- Respaldo anterior a la suite de IA:
  `~/Library/Application Support/GuitarPracticeLab-backup-before-ai-suite-2026-08-01/`.
