import Foundation
import SwiftData

enum SeedService {
    static func seedIfNeeded(in context: ModelContext) {
        do {
            let instrumentCount = try context.fetchCount(FetchDescriptor<Instrument>())
            if instrumentCount == 0 { seedInventory(in: context) }

            let assetCount = try context.fetchCount(FetchDescriptor<StudioAsset>())
            if assetCount == 0 { seedStudio(in: context) }

            let skillCount = try context.fetchCount(FetchDescriptor<SkillTopic>())
            if skillCount == 0 { seedSkillTopics(in: context) }

            seedDailyChromaticWarmupIfNeeded(in: context)
            seedDailyFretboardTrainingIfNeeded(in: context)

            try context.save()
        } catch {
            assertionFailure("No fue posible crear los datos iniciales: \(error.localizedDescription)")
        }
    }

    private static func seedInventory(in context: ModelContext) {
        [
            Instrument(name: "Fender Stratocaster American Series", kind: "Guitarra eléctrica", pickups: "Single coils", tuning: "Estándar"),
            Instrument(name: "Gibson Les Paul Standard", kind: "Guitarra eléctrica", pickups: "Humbuckers", tuning: "Estándar"),
            Instrument(name: "Ibanez JEM", kind: "Guitarra eléctrica", pickups: "HSH", tuning: "Estándar"),
            Instrument(name: "Carvin Bolt T", kind: "Guitarra eléctrica", tuning: "Estándar"),
            Instrument(name: "Réplica Stratocaster", kind: "Guitarra eléctrica", pickups: "Single coils", tuning: "Estándar"),
            Instrument(name: "Electroacústica de cuerdas metálicas", kind: "Guitarra electroacústica"),
            Instrument(name: "Guitarra clásica de cuerdas de nylon", kind: "Guitarra clásica"),
            Instrument(name: "Bajo eléctrico", kind: "Bajo")
        ].forEach(context.insert)
    }

    private static func seedStudio(in context: ModelContext) {
        [
            StudioAsset(name: "Fractal FM9", assetType: .hardware, category: "Modelador", usage: "Presets, práctica silenciosa y grabación por USB"),
            StudioAsset(name: "Logic Pro", assetType: .software, category: "DAW", usage: "Plantillas de práctica y grabaciones de evaluación"),
            StudioAsset(name: "Superior Drummer", assetType: .software, category: "Batería virtual", usage: "Backings y trabajo rítmico"),
            StudioAsset(name: "EZbass", assetType: .software, category: "Bajo virtual", usage: "Acompañamientos"),
            StudioAsset(name: "EZkeys", assetType: .software, category: "Teclado virtual", usage: "Armonía y acompañamientos"),
            StudioAsset(name: "Eurocom Tornado F5", assetType: .hardware, category: "Computador auxiliar", usage: "Procesamiento por lotes y laboratorio Windows"),
            StudioAsset(name: "MacBook Pro Late 2012", assetType: .hardware, category: "Computador auxiliar", usage: "Visor de material y terminal de práctica")
        ].forEach(context.insert)
    }

    private static func seedSkillTopics(in context: ModelContext) {
        let topics: [SkillTopic] = [
        // MARK: Técnica — Test Integral (fundamentos, 85% del nivel general)
            SkillTopic(
                name: "Postura, relajación y mecánica general",
                detail: "Postura corporal, estabilidad de la guitarra, posición de muñecas, presión y eficiencia de movimientos.",
                domain: .technique, level: .basic,
                concept: "Esta habilidad comprende la postura corporal, la estabilidad de la guitarra, la posición de las muñecas, la presión utilizada y la eficiencia de los movimientos.",
                correctExecution: "La guitarra debe permanecer estable sin necesidad de sujetarla con fuerza. Los hombros deben estar relajados, las muñecas deben evitar posiciones extremas y los dedos deben moverse solamente lo necesario.",
                commonErrors: "Apretar excesivamente el mástil. Sujetar la púa con demasiada fuerza. Elevar los hombros. Doblar demasiado las muñecas. Levantar demasiado los dedos. Ignorar dolor o entumecimiento."
            ),
            SkillTopic(
                name: "Sincronización entre ambas manos",
                detail: "La púa y el dedo que pisa la nota actúan prácticamente al mismo tiempo.",
                domain: .technique, level: .basic,
                concept: "La sincronización significa que la púa y el dedo que pisa la nota actúan prácticamente al mismo tiempo.",
                correctExecution: "Cada nota debe comenzar de forma definida, sin silencios, notas dobles, arrastres ni ataques anticipados.",
                commonErrors: "La púa llega antes que el dedo. El dedo llega antes que la púa. Acelerar una mano más que la otra. Ocultar errores mediante distorsión. Practicar siempre demasiado rápido."
            ),
            SkillTopic(
                name: "Ritmo, subdivisión y groove",
                detail: "Pulso, subdivisiones, acentos, duración de las notas y silencios.",
                domain: .technique, level: .basic,
                concept: "El ritmo comprende el pulso, las subdivisiones, los acentos, la duración de las notas y los silencios.",
                correctExecution: "Debes poder mantener el tempo, contar las subdivisiones y colocar las notas de manera consistente respecto del metrónomo o la batería.",
                commonErrors: "Acelerar en partes fáciles. Frenar durante cambios. Confundir corcheas, tresillos y semicorcheas. No controlar silencios. Depender constantemente de una grabación."
            ),
            SkillTopic(
                name: "Acordes y guitarra rítmica",
                detail: "Acordes abiertos, cejillas, power chords, octavas, rasgueos, cortes y cambios de acorde.",
                domain: .technique, level: .basic,
                concept: "Incluye acordes abiertos, cejillas, power chords, octavas, rasgueos, cortes y cambios de acorde.",
                correctExecution: "Deben sonar únicamente las cuerdas necesarias, con ritmo, duración y dinámica controlados.",
                commonErrors: "Golpear todas las cuerdas. Detener la mano en los cambios. Dejar cuerdas abiertas accidentales. Presionar demasiado las cejillas. No controlar la duración de los acordes."
            ),
            SkillTopic(
                name: "Muting y palm muting",
                detail: "Evita que suenen cuerdas no deseadas; el palm muting reduce la resonancia apoyando la mano cerca del puente.",
                domain: .technique, level: .basic,
                concept: "El muting evita que suenen cuerdas no deseadas. El palm muting reduce la resonancia mediante el apoyo de la mano cerca del puente.",
                correctExecution: "Ambas manos deben controlar las cuerdas que no participan en la nota o acorde.",
                commonErrors: "Controlar solamente la cuerda tocada. Apoyar la palma demasiado lejos del puente. Apagar completamente la nota. Depender de una puerta de ruido. Permitir resonancia durante solos."
            ),
            SkillTopic(
                name: "Alternate picking",
                detail: "Alternar ataques descendentes y ascendentes.",
                domain: .technique, level: .basic,
                concept: "Consiste en alternar ataques descendentes y ascendentes.",
                correctExecution: "El movimiento debe ser pequeño, relajado y uniforme. Ambos ataques deben tener volumen semejante.",
                commonErrors: "Introducir demasiado la púa. Perder la alternancia. Hacer movimientos amplios. Acentuar todos los ataques descendentes. Practicar siempre comenzando hacia abajo."
            ),
            SkillTopic(
                name: "Downpicking, tremolo picking y gallops",
                detail: "Downpicking (ataques descendentes), tremolo (repetición rápida de una nota), gallops (subdivisiones cortas y largas).",
                domain: .technique, level: .basic,
                concept: "El downpicking utiliza ataques descendentes. El tremolo picking repite rápidamente una nota. Los gallops combinan subdivisiones cortas y largas.",
                correctExecution: "El movimiento debe ser económico y relajado. La velocidad no debe alterar el pulso ni la uniformidad.",
                commonErrors: "Utilizar todo el brazo. Endurecer el hombro. Tocar con demasiada fuerza. Acelerar involuntariamente. Confundir los gallops."
            ),
            SkillTopic(
                name: "Legato",
                detail: "Hammer-ons y pull-offs producidos principalmente por la mano izquierda.",
                domain: .technique, level: .basic,
                concept: "Incluye hammer-ons y pull-offs producidos principalmente por la mano izquierda.",
                correctExecution: "Las notas deben sonar claras, uniformes, afinadas y dentro de una subdivisión precisa.",
                commonErrors: "Hammer-ons débiles. Pull-offs demasiado fuertes. Dedos elevados. Desafinación lateral. Ritmo irregular."
            ),
            SkillTopic(
                name: "Slides y cambios de posición",
                detail: "Los slides conectan notas mediante un desplazamiento audible; los cambios de posición trasladan la mano por el mástil.",
                domain: .technique, level: .basic,
                concept: "Los slides conectan notas mediante un desplazamiento audible. Los cambios de posición trasladan la mano por el mástil.",
                correctExecution: "Debes anticipar el traste objetivo, llegar dentro del pulso y controlar la presión durante el recorrido.",
                commonErrors: "Llegar tarde. Corregir después de llegar. Presionar demasiado. Bloquear el pulgar. Generar ruido durante cambios silenciosos."
            ),
            SkillTopic(
                name: "Bending",
                detail: "Elevar la afinación al desplazar lateralmente la cuerda.",
                domain: .technique, level: .basic,
                concept: "El bending eleva la afinación al desplazar lateralmente la cuerda.",
                correctExecution: "La nota debe llegar exactamente a la afinación objetivo y mantenerse estable.",
                commonErrors: "Bend bajo. Bend alto. Utilizar solamente un dedo. Perder sustain. No silenciar cuerdas vecinas."
            ),
            SkillTopic(
                name: "Vibrato",
                detail: "Oscilación controlada de la afinación.",
                domain: .technique, level: .basic,
                concept: "El vibrato es una oscilación controlada de la afinación.",
                correctExecution: "Debe tener velocidad, amplitud y centro de afinación intencionales.",
                commonErrors: "Vibrato nervioso. Oscilación irregular. Pérdida del centro. Utilizar siempre la misma velocidad. Perder afinación sobre un bend."
            ),
            SkillTopic(
                name: "Aplicación musical, oído, teoría y repertorio",
                detail: "La técnica debe servir al ritmo, la melodía, la armonía y la expresión — no basta con dominar ejercicios aislados.",
                domain: .technique, level: .basic,
                concept: "El nivel general no depende únicamente de técnicas aisladas. También requiere tocar canciones completas, escuchar, improvisar, comprender armonía y tomar decisiones musicales.",
                correctExecution: "La técnica debe servir al ritmo, la melodía, la armonía y la expresión.",
                commonErrors: "Tocar únicamente ejercicios. Memorizar formas sin comprenderlas. Improvisar sin seguir los acordes. Depender siempre de tablaturas. No escuchar los propios errores."
            ),

            // MARK: Técnica — Test Integral (especialización, 15% del nivel general — mejores 3 de 6)
            SkillTopic(
                name: "String skipping",
                detail: "Saltar una o varias cuerdas sin golpear las intermedias.",
                domain: .technique, level: .advanced,
                concept: "Consiste en saltar una o varias cuerdas sin golpear las intermedias.",
                correctExecution: "La púa debe desplazarse directamente hacia la cuerda objetivo con control del ruido.",
                commonErrors: "Golpear cuerdas intermedias. Abrir demasiado el movimiento. Mirar permanentemente la mano. Perder la alternancia. Dejar resonancias."
            ),
            SkillTopic(
                name: "Economy picking",
                detail: "Combina púa alternada con pequeños barridos al cambiar de cuerda.",
                domain: .technique, level: .advanced,
                concept: "Combina púa alternada con pequeños barridos al cambiar de cuerda.",
                correctExecution: "El movimiento debe continuar en la dirección de la cuerda siguiente sin perder separación, ritmo ni claridad.",
                commonErrors: "Mezclar direcciones accidentalmente. Arrastrar la púa. Convertir notas separadas en un acorde. Perder los acentos. No planificar la digitación."
            ),
            SkillTopic(
                name: "Sweep picking",
                detail: "Movimiento continuo de la púa a través de varias cuerdas para ejecutar arpegios.",
                domain: .technique, level: .advanced,
                concept: "Utiliza un movimiento continuo de la púa a través de varias cuerdas para ejecutar arpegios.",
                correctExecution: "Cada nota debe sonar por separado. La mano izquierda pisa y libera cada nota en sincronización con el barrido.",
                commonErrors: "Rasguear un acorde. Mantener todas las notas pisadas. Descoordinar las manos. Depender de demasiada distorsión. Acelerar en una dirección."
            ),
            SkillTopic(
                name: "Tapping",
                detail: "Dedos de la mano derecha sobre el diapasón para producir notas.",
                domain: .technique, level: .advanced,
                concept: "El tapping utiliza dedos de la mano derecha sobre el diapasón para producir notas.",
                correctExecution: "La nota golpeada debe equilibrarse con las demás. La retirada del dedo debe producir la siguiente nota sin sacar la cuerda de afinación.",
                commonErrors: "Golpear demasiado fuerte. Desafinar lateralmente. Producir ruido grave. Ejecutar patrones irregulares. Depender de compresión extrema."
            ),
            SkillTopic(
                name: "Armónicos",
                detail: "Armónicos naturales, artificiales, pinch harmonics y tapped harmonics.",
                domain: .technique, level: .advanced,
                concept: "Incluye armónicos naturales, artificiales, pinch harmonics y tapped harmonics.",
                correctExecution: "Requieren precisión de contacto, ataque y posición de la mano derecha.",
                commonErrors: "Presionar demasiado. Retirar el dedo tarde. Exponer incorrectamente el pulgar. Depender de ganancia extrema. No controlar cuerdas vecinas."
            ),
            SkillTopic(
                name: "Hybrid picking, fingerstyle y palanca",
                detail: "Combina púa y dedos; usa los dedos para varias voces; la palanca modifica la afinación con fines expresivos.",
                domain: .technique, level: .advanced,
                concept: "El hybrid picking combina púa y dedos. El fingerstyle utiliza los dedos para producir varias voces. La palanca modifica la afinación y permite efectos expresivos.",
                correctExecution: "Los ataques deben equilibrarse en volumen. La palanca debe utilizarse con afinación, ritmo y retorno controlados.",
                commonErrors: "Dedos mucho más débiles que la púa. Falta de independencia. Perder la púa. Movimiento excesivo de la palanca. No regresar a la afinación."
            ),

            // MARK: Teoría — Test Integral de Teoría (bloque A: fundamentos, módulos 1-8)
            SkillTopic(
                name: "Notas musicales y organización del diapasón",
                detail: "Los siete nombres de nota (A-G / La-Sol), semitonos entre B-C y E-F, y la afinación estándar E-A-D-G-B-E.",
                domain: .theory, level: .basic,
                concept: "La música occidental utiliza siete nombres básicos de notas (A, B, C, D, E, F, G / La, Si, Do, Re, Mi, Fa, Sol). Entre la mayoría de las notas naturales existe un tono; entre B-C y E-F existe solamente un semitono. Cada traste de la guitarra representa un semitono.",
                correctExecution: "Debes poder nombrar las cuerdas al aire, calcular cualquier nota avanzando por semitonos, localizar una nota en diferentes cuerdas, utilizar patrones de octavas y reconocer notas enarmónicas. Afinación estándar: E–A–D–G–B–E.",
                commonErrors: "Contar el traste cero como si fuera el primer traste. Olvidar que B-C y E-F no tienen nota natural intermedia. Conocer únicamente las notas de la sexta cuerda. Depender siempre de patrones visuales. Creer que un sostenido y un bemol siempre cumplen funciones idénticas."
            ),
            SkillTopic(
                name: "Alteraciones y notas enarmónicas",
                detail: "Sostenidos y bemoles, y notas que suenan igual pero se escriben distinto según la tonalidad.",
                domain: .theory, level: .basic,
                concept: "Un sostenido eleva una nota un semitono; un bemol la disminuye un semitono. Dos notas pueden sonar igual y escribirse distinto — esto se llama enarmonía (ej. C♯ y D♭).",
                correctExecution: "Debes elegir el nombre de la nota según la escala, acorde o tonalidad. En D mayor se usa C♯, no D♭, porque cada grado debe conservar una letra diferente.",
                commonErrors: "Escribir dos notas con la misma letra dentro de una escala. Elegir sostenidos o bemoles al azar. Pensar que la escritura no afecta la comprensión armónica. Confundir una alteración accidental con la armadura de tonalidad. Llamar sostenido a cualquier posición intermedia."
            ),
            SkillTopic(
                name: "Intervalos",
                detail: "La distancia entre dos notas (segundas, terceras, cuartas... hasta la octava), base de escalas y acordes.",
                domain: .theory, level: .basic,
                concept: "Un intervalo es la distancia entre dos notas, nombrado por número y calidad (segunda menor/mayor, tercera menor/mayor, cuarta justa, quinta justa, sexta menor/mayor, séptima menor/mayor, octava). Determinan la estructura de escalas, acordes, riffs y melodías.",
                correctExecution: "Debes poder contar intervalos desde cualquier nota, reconocer su cantidad de semitonos, encontrarlos en distintas cuerdas, escucharlos dentro de acordes y melodías, y usarlos para transportar ideas.",
                commonErrors: "Contar solamente la distancia física entre trastes. No incluir la nota inicial al nombrar el intervalo. Confundir tercera menor con segunda aumentada. Memorizar formas sin conocer las notas. Suponer que una forma funciona igual al cruzar de la tercera a la segunda cuerda."
            ),
            SkillTopic(
                name: "Ritmo, figuras y compás",
                detail: "Duración de notas y silencios, redonda/blanca/negra/corchea/semicorchea, y qué indican los números del compás.",
                domain: .theory, level: .basic,
                concept: "La teoría rítmica organiza la duración de notas y silencios. En 4/4: la redonda dura 4 pulsos, la blanca 2, la negra 1, la corchea medio pulso, la semicorchea un cuarto de pulso. El número superior del compás indica cuántos pulsos contiene; el inferior indica qué figura representa la unidad de pulso.",
                correctExecution: "Debes poder contar las subdivisiones, interpretar silencios, leer ritmos antes de tocarlos, reconocer síncopas, distinguir compases simples y compuestos, y mantener la duración exacta de las notas.",
                commonErrors: "Pensar que una nota larga debe tocarse más fuerte. Ignorar los silencios. Confundir tempo con subdivisión. Leer el 6/8 como seis pulsos fuertes iguales. Cortar las notas antes de completar su valor."
            ),
            SkillTopic(
                name: "Escala mayor y tonalidades",
                detail: "Patrón Tono-Tono-Semitono-Tono-Tono-Tono-Semitono (grados 1-7), base de intervalos, acordes, modos y funciones.",
                domain: .theory, level: .basic,
                concept: "La escala mayor sigue la secuencia tono-tono-semitono-tono-tono-tono-semitono (grados 1-2-3-4-5-6-7). Sirve como referencia para construir intervalos, acordes, modos y funciones armónicas.",
                correctExecution: "No basta con memorizar una figura. Debes conocer las notas, identificar los grados, localizar la tónica, tocarla en diferentes zonas, construirla desde cualquier nota y relacionarla con los acordes de la tonalidad.",
                commonErrors: "Confundir patrón físico con escala. No saber dónde está la tónica. Aprender una única posición. Pensar que tocar las notas correctas garantiza una frase musical. Confundir tonalidad mayor con acorde mayor."
            ),
            SkillTopic(
                name: "Escalas menores",
                detail: "Menor natural, menor armónica (séptimo grado elevado) y menor melódica.",
                domain: .theory, level: .basic,
                concept: "Las tres formas menores principales son natural (1-2-♭3-4-5-♭6-♭7), armónica (eleva el séptimo grado: 1-2-♭3-4-5-♭6-7) y melódica (eleva sexto y séptimo al ascender en el uso clásico).",
                correctExecution: "Debes identificar la tónica, el tercer grado menor, la sensible de la menor armónica, los acordes derivados y el contexto estilístico de cada escala.",
                commonErrors: "Confundir relativo menor con menor paralelo. Usar menor armónica sobre todos los acordes de una tonalidad menor. No reconocer el efecto del séptimo grado elevado. Memorizar formas sin conocer la armonía. Suponer que toda música usa la menor melódica igual."
            ),
            SkillTopic(
                name: "Escalas pentatónicas y blues",
                detail: "Pentatónica menor (1-♭3-4-5-♭7), pentatónica mayor (1-2-3-5-6) y blues (pentatónica menor + ♭5).",
                domain: .theory, level: .basic,
                concept: "La pentatónica menor usa 1-♭3-4-5-♭7. La pentatónica mayor usa 1-2-3-5-6. La escala de blues menor añade la quinta disminuida: 1-♭3-4-♭5-5-♭7.",
                correctExecution: "La pentatónica debe usarse como material melódico, no como una figura recorrida de arriba abajo. Debes conocer las tónicas, las notas del acorde, las notas de tensión, las conexiones entre posiciones y la relación entre pentatónica mayor y menor.",
                commonErrors: "Pensar que una sola pentatónica funciona igual sobre cualquier progresión. Tocar siempre desde la nota más grave de la figura. No resolver las tensiones. Desconocer las notas que contiene la posición. Confundir la \"blue note\" con una nota que debe sostenerse siempre."
            ),
            SkillTopic(
                name: "Construcción de tríadas",
                detail: "Fundamental, tercera y quinta — mayor (1-3-5), menor (1-♭3-5), disminuida (1-♭3-♭5), aumentada (1-3-♯5).",
                domain: .theory, level: .basic,
                concept: "Una tríada contiene tres notas: fundamental, tercera y quinta. Fórmulas: mayor 1-3-5, menor 1-♭3-5, disminuida 1-♭3-♭5, aumentada 1-3-♯5.",
                correctExecution: "Debes poder construir cualquier tríada desde una fundamental, localizarla en grupos de tres cuerdas y reconocer sus inversiones. Son esenciales para acompañamientos, armonizaciones, solos basados en acordes, voice leading y creación de riffs.",
                commonErrors: "Identificar un acorde solo por su forma. Confundir fundamental con nota más grave. No conocer las inversiones. Añadir cuerdas que no pertenecen al acorde. Pensar que una tríada siempre necesita repetición de la fundamental."
            ),

            // MARK: Teoría — Test Integral de Teoría (bloque B: armonía y acordes, módulos 9-14)
            SkillTopic(
                name: "Acordes de séptima y extensiones",
                detail: "Mayor7 (1-3-5-7), dominante7 (1-3-5-♭7), menor7 (1-♭3-5-♭7), m7♭5, y extensiones (9ª, 11ª, 13ª).",
                domain: .theory, level: .intermediate,
                concept: "Los acordes de séptima añaden una cuarta nota a la tríada: mayor séptima 1-3-5-7, dominante séptima 1-3-5-♭7, menor séptima 1-♭3-5-♭7, menor séptima con quinta disminuida 1-♭3-♭5-♭7. Las extensiones incluyen novena, oncena y trecena.",
                correctExecution: "Debes reconocer las notas esenciales de cada acorde, especialmente la tercera y la séptima. No todas las extensiones deben tocarse simultáneamente en la guitarra; es habitual omitir notas menos importantes para evitar acumulaciones graves.",
                commonErrors: "Confundir C7 con Cmaj7. Suponer que \"séptima\" siempre significa séptima mayor. Duplicar notas innecesariamente. Incluir todas las extensiones en registros graves. Confundir add9 con un acorde de novena dominante."
            ),
            SkillTopic(
                name: "Inversiones, voicings y sistema CAGED",
                detail: "Cambiar la nota más grave de un acorde, disposiciones concretas de sus notas, y las 5 formas C-A-G-E-D.",
                domain: .theory, level: .intermediate,
                concept: "Una inversión cambia la nota más grave del acorde (posición fundamental, primera inversión con la tercera en el bajo, segunda inversión con la quinta en el bajo). Un voicing es una disposición concreta de las notas de un acorde. El sistema CAGED organiza el diapasón con cinco formas derivadas de los acordes abiertos C, A, G, E y D.",
                correctExecution: "El objetivo no es memorizar cinco dibujos aislados, sino comprender dónde están las fundamentales, qué intervalos contiene cada forma, cómo se conectan, qué tríadas aparecen dentro de cada posición y qué voicing resulta apropiado para cada registro.",
                commonErrors: "Creer que CAGED son cinco escalas. Transportar formas sin identificar la tónica. Tocar acordes completos cuando basta una tríada. Confundir inversión con una nueva clase de acorde. No considerar el registro de los otros instrumentos."
            ),
            SkillTopic(
                name: "Armonización de la escala mayor",
                detail: "Tríadas construidas sobre cada grado: I mayor, ii menor, iii menor, IV mayor, V mayor, vi menor, vii disminuido.",
                domain: .theory, level: .intermediate,
                concept: "Al construir tríadas sobre cada grado de una escala mayor se obtiene I mayor – ii menor – iii menor – IV mayor – V mayor – vi menor – vii disminuido (en C mayor: C, Dm, Em, F, G, Am, Bdim).",
                correctExecution: "Debes poder armonizar cualquier escala mayor y traducir los números romanos a acordes concretos. Los números romanos permiten transportar progresiones sin perder sus relaciones internas.",
                commonErrors: "Memorizar acordes de C mayor como si fueran universales. Confundir grado de escala con intervalo. No distinguir números mayores y menores. Construir acordes usando notas externas a la tonalidad. Creer que todos los acordes de una canción deben ser diatónicos."
            ),
            SkillTopic(
                name: "Funciones armónicas",
                detail: "Tónica (estabilidad), subdominante/predominante (movimiento) y dominante (tensión que resuelve hacia la tónica).",
                domain: .theory, level: .intermediate,
                concept: "En la armonía tonal, los acordes cumplen funciones generales: tónica (estabilidad), predominante o subdominante (movimiento), dominante (tensión y tendencia hacia la tónica). En una tonalidad mayor: I suele ser tónica, ii y IV predominante, V y vii° dominante.",
                correctExecution: "Debes escuchar la dirección armónica, no solamente identificar nombres de acordes. Comprender la función permite anticipar resoluciones, crear progresiones, improvisar con dirección, sustituir acordes de función similar y reconocer tensiones.",
                commonErrors: "Pensar que cada acorde tiene una única función posible. Confundir función con calidad mayor o menor. Analizar acordes sin considerar el contexto. Creer que la dominante siempre debe resolver. Ignorar el bajo y la melodía."
            ),
            SkillTopic(
                name: "Progresiones y cadencias",
                detail: "Secuencias de acordes y sus cierres: auténtica (V-I), plagal (IV-I), semicadencia, engañosa (V-vi).",
                domain: .theory, level: .intermediate,
                concept: "Una progresión es una secuencia organizada de acordes. Una cadencia produce cierre, pausa o desviación: auténtica (V-I), plagal (IV-I), semicadencia (termina en V), engañosa (V-vi u otra resolución inesperada).",
                correctExecution: "Debes poder analizar una progresión mediante números romanos y transportarla a otras tonalidades, además de escuchar qué acordes generan estabilidad, preparación o tensión.",
                commonErrors: "Analizar cada acorde de forma aislada. Confundir progresión con tonalidad. Transportar acordes por nombre en lugar de por función. Pensar que toda progresión debe terminar en I. No distinguir una repetición cíclica de una cadencia."
            ),
            SkillTopic(
                name: "Arpegios y notas del acorde",
                detail: "Las notas de un acorde ejecutadas sucesivamente — puntos de estabilidad para la improvisación.",
                domain: .theory, level: .intermediate,
                concept: "Un arpegio contiene las notas de un acorde ejecutadas sucesivamente (ej. Cmaj7: C-E-G-B). Las notas del acorde proporcionan puntos de estabilidad durante la improvisación.",
                correctExecution: "Debes relacionar cada arpegio con el acorde que está sonando y dirigir las frases hacia fundamental, tercera, quinta, séptima o extensiones apropiadas. La tercera y la séptima suelen expresar claramente la calidad y función del acorde.",
                commonErrors: "Recorrer arpegios sin relación con el ritmo. Comenzar siempre desde la fundamental. Ignorar el acorde que está sonando. Confundir forma de arpegio con técnica de sweep. Tocar todas las notas del arpegio con el mismo énfasis."
            ),

            // MARK: Teoría — Test Integral de Teoría (bloque C: aplicación avanzada, módulos 15-19 + bloque D: oído/sonido, módulo 20)
            SkillTopic(
                name: "Modos de la escala mayor",
                detail: "Jónico, dórico, frigio, lidio, mixolidio, eólico y locrio — cada uno con una nota característica y un centro tonal propio.",
                domain: .theory, level: .advanced,
                concept: "Los siete modos derivados de la escala mayor son jónico, dórico, frigio, lidio, mixolidio, eólico y locrio. Un modo no se define únicamente por comenzar una escala mayor desde otra nota — debe existir un centro tonal que haga escuchar esa nota como tónica.",
                correctExecution: "Debes comprender la fórmula de cada modo, su nota característica, el acorde o contexto que lo sostiene, y la diferencia entre posición física y centro tonal (ej. dórico 1-2-♭3-4-5-6-♭7, lidio = mayor con ♯4, mixolidio = mayor con ♭7, frigio = menor con ♭2).",
                commonErrors: "Tocar C mayor desde D y asumir que automáticamente suena dórico. Memorizar siete figuras sin escuchar sus diferencias. Ignorar el acorde pedal o centro tonal. Usar todos los modos sobre la misma armonía. Confundir modo con posición de escala."
            ),
            SkillTopic(
                name: "Voice leading y conducción de voces",
                detail: "Cómo se desplaza cada nota de un acorde hacia el siguiente — notas comunes, movimientos pequeños, resoluciones claras.",
                domain: .theory, level: .advanced,
                concept: "El voice leading estudia cómo se desplaza cada nota de un acorde hacia el siguiente. Una buena conducción de voces suele conservar notas comunes, usar movimientos pequeños, evitar saltos innecesarios y dirigir las tensiones hacia resoluciones claras.",
                correctExecution: "En guitarra, las inversiones y tríadas pequeñas permiten conectar acordes sin mover toda la mano por el mástil (ej. C mayor C-E-G y A menor A-C-E comparten C y E).",
                commonErrors: "Mover siempre acordes completos en posición fundamental. Ignorar notas comunes. Elegir voicings por comodidad sin escuchar las voces. Duplicar notas que interfieren con la melodía. Pensar que el bajo debe tocar siempre la fundamental."
            ),
            SkillTopic(
                name: "Transporte y afinaciones",
                detail: "Mover una pieza a otra tonalidad conservando sus relaciones interválicas; afinaciones alternativas como Drop D.",
                domain: .theory, level: .advanced,
                concept: "Transportar significa mover una pieza, progresión, acorde o melodía a otra tonalidad conservando sus relaciones interválicas. Las afinaciones alternativas modifican la ubicación física de las notas y las formas (ej. Drop D: D-A-D-G-B-E).",
                correctExecution: "Para transportar correctamente debes usar intervalos o números romanos. Al cambiar de afinación debes recalcular notas, intervalos, formas de acordes, patrones de octavas y digitaciones.",
                commonErrors: "Mover acordes sin conservar la calidad. Confundir transporte con modulación. Usar formas estándar en una afinación distinta sin comprobar las notas. Pensar que Drop D baja todas las cuerdas. No ajustar tensión, entonación o calibre en cambios considerables."
            ),
            SkillTopic(
                name: "Improvisación y relación acorde-escala",
                detail: "Improvisar no es solo elegir una escala compatible — requiere relacionar notas del acorde, tensiones, ritmo y estructura.",
                domain: .theory, level: .advanced,
                concept: "Improvisar no consiste únicamente en elegir una escala compatible. Una improvisación sólida relaciona notas del acorde, tensiones, resoluciones, ritmo, motivos, dinámica y estructura formal.",
                correctExecution: "Sobre cada acorde debes conocer su fundamental, tercera, quinta, séptima (cuando corresponda) y las tensiones disponibles. Las notas del acorde suelen funcionar bien como puntos de llegada; las tensiones pueden generar movimiento si se resuelven con intención.",
                commonErrors: "Utilizar una sola figura sin escuchar los cambios. Comenzar y terminar todas las frases igual. Pensar que una escala compatible elimina las notas problemáticas. Ignorar el ritmo. Tocar continuamente sin dejar espacios."
            ),
            SkillTopic(
                name: "Recursos armónicos no diatónicos",
                detail: "Dominantes secundarios, intercambio modal, acordes prestados, cromatismo y modulación.",
                domain: .theory, level: .advanced,
                concept: "No todos los acordes de una canción pertenecen a una única escala. Recursos frecuentes: dominantes secundarios, intercambio modal, acordes prestados, cromatismo, modulación, acordes de paso. Un dominante secundario funciona temporalmente como dominante de un acorde distinto de la tónica (ej. en C mayor, D7-G-C: D7 es V/V).",
                correctExecution: "Debes identificar primero la tonalidad principal y después determinar qué acorde externo aparece y hacia dónde se dirige.",
                commonErrors: "Considerar cualquier acorde externo como cambio completo de tonalidad. Confundir dominante secundario con modulación. Improvisar únicamente con la escala principal sobre todos los acordes. No reconocer las alteraciones del acorde temporal. Etiquetar recursos avanzados sin escuchar su resolución."
            ),
            SkillTopic(
                name: "Oído, transcripción, lectura y sonido eléctrico",
                detail: "Conectar la teoría con el oído y el sonido real: transcripción, tablatura, pastillas, ganancia, ecualización y efectos.",
                domain: .theory, level: .advanced,
                concept: "La teoría debe conectarse con el oído y con el sonido real del instrumento. La transcripción desarrolla la capacidad de reconocer notas, intervalos, acordes, ritmos, articulaciones y estructura. La tablatura indica posiciones, pero no siempre representa el ritmo, la digitación o la intención musical.",
                correctExecution: "Debes escuchar antes de buscar posiciones. La pastilla del puente suele ser más brillante, la del mástil más cálida; la distorsión añade armónicos y compresión; el ecualizador modifica bandas de frecuencia; no hay un único orden obligatorio de pedales, aunque hay configuraciones habituales.",
                commonErrors: "Copiar tablaturas sin escuchar. Confundir traste correcto con frase correcta. Ignorar ritmo y articulación. Usar demasiada ganancia para compensar falta de sustain. Recortar todos los medios y desaparecer dentro de una banda. Tratar la puerta de ruido como sustituto del muting."
            )
        ]

        for topic in topics {
            // No reordenar/insertar preguntas dentro de un tema existente en SkillAssessmentQuestionBank:
            // TheoryFlashcardProgress identifica cada tarjeta por (topic.id, índice), así que cambiar el
            // orden corrompería en silencio el progreso guardado de flashcards de teoría ya existente.
            topic.assessmentQuestions = SkillAssessmentQuestionBank.questions(for: topic.name)
        }
        topics.forEach(context.insert)
    }

    /// El usuario hace este calentamiento cromático todos los días, rotando de combinación de dedos
    /// cada día, así que se agrega una sola vez como
    /// `LibraryExercise` en aprendizaje: `RecurringPracticeService` ya recrea la tarea del día
    /// siguiente automáticamente mientras el estado no pase a Dominado ni Revisión periódica,
    /// recalculando la variación que toca según la fecha. Se revisa en cada arranque solo para
    /// reponer la tarea de hoy si por algún motivo no quedó ninguna pendiente.
    private static func seedDailyChromaticWarmupIfNeeded(in context: ModelContext) {
        let exercise = resolveChromaticWarmupExercise(in: context)

        let pendingTasks = ((try? context.fetch(FetchDescriptor<PracticeTask>(
            predicate: #Predicate { !$0.isCompleted }
        ))) ?? []).filter {
            $0.sourceID == exercise.id && $0.sourceKindRaw == TaskSourceKind.library.rawValue
        }

        if let taskToKeep = pendingTasks.max(by: { $0.scheduledDate < $1.scheduledDate }) {
            // Quedaron varias pendientes por el bug de duplicado (ver `resolveChromaticWarmupExercise`):
            // nos quedamos con la agendada más adelante y borramos el resto para no mostrarla repetida.
            for extra in pendingTasks where extra.id != taskToKeep.id {
                context.delete(extra)
            }

            // Migra de inmediato las tareas creadas por versiones anteriores con el título genérico
            // "... y variaciones" y actualiza una tarea vencida con el patrón del día actual. Si la
            // tarea está agendada a futuro, conserva la combinación que corresponde a esa fecha.
            let hadAutomaticRhythm = taskToKeep.instructions.hasPrefix("Figura rítmica:")
                || RhythmicFigure.allCases.dropFirst().contains {
                    taskToKeep.title.localizedCaseInsensitiveContains("· \($0.displayName) ·")
                }
            let variationDate = max(taskToKeep.scheduledDate, Date.now)
            let variation = ChromaticWarmupRotation.variation(for: variationDate)
            taskToKeep.title = variation.title
            taskToKeep.exerciseTitle = variation.title
            taskToKeep.instructions = variation.instructions
            taskToKeep.plannedMinutes = DailyPracticeRoutine.chromaticMinutes
            if hadAutomaticRhythm { taskToKeep.rhythmicFigure = .unspecified }
            return
        }

        let variation = ChromaticWarmupRotation.variation(for: .now)
        context.insert(PracticeTask(
            title: variation.title,
            category: .technique,
            plannedMinutes: DailyPracticeRoutine.chromaticMinutes,
            sourceTitle: exercise.bookTitle,
            exerciseTitle: variation.title,
            priority: 0,
            instructions: variation.instructions,
            sourceKind: .library,
            sourceID: exercise.id
        ))
    }

    /// Localiza (o crea) el `LibraryExercise` del calentamiento diario, identificado por
    /// `collectionName`+`bookTitle` en vez de por `technique` — ese texto cambió de una versión de
    /// este seed a otra y dejó dos ejercicios (y dos cadenas de tareas recurrentes) corriendo en
    /// paralelo, que es la causa del duplicado. De paso fusiona esos duplicados si los encuentra:
    /// reasigna sus tareas al que se conserva y borra el resto.
    private static func resolveChromaticWarmupExercise(in context: ModelContext) -> LibraryExercise {
        let rotationNotes = "Rotación diaria de las 24 combinaciones de dedos cromáticas, agrupadas en 12 pares de ida y vuelta (1234/4321, 1324/4231, etc.). La figura rítmica se elige manualmente para cada práctica."
        let matches = (try? context.fetch(FetchDescriptor<LibraryExercise>(
            predicate: #Predicate { $0.collectionName == "Calentamiento diario" && $0.bookTitle == "Rutina propia" }
        ))) ?? []

        guard let primary = matches.first else {
            let created = LibraryExercise(
                collectionName: "Calentamiento diario",
                bookTitle: "Rutina propia",
                technique: ChromaticWarmupRotation.techniqueMarker,
                status: .learning,
                notes: rotationNotes
            )
            context.insert(created)
            return created
        }

        primary.technique = ChromaticWarmupRotation.techniqueMarker
        primary.notes = rotationNotes
        for duplicate in matches.dropFirst() {
            let duplicateID: UUID? = duplicate.id
            let duplicateTasks = (try? context.fetch(FetchDescriptor<PracticeTask>(
                predicate: #Predicate { $0.sourceID == duplicateID }
            ))) ?? []
            duplicateTasks.forEach { $0.sourceID = primary.id }
            context.delete(duplicate)
        }
        return primary
    }

    /// La práctica del mástil es una rutina propia del producto, no un ejercicio importado. Una
    /// sola tarea pendiente garantiza 7 minutos diarios; al completarla, la recurrencia crea la
    /// de mañana y conserva el BPM que recomiende el entrenador adaptativo.
    private static func seedDailyFretboardTrainingIfNeeded(in context: ModelContext) {
        let pending = ((try? context.fetch(FetchDescriptor<PracticeTask>(
            predicate: #Predicate { !$0.isCompleted }
        ))) ?? []).filter { $0.sourceKindRaw == TaskSourceKind.fretboard.rawValue }

        if let taskToKeep = pending.max(by: { $0.scheduledDate < $1.scheduledDate }) {
            for duplicate in pending where duplicate.id != taskToKeep.id { context.delete(duplicate) }
            taskToKeep.title = "Notas del mástil · sesión adaptativa"
            taskToKeep.exerciseTitle = "Entrenamiento del mástil"
            taskToKeep.category = .theory
            taskToKeep.plannedMinutes = DailyPracticeRoutine.fretboardMinutes
            taskToKeep.priority = 0
            taskToKeep.instructions = "Con la guitarra en mano, responde tocando una sola nota. El micrófono comprobará altura y octava; los fallos volverán reformulados y el tempo subirá cuando la respuesta sea estable."
            return
        }

        let profile = (try? context.fetch(FetchDescriptor<FretboardTrainingProfile>()))?.first
        context.insert(PracticeTask(
            title: "Notas del mástil · sesión adaptativa",
            category: .theory,
            plannedMinutes: DailyPracticeRoutine.fretboardMinutes,
            sourceTitle: "Rutina diaria",
            exerciseTitle: "Entrenamiento del mástil",
            targetBPM: profile?.recommendedBPM ?? 40,
            priority: 0,
            instructions: "Con la guitarra en mano, responde tocando una sola nota. El micrófono comprobará altura y octava; los fallos volverán reformulados y el tempo subirá cuando la respuesta sea estable.",
            sourceKind: .fretboard
        ))
    }
}
