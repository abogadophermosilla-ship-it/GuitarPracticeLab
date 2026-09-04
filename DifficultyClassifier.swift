import Foundation

/// Resultado de clasificar un material: la nota en estrellas y los motivos que la produjeron, para
/// que la clasificación se pueda auditar en la ficha del ejercicio en vez de aparecer como un número
/// caído del cielo.
struct DifficultyAssessment {
    let rating: DifficultyRating
    let factors: [String]
    /// Lectura breve en lenguaje de profesor: qué se trabaja y dónde está la dificultad real.
    let summary: String
    /// Exigencias observables en la descripción/notas, no nombres genéricos de nivel.
    let demands: [String]
    /// Base que conviene tener antes de abordar el material.
    let prerequisites: [String]
    /// Primera consigna concreta para estudiarlo con criterio.
    let practiceFocus: String

    init(
        rating: DifficultyRating,
        factors: [String],
        summary: String = "",
        demands: [String] = [],
        prerequisites: [String] = [],
        practiceFocus: String = ""
    ) {
        self.rating = rating
        self.factors = factors
        self.summary = summary
        self.demands = demands
        self.prerequisites = prerequisites
        self.practiceFocus = practiceFocus
    }

    var explanation: String { factors.joined(separator: " · ") }

    /// Permite encontrar un ejercicio por lo que realmente exige (por ejemplo, "afinación del
    /// bend"), aunque esa frase no estuviera escrita literalmente en el catálogo original.
    var searchableText: String {
        ([summary, practiceFocus] + demands + prerequisites + factors).joined(separator: " ")
    }
}

/// Clasifica el material de la Biblioteca con criterio de profesor y sin IA: determinístico,
/// instantáneo y reproducible.
///
/// El razonamiento tiene tres capas, en este orden:
///
/// 1. **El libro**. Cada uno de los 19 libros del catálogo tiene un rango real conocido — "Total
///    Rock Guitar" nunca llega adonde llega "Speed Mechanics", por más que su último capítulo sea el
///    más difícil del libro. El rango acota todo lo demás.
/// 2. **La posición dentro del libro**. Todos estos métodos están escritos en progresión, así que la
///    página (y el número propio del ejercicio, cuando la numeración avanza junto con la página)
///    ubica el ejercicio dentro del rango del libro.
/// 3. **La técnica concreta**. Sobre esa base se suman y restan los recursos que el ejercicio pide:
///    un barrido de cinco cuerdas cuesta más que una pentatónica en una posición, esté donde esté.
///
/// La etiqueta cruda del catálogo original (principiante/intermedio/avanzado) participa solo como
/// un empujón menor: es la que resultó demasiado gruesa y por eso existe esta escala.
enum DifficultyClassifier {

    // MARK: - Contexto por libro

    /// Dónde empieza y termina cada libro en el catálogo real, medido sobre los propios ejercicios
    /// importados en vez de estar escrito a mano — así sigue siendo correcto si mañana se agregan
    /// más páginas de un libro ya presente.
    struct BookContext: Sendable {
        var firstPage: Int
        var lastPage: Int
        /// Número propio más alto encontrado ("Ejercicio 196", "Lick #365").
        var highestNumber: Int
        /// `true` cuando esa numeración avanza junto con la página en casi todo el libro. Cuando el
        /// libro reinicia la cuenta en cada capítulo (el caso de "Blues a tu alcance"), el número no
        /// dice nada de la progresión y se ignora.
        var numberingIsProgressive: Bool

        var pageSpan: Int { max(0, lastPage - firstPage) }
    }

    /// Rango de dificultad de cada libro del catálogo, con el motivo por el que se le asignó.
    /// `match` son fragmentos ya normalizados (sin tildes ni mayúsculas) que aparecen en el título
    /// tal como lo escribe el catálogo, que no siempre coincide con el del PDF.
    struct BookProfile {
        let name: String
        let match: [String]
        let floor: Double
        let ceiling: Double
        let rationale: String
    }

    static let bookProfiles: [BookProfile] = [
        BookProfile(
            name: "Teoría Básica Para Guitarristas Principiantes",
            match: ["teoria basica para guitarristas"],
            floor: 1.0, ceiling: 3.0,
            rationale: "método de entrada: notas al aire, power chords y canciones con acordes abiertos"
        ),
        BookProfile(
            name: "Total Rock Guitar",
            match: ["total rock guitar"],
            floor: 1.5, ceiling: 4.5,
            rationale: "curso completo de rock desde cero, termina en tremolo y tres notas por cuerda"
        ),
        BookProfile(
            name: "Blues a tu alcance",
            match: ["blues a tu alcance"],
            floor: 2.0, ceiling: 5.0,
            rationale: "pentatónica menor por posiciones sobre blues de 12 compases"
        ),
        BookProfile(
            name: "Guitar Aerobics",
            match: ["guitar aerobics"],
            floor: 2.0, ceiling: 7.5,
            rationale: "365 días en progresión estricta: arranca en calentamientos y cierra en material de shred"
        ),
        BookProfile(
            name: "Fretboard Freedom",
            match: ["fretboard freedom"],
            floor: 3.0, ceiling: 7.0,
            rationale: "365 licks para conectar el diapasón; exige lectura de posición más que velocidad pura"
        ),
        BookProfile(
            name: "Improvisación para Muñones",
            match: ["improvisacion para munones", "improvisacion para muñones"],
            floor: 2.5, ceiling: 6.5,
            rationale: "de la fundamental de cada acorde a dominantes secundarios y sustitución tritonal"
        ),
        BookProfile(
            name: "Tríadas para Muñones",
            match: ["triadas para munones", "triadas para muñones"],
            floor: 2.5, ceiling: 5.5,
            rationale: "tríadas y arpegios por todo el mástil: mucha visualización, exigencia física moderada"
        ),
        BookProfile(
            name: "Metal Rhythm Guitar Volume I",
            match: ["metal rhythm guitar volume i"],
            floor: 2.0, ceiling: 5.5,
            rationale: "Stetina I: power chords, palm mute y síncopa, la base de la mano derecha del metal"
        ),
        BookProfile(
            name: "Metal Rhythm Guitar Volume II",
            match: ["metal rhythm guitar volume ii"],
            floor: 5.0, ceiling: 7.5,
            rationale: "Stetina II: riffs rápidos, dropped-D, tresillos en 12/8 y cambios de métrica"
        ),
        BookProfile(
            name: "Heavy Metal Lead Guitar Vol I",
            match: ["heavy metal lead guitar vol i"],
            floor: 2.5, ceiling: 6.0,
            rationale: "Stetina: primer solo de metal — pentatónica, bends de dos trastes y contorno escalar"
        ),
        BookProfile(
            name: "Heavy Metal Lead Guitar Vol II",
            match: ["heavy metal lead guitar vol ii"],
            floor: 5.5, ceiling: 8.0,
            rationale: "Stetina II: modos, arpegios extendidos y patrones escalares a tempo de solo"
        ),
        BookProfile(
            name: "Heavy Metal Guitar Tricks",
            match: ["heavy metal guitar tricks"],
            floor: 3.5, ceiling: 6.5,
            rationale: "recursos de efecto (armónicos golpeados, trucos de volumen) sobre una base ya formada"
        ),
        BookProfile(
            name: "Secrets To Writing Killer Metal Songs",
            match: ["secrets to writing killer metal songs"],
            floor: 3.5, ceiling: 6.5,
            rationale: "composición: el peso está en el análisis y el arreglo, no en la ejecución"
        ),
        BookProfile(
            name: "Speed And Thrash Metal",
            match: ["speed and thrash metal"],
            floor: 4.5, ceiling: 7.5,
            rationale: "downpicking sostenido y riffs de thrash a tempo alto"
        ),
        BookProfile(
            name: "Blues Rhythms You Can Use",
            match: ["blues rhythms you can use"],
            floor: 3.0, ceiling: 6.0,
            rationale: "Ganapes: acordes de novena y trecena, spread voicings y ritmo con swing"
        ),
        BookProfile(
            name: "More Blues You Can Use",
            match: ["more blues you can use"],
            floor: 3.5, ceiling: 6.5,
            rationale: "Ganapes: fraseo de blues real, vibrato de calidad, tremolo y rakes"
        ),
        BookProfile(
            name: "Breakthrough Blues-Rock Rhythm Fills",
            match: ["breakthrough blues", "mcerlain"],
            floor: 4.0, ceiling: 6.5,
            rationale: "McErlain: rellenos entre acordes, mezcla ritmo y solo en el mismo compás"
        ),
        BookProfile(
            name: "Speed Mechanics For The Lead Guitar",
            match: ["speed mechanics"],
            floor: 5.0, ceiling: 9.0,
            rationale: "Stetina: el método de velocidad de referencia, llega a sextillos y solos completos"
        ),
        BookProfile(
            name: "Shred Guitar",
            match: ["shred guitar"],
            floor: 5.5, ceiling: 9.5,
            rationale: "Hanson: barrido, tapping y modos exóticos a tempo de disco"
        )
    ]

    /// Para ejercicios cargados a mano o de un libro que todavía no tiene perfil.
    private static let defaultProfile = BookProfile(
        name: "Sin perfil de libro",
        match: [],
        floor: 2.5, ceiling: 7.0,
        rationale: "libro sin perfil conocido: rango amplio, manda la técnica declarada"
    )

    // MARK: - Modificadores por técnica

    /// Cuánto suma o resta cada recurso técnico sobre la base del libro. Los valores son de criterio
    /// docente: lo que suma es lo que agrega una coordinación nueva (barrido, tapping, salto de
    /// cuerda), no lo que simplemente suena más rápido.
    private struct Modifier {
        let keywords: [String]
        let delta: Double
        let reason: String
    }

    private static let modifiers: [Modifier] = [
        // Mano derecha
        .init(keywords: ["sweep picking", "barrido", "sweep"], delta: 1.4,
              reason: "barrido: exige muting rodante y que cada nota no se solape"),
        .init(keywords: ["tapping", "ocho dedos", "eight finger", "dos manos"], delta: 1.3,
              reason: "tapping: articulación de la mano derecha sobre el diapasón"),
        .init(keywords: ["economy picking", "economia de pua"], delta: 1.1,
              reason: "economía de púa: rompe la alternancia automática"),
        .init(keywords: ["string skipping", "saltos de cuerda", "salto de cuerda", "skipping"], delta: 1.0,
              reason: "salto de cuerda: sin cuerda intermedia de referencia"),
        .init(keywords: ["armonicos artificiales", "pinch harmonic", "armonicos golpeados", "tapped harmonic"], delta: 1.0,
              reason: "armónicos artificiales: punto de contacto exacto con la púa"),
        .init(keywords: ["palanca", "whammy", "vibrato bar"], delta: 0.9,
              reason: "palanca: control de afinación fuera del traste"),
        .init(keywords: ["hybrid picking", "hibrido", "pua y dedos"], delta: 0.9,
              reason: "híbrido: púa y dedos coordinados en la misma frase"),
        .init(keywords: ["tremolo", "punteo tremolo"], delta: 0.8,
              reason: "tremolo: repetición sostenida sin acumular tensión"),
        .init(keywords: ["fingerstyle", "fingerpicking", "dedos", "pulgar"], delta: 0.6,
              reason: "mano derecha sin púa: independencia de dedos"),
        .init(keywords: ["gallop", "galope"], delta: 0.6,
              reason: "galope: subdivisión desigual sostenida"),
        .init(keywords: ["downpicking", "pua hacia abajo", "downstroke", "ataques descendentes"], delta: 0.5,
              reason: "downpicking: resistencia del antebrazo a tempo alto"),
        .init(keywords: ["armonicos naturales", "armonico", "harmonics"], delta: 0.5,
              reason: "armónicos: punto de contacto y limpieza"),
        .init(keywords: ["alternate picking", "picking alterno", "punteo alterno", "punteo alternado", "pua alternada"], delta: 0.4,
              reason: "púa alterna: sincronía entre ambas manos"),
        .init(keywords: ["rake", "rakes"], delta: 0.4,
              reason: "rakes: cuerdas apagadas antes de la nota objetivo"),
        .init(keywords: ["palm mute", "muteo", "muting", "apagado"], delta: -0.2,
              reason: "muting: recurso de control, no de dificultad"),

        // Mano izquierda
        .init(keywords: ["rolling finger", "rolling", "cejilla rodante"], delta: 1.0,
              reason: "rolling: un dedo pisando trastes contiguos sin que se solapen"),
        .init(keywords: ["manos invertidas", "mano invertida"], delta: 1.2,
              reason: "posición invertida: coordinación fuera de lo habitual"),
        .init(keywords: ["stretch", "apertura", "estiramiento"], delta: 0.8,
              reason: "apertura amplia: exige mano izquierda ya formada"),
        .init(keywords: ["legato", "hammer", "pull off", "pull-off", "ligado"], delta: 0.5,
              reason: "legato: fuerza pareja sin ayuda de la púa"),
        .init(keywords: ["double stop", "double stops", "dobles cuerdas", "terceras", "sextas", "octavas"], delta: 0.5,
              reason: "dobles cuerdas: dos voces afinadas al mismo tiempo"),
        .init(keywords: ["vibrato"], delta: 0.5,
              reason: "vibrato: velocidad y amplitud controladas a voluntad"),
        .init(keywords: ["bending", "bend", "string bending"], delta: 0.4,
              reason: "bending: afinación del destino, no solo el gesto"),
        .init(keywords: ["independencia de dedos"], delta: 0.4,
              reason: "independencia: dedos 3 y 4 al mismo nivel que 1 y 2"),
        .init(keywords: ["slide", "deslizamiento", "cambio de posicion", "cambios de posicion"], delta: 0.2,
              reason: "cambio de posición: llegada afinada tras el desplazamiento"),
        .init(keywords: ["cejilla", "barre"], delta: 0.1,
              reason: "cejilla: presión pareja en seis cuerdas"),

        // Material armónico y melódico
        .init(keywords: ["sustitucion tritonal", "dominantes secundarios", "prestamo modal", "intercambio modal", "no diatonic"], delta: 1.3,
              reason: "armonía no diatónica: hay que oír la tensión, no solo digitarla"),
        .init(keywords: ["frigio dominante", "lidio b7", "escala alterada", "superlocrio", "disminuida", "disminuid", "octatonica", "tonos enteros"], delta: 1.2,
              reason: "escala simétrica o alterada: fuera de la sonoridad diatónica habitual"),
        .init(keywords: ["voice leading", "conduccion de voces"], delta: 1.1,
              reason: "conducción de voces: decisión armónica en cada nota"),
        .init(keywords: ["modo", "modos", "dorico", "frigio", "lidio", "mixolidio", "eolico", "locrio"], delta: 0.9,
              reason: "modos: elegir el centro tonal correcto sobre cada acorde"),
        .init(keywords: ["novena", "oncena", "trecena", "extensiones", "alterad"], delta: 0.8,
              reason: "extensiones: voicings de cuatro voces o más"),
        .init(keywords: ["septima", "seventh", "arpegios de septima"], delta: 0.7,
              reason: "acordes de séptima: cuatro notas por posición"),
        .init(keywords: ["tres notas por cuerda", "three notes per string", "3 notas por cuerda"], delta: 0.7,
              reason: "tres notas por cuerda: digitación que empuja el tempo"),
        .init(keywords: ["arpegio", "arpegios", "arpeggio", "arpeggios"], delta: 0.5,
              reason: "arpegios: una nota por cuerda con muting entre medio"),
        .init(keywords: ["improvisacion", "improvisar", "solo", "solos", "lick"], delta: 0.5,
              reason: "aplicación libre: además de tocarlo hay que decidirlo"),
        .init(keywords: ["caged"], delta: 0.4,
              reason: "CAGED: cinco formas conectadas en todo el mástil"),
        .init(keywords: ["triada", "triadas", "triads"], delta: 0.2,
              reason: "tríadas: tres voces por posición"),
        .init(keywords: ["pentatonica", "pentatonic"], delta: -0.2,
              reason: "pentatónica: la digitación más familiar del instrumento"),
        .init(keywords: ["power chord", "power chords", "quintas"], delta: -0.7,
              reason: "power chords: dos dedos, forma transportable"),
        .init(keywords: ["acordes abiertos", "primera posicion", "notas al aire", "cuerdas al aire"], delta: -0.9,
              reason: "primera posición: sin cejilla ni desplazamientos"),

        // Ritmo
        .init(keywords: ["polirritmia", "polyrhythm", "metrica impar", "compas compuesto", "12/8", "7/8", "5/4"], delta: 1.0,
              reason: "métrica poco habitual: contar deja de ser automático"),
        .init(keywords: ["sextillo", "sextuplet", "seisillo"], delta: 0.9,
              reason: "sextillos: seis notas por pulso"),
        .init(keywords: ["sincopa", "sincopad", "syncopat", "ligadura"], delta: 0.6,
              reason: "síncopa: acentos fuera del pulso"),
        .init(keywords: ["semicorchea", "16th", "sixteenth"], delta: 0.5,
              reason: "semicorcheas: cuatro notas por pulso"),
        .init(keywords: ["tresillo", "triplet"], delta: 0.5,
              reason: "tresillos: subdivisión ternaria sobre pulso binario"),
        .init(keywords: ["shuffle", "swing"], delta: 0.3,
              reason: "shuffle: la corchea deja de ser pareja"),
        .init(keywords: ["silencio", "silencios", "redonda", "blanca"], delta: -0.4,
              reason: "figuras largas: mucho tiempo para preparar cada nota"),

        // Formato y enfoque
        .init(keywords: ["transcrip", "al oido", "transcribir"], delta: 0.8,
              reason: "transcripción: el oído hace el trabajo antes que las manos"),
        .init(keywords: ["analisis"], delta: 0.3,
              reason: "análisis: comprensión antes que ejecución"),
        .init(keywords: ["composicion", "escribir riffs"], delta: 0.3,
              reason: "composición: criterio propio sobre material conocido"),
        .init(keywords: ["cromatic"], delta: -0.3,
              reason: "cromático: digitación mecánica y predecible"),
        .init(keywords: ["calentamiento", "warm up", "warm-up"], delta: -0.6,
              reason: "calentamiento: pensado para entrar en temperatura, no para exigir"),

        // Alcance e integración, señales que aparecen sobre todo en las descripciones importadas.
        .init(keywords: ["cinco patrones", "5 patrones", "cinco posiciones", "todo el mastil", "todas las posiciones"], delta: 0.6,
              reason: "recorrido global: conecta varias zonas del mástil sin reiniciar"),
        .init(keywords: ["varias posiciones", "diferentes posiciones", "cambios de posicion suaves", "a traves del mastil", "por todo el mastil"], delta: 0.4,
              reason: "varias posiciones: exige orientación durante el desplazamiento"),
        .init(keywords: ["pieza completa", "solo completo", "performance", "tema completo", "con banda", "backing track", "pista de acompanamiento"], delta: 0.3,
              reason: "aplicación continua: hay que sostener la técnica dentro de música real"),
        .init(keywords: ["combina", "combinando", "simultaneamente", "al mismo tiempo", "mientras"], delta: 0.3,
              reason: "integración: coordina más de una tarea en la misma frase"),
        .init(keywords: ["una sola posicion", "primera posicion", "primer patron", "una sola cuerda", "en una cuerda"], delta: -0.4,
              reason: "alcance reducido: una sola posición o cuerda limita las decisiones")
    ]

    /// Las palabras clave son constantes, pero normalizarlas dentro de cada comparación hacía que
    /// ordenar el catálogo completo repitiera miles de veces el mismo trabajo de Unicode.
    private static let normalizedModifierKeywords: [[String]] = modifiers.map { modifier in
        modifier.keywords.map(normalized)
    }

    /// Evidencia pedagógica extraída de `technique`, título, capítulo y especialmente de la
    /// descripción/notas. No sustituye el texto original: lo convierte en consignas útiles.
    private struct PedagogicalSignal {
        let keywords: [String]
        let label: String
        let demand: String
        let prerequisite: String
        let practice: String
        let priority: Int
    }

    private static let pedagogicalSignals: [PedagogicalSignal] = [
        .init(keywords: ["sweep picking", "barrido", "sweep"], label: "barrido y limpieza entre cuerdas",
              demand: "Separar cada nota del barrido: la púa fluye en un gesto, pero la mano izquierda libera una cuerda antes de activar la siguiente.",
              prerequisite: "Arpegios lentos de tres cuerdas y muting independiente con ambas manos.",
              practice: "Aísla primero el descenso y luego el ascenso en grupos de tres cuerdas; sube tempo solo cuando no se solapen notas.", priority: 100),
        .init(keywords: ["tapping", "ocho dedos", "eight finger", "dos manos"], label: "tapping y articulación de dos manos",
              demand: "Igualar volumen, ataque y duración entre la mano que pulsa y la que martilla sobre el diapasón.",
              prerequisite: "Hammer-ons y pull-offs parejos, además de muting fiable en cuerdas vecinas.",
              practice: "Practica una sola cuerda con dinámica pareja antes de extender el patrón o añadir cambios de cuerda.", priority: 98),
        .init(keywords: ["economy picking", "economia de pua"], label: "economía de púa",
              demand: "Cambiar entre alternancia y barrido según la dirección del cruce de cuerda sin perder el pulso.",
              prerequisite: "Púa alterna estable y cruces de cuerda limpios a tempo moderado.",
              practice: "Marca la dirección de cada ataque y repite únicamente el cruce que rompe la continuidad.", priority: 94),
        .init(keywords: ["string skipping", "saltos de cuerda", "salto de cuerda", "skipping"], label: "saltos de cuerda",
              demand: "Acertar una cuerda no adyacente y silenciar la que queda en medio sin usarla como referencia.",
              prerequisite: "Púa alterna y muting controlados en cambios entre cuerdas contiguas.",
              practice: "Reduce el ejercicio a dos cuerdas no adyacentes y comprueba que la cuerda omitida permanezca muda.", priority: 92),
        .init(keywords: ["armonicos artificiales", "pinch harmonic", "armonicos golpeados", "tapped harmonic"], label: "armónicos artificiales",
              demand: "Encontrar simultáneamente el punto de ataque de la púa y el nodo que hace hablar al armónico.",
              prerequisite: "Muting preciso y control de púa sobre notas individuales.",
              practice: "Busca primero un armónico fiable en una sola nota y conserva ese ángulo antes de mover la frase.", priority: 90),
        .init(keywords: ["palanca", "whammy", "vibrato bar"], label: "palanca y afinación móvil",
              demand: "Controlar alturas que no están fijadas por un traste y regresar exactamente a la afinación.",
              prerequisite: "Oído para reconocer semitono y tono, y vibrato afinado sin palanca.",
              practice: "Ensaya cada caída o subida contra una nota de referencia antes de tocarla dentro de la frase.", priority: 88),
        .init(keywords: ["hybrid picking", "hibrido", "pua y dedos", "fingerstyle", "fingerpicking"], label: "coordinación de púa y dedos",
              demand: "Repartir voces entre púa y dedos manteniendo volumen y tiempo homogéneos.",
              prerequisite: "Pulso estable y capacidad de aislar cuerdas sin rozar las vecinas.",
              practice: "Separa las voces: toca primero solo la púa, luego solo los dedos y finalmente vuelve a unirlas.", priority: 84),
        .init(keywords: ["downpicking", "pua hacia abajo", "downstroke", "gallop", "galope", "tremolo", "punteo tremolo"], label: "resistencia y economía de mano derecha",
              demand: "Mantener ataques regulares sin que el antebrazo se endurezca ni el movimiento crezca con el tempo.",
              prerequisite: "Corcheas limpias con metrónomo y una postura de púa sin tensión acumulada.",
              practice: "Trabaja ráfagas breves seguidas de descanso; detente en cuanto cambie el tono o aparezca rigidez.", priority: 82),
        .init(keywords: ["alternate picking", "picking alterno", "punteo alterno", "punteo alternado", "pua alternada"], label: "sincronización con púa alterna",
              demand: "Hacer coincidir cada cambio de dedo con un ataque de púa de dirección predecible.",
              prerequisite: "Movimiento corto de púa y digitación relajada a tempo lento.",
              practice: "Usa acentos por pulso y busca cuatro repeticiones idénticas antes de subir 2–3 BPM.", priority: 80),
        .init(keywords: ["legato", "hammer", "pull off", "pull-off", "ligado"], label: "legato parejo",
              demand: "Producir hammer-ons y pull-offs con el mismo volumen, duración y claridad que las notas pulsadas.",
              prerequisite: "Independencia básica de los dedos 2, 3 y 4 sin apretar el pulgar.",
              practice: "Practica pares de dedos y escucha si alguna nota desaparece; la velocidad viene después de igualar el volumen.", priority: 78),
        .init(keywords: ["bending", "bend", "string bending"], label: "bends afinados",
              demand: "Llegar a una altura concreta y sostenerla sin pasarse, no solo empujar la cuerda.",
              prerequisite: "Reconocer de oído medio tono, un tono y tono y medio antes de ejecutar el gesto.",
              practice: "Toca primero la nota objetivo en su traste, memorízala y luego compara cada bend contra esa referencia.", priority: 76),
        .init(keywords: ["vibrato"], label: "vibrato controlado",
              demand: "Elegir y repetir conscientemente amplitud y velocidad sin alterar la nota central.",
              prerequisite: "Bends pequeños afinados y sostener una nota sin exceso de presión.",
              practice: "Practica oscilaciones contadas con metrónomo —dos, tres y cuatro por pulso— antes de usar vibrato libre.", priority: 75),
        .init(keywords: ["stretch", "apertura", "estiramiento"], label: "apertura de mano izquierda",
              demand: "Cubrir una distancia amplia sin girar la muñeca ni compensar con presión excesiva.",
              prerequisite: "Postura neutra del pulgar y capacidad de desplazar la mano en bloque.",
              practice: "Empieza en trastes altos, donde la distancia es menor, y baja un traste solo cuando la mano siga relajada.", priority: 74),
        .init(keywords: ["double stop", "double stops", "dobles cuerdas", "terceras", "sextas", "octavas"], label: "dobles cuerdas afinadas",
              demand: "Controlar dos voces a la vez, incluida su afinación relativa durante bends o desplazamientos.",
              prerequisite: "Notas individuales limpias y conocimiento de la forma interválica usada.",
              practice: "Escucha primero cada voz por separado y después verifica que ninguna domine ni arrastre a la otra.", priority: 72),
        .init(keywords: ["slide", "deslizamiento", "cambio de posicion", "cambios de posicion"], label: "cambios de posición",
              demand: "Llegar al traste de destino a tiempo, con presión mínima y sin ruido de arrastre no intencional.",
              prerequisite: "Ubicar visualmente el destino antes de mover la mano.",
              practice: "Detén el ejercicio justo después de cada desplazamiento y comprueba afinación, tiempo y relajación de la llegada.", priority: 70),
        .init(keywords: ["sustitucion tritonal", "dominantes secundarios", "prestamo modal", "intercambio modal", "no diatonic"], label: "armonía no diatónica",
              demand: "Entender y oír por qué un acorde externo crea tensión y hacia dónde resuelve.",
              prerequisite: "Funciones tónica–subdominante–dominante y armonización de la escala mayor.",
              practice: "Reduce la progresión al acorde de tensión y su resolución; canta las notas guía antes de improvisar.", priority: 96),
        .init(keywords: ["frigio dominante", "lidio b7", "escala alterada", "superlocrio", "disminuida", "octatonica", "tonos enteros"], label: "material escalar alterado o simétrico",
              demand: "Relacionar una sonoridad poco familiar con el acorde exacto que la admite, además de memorizar la digitación.",
              prerequisite: "Escala mayor, intervalos y arpegio del acorde dominante.",
              practice: "Sostén el acorde de destino y limita la improvisación a tres notas características antes de recorrer la escala completa.", priority: 95),
        .init(keywords: ["voice leading", "conduccion de voces"], label: "conducción de voces",
              demand: "Elegir cada inversión por el movimiento individual de sus voces, no por una forma aislada.",
              prerequisite: "Tríadas, inversiones y notas de cada acorde en al menos una zona del mástil.",
              practice: "Escribe soprano, voces internas y bajo por separado; después busca el voicing que realice esos movimientos.", priority: 93),
        .init(keywords: ["modo", "modos", "dorico", "frigio", "lidio", "mixolidio", "eolico", "locrio"], label: "modos aplicados",
              demand: "Mantener audible el centro tonal y destacar la nota característica del modo sobre la armonía correcta.",
              prerequisite: "Escala mayor por grados y funciones armónicas básicas.",
              practice: "Usa un pedal de tónica y frases cortas que terminen en la nota característica; evita correr la digitación de arriba abajo.", priority: 86),
        .init(keywords: ["novena", "oncena", "trecena", "extensiones", "septima", "seventh"], label: "acordes extendidos",
              demand: "Ubicar cuatro o más voces y decidir cuáles conservar cuando la guitarra no permite tocarlas todas.",
              prerequisite: "Tríadas, séptimas e intervalos reconocibles dentro de una forma de acorde.",
              practice: "Nombra raíz, tercera, séptima y extensión en cada voicing antes de moverlo por la progresión.", priority: 68),
        .init(keywords: ["arpegio", "arpegios", "arpeggio", "arpeggios"], label: "arpegios y muting",
              demand: "Cruzar cuerdas manteniendo una sola nota activa y reconociendo la función de cada nota del acorde.",
              prerequisite: "Tríadas y cruces de cuerda limpios a tempo lento.",
              practice: "Detén cada nota antes de tocar la siguiente y di raíz, tercera, quinta o séptima mientras recorres la forma.", priority: 66),
        .init(keywords: ["improvisacion", "improvisar", "solo", "solos", "lick"], label: "aplicación musical y fraseo",
              demand: "Tomar decisiones de ritmo, registro y resolución en tiempo real, no limitarse a repetir una digitación.",
              prerequisite: "Una forma técnica memorizada y capacidad de seguir la armonía sin detenerse.",
              practice: "Limita primero el vocabulario a tres notas y una sola idea rítmica; amplía solo cuando puedas construir frases con respiración.", priority: 64),
        .init(keywords: ["caged", "triada", "triadas", "triads"], label: "visualización armónica del mástil",
              demand: "Ver las notas del acorde en varias inversiones y escoger la forma que minimiza el movimiento.",
              prerequisite: "Intervalos de raíz, tercera y quinta, y notas de las cuerdas 6, 5 y 4.",
              practice: "Mantente en una zona de cinco trastes y enlaza los acordes por la voz más cercana antes de transportarlos.", priority: 62),
        .init(keywords: ["polirritmia", "polyrhythm", "metrica impar", "compas compuesto", "12/8", "7/8", "5/4", "sextillo", "sextuplet", "seisillo"], label: "subdivisión compleja",
              demand: "Conservar el pulso mientras la agrupación interna cambia o deja de coincidir con los acentos habituales.",
              prerequisite: "Subdividir corcheas, semicorcheas y tresillos en voz alta con metrónomo.",
              practice: "Palméalo y cuéntalo antes de tocar; añade las notas solo cuando los acentos sobrevivan sin la guitarra.", priority: 89),
        .init(keywords: ["sincopa", "sincopad", "syncopat", "ligadura", "semicorchea", "16th", "sixteenth", "tresillo", "triplet", "shuffle", "swing"], label: "subdivisión y acentos",
              demand: "Colocar ataques y silencios dentro del pulso sin adelantar los contratiempos ni aplastar el swing.",
              prerequisite: "Pulso de negras estable y capacidad de contar la subdivisión en voz alta.",
              practice: "Toca una sola nota apagada, contando todos los huecos, antes de reincorporar acordes o cambios de posición.", priority: 73),
        .init(keywords: ["transcrip", "al oido", "transcribir", "analisis", "composicion", "escribir riffs"], label: "decisión auditiva y musical",
              demand: "Escuchar, formular una hipótesis y justificarla en vez de resolver una digitación ya dada.",
              prerequisite: "Reconocer pulso, forma y funciones armónicas básicas.",
              practice: "Trabaja fragmentos muy breves y deja por escrito qué oyes antes de comprobarlo con el instrumento.", priority: 69),
        .init(keywords: ["cinco patrones", "5 patrones", "cinco posiciones", "todo el mastil", "todas las posiciones", "varias posiciones", "diferentes posiciones", "por todo el mastil"], label: "orientación en varias posiciones",
              demand: "Conservar el mapa de notas al desplazarse y enlazar posiciones sin pausas ni saltos de volumen.",
              prerequisite: "Una posición completamente memorizada y notas raíz localizadas en el mástil.",
              practice: "Une solo dos posiciones vecinas por una nota común; añade la siguiente cuando el cambio deje de sentirse como un salto.", priority: 79),
        .init(keywords: ["pieza completa", "solo completo", "performance", "tema completo", "con banda", "backing track", "pista de acompanamiento"], label: "continuidad musical",
              demand: "Sostener tiempo, forma y recuperación de errores durante una ejecución continua.",
              prerequisite: "Cada sección estable por separado y conocimiento de la forma de la pieza.",
              practice: "Haz primero una pasada sin detenerte a tempo reducido; anota los dos puntos de quiebre y trabaja únicamente esos enlaces.", priority: 67),
        .init(keywords: ["power chord", "power chords", "quintas", "acordes abiertos", "notas al aire", "primera posicion"], label: "formas fundamentales",
              demand: "Cambiar de forma sin cortar el pulso y silenciar las cuerdas que no pertenecen al acorde.",
              prerequisite: "Postura relajada y lectura básica de tablatura o diagramas.",
              practice: "Ensaya el cambio sin rasguear, luego en negras y finalmente con el patrón rítmico original.", priority: 45)
    ]

    /// Tope de lo que puede mover la suma de modificadores, para que un ejercicio con seis palabras
    /// clave no termine valiendo más que el libro completo.
    private static let modifierCap = 2.5

    // MARK: - API

    /// Perfil del libro al que pertenece un título, o el genérico cuando no hay coincidencia.
    static func profile(forBook bookTitle: String) -> BookProfile {
        let needle = normalized(bookTitle)
        guard !needle.isEmpty else { return defaultProfile }
        // Gana la coincidencia más específica. Es importante para títulos como "Volume II": el
        // texto "Volume I" es prefijo suyo y, si se tomara el primer match, bajaría varios puntos.
        return bookProfiles.compactMap { profile -> (BookProfile, Int)? in
            guard let length = profile.match.filter({ needle.contains($0) }).map(\.count).max() else { return nil }
            return (profile, length)
        }
        .max { $0.1 < $1.1 }?.0 ?? defaultProfile
    }

    static func context(forBook bookTitle: String, in contexts: [String: BookContext]) -> BookContext? {
        contexts[normalized(bookTitle)]
    }

    /// Calcula el contexto (rango de páginas y numeración) de cada libro presente en el catálogo.
    static func bookContexts(for exercises: [LibraryExercise]) -> [String: BookContext] {
        var grouped: [String: [LibraryExercise]] = [:]
        for exercise in exercises {
            grouped[normalized(exercise.bookTitle), default: []].append(exercise)
        }

        return grouped.mapValues { items in
            let pages = items.map(\.page).filter { $0 > 0 }
            let numbered = items.compactMap { item -> (page: Int, number: Int)? in
                guard item.page > 0, let number = trailingNumber(in: item.exerciseNumber) else { return nil }
                return (item.page, number)
            }.sorted { $0.page < $1.page }

            var progressive = false
            if numbered.count >= 12 {
                // Una numeración sirve como progresión solo si sube junto con la página casi
                // siempre. Los libros que reinician la cuenta por capítulo fallan este test.
                let pairs = zip(numbered, numbered.dropFirst())
                let ascending = pairs.filter { $0.1.number >= $0.0.number }.count
                progressive = Double(ascending) / Double(numbered.count - 1) >= 0.85
            }

            return BookContext(
                firstPage: pages.min() ?? 0,
                lastPage: pages.max() ?? 0,
                highestNumber: numbered.map(\.number).max() ?? 0,
                numberingIsProgressive: progressive
            )
        }
    }

    /// Clasifica un ejercicio de Biblioteca. `context` es el resultado de `bookContexts` para su
    /// libro; sin él la clasificación sigue funcionando, solo pierde la ubicación dentro del método.
    static func assess(_ exercise: LibraryExercise, context: BookContext?) -> DifficultyAssessment {
        let score = exerciseScore(exercise, context: context, includeFactors: true)
        let pedagogy = exercisePedagogy(
            technique: exercise.technique,
            description: exercise.notes,
            haystack: score.haystack
        )
        return DifficultyAssessment(
            rating: score.rating,
            factors: score.factors,
            summary: pedagogy.summary,
            demands: pedagogy.demands,
            prerequisites: pedagogy.prerequisites,
            practiceFocus: pedagogy.practiceFocus
        )
    }

    /// Versión liviana para listas y ordenamientos que solo necesitan la nota. Evita construir la
    /// explicación pedagógica completa de cada ejercicio del catálogo.
    static func rating(for exercise: LibraryExercise, context: BookContext?) -> DifficultyRating {
        exerciseScore(exercise, context: context, includeFactors: false).rating
    }

    private static func exerciseScore(
        _ exercise: LibraryExercise,
        context: BookContext?,
        includeFactors: Bool
    ) -> (rating: DifficultyRating, factors: [String], haystack: String) {
        let profile = profile(forBook: exercise.bookTitle)
        var factors: [String] = []

        let position = position(of: exercise, in: context)
        let span = profile.ceiling - profile.floor
        let base = profile.floor + span * (position ?? 0.45)

        if includeFactors {
            factors.append("\(profile.name): \(format(profile.floor))-\(format(profile.ceiling))★ (\(profile.rationale))")
            if let position {
                factors.append("posición en el libro: \(Int((position * 100).rounded()))% → base \(format(base))★")
            } else {
                factors.append("sin página ni número de referencia: base \(format(base))★")
            }
        }

        let haystack = normalized([exercise.technique, exercise.exerciseNumber, exercise.chapter, exercise.notes].joined(separator: " "))
        var total = 0.0
        for (modifier, keywords) in zip(modifiers, normalizedModifierKeywords)
        where keywords.contains(where: haystack.contains) {
            total += modifier.delta
            if includeFactors { factors.append("\(signed(modifier.delta)) \(modifier.reason)") }
        }

        let bpm = exercise.targetBPM > 0 ? exercise.targetBPM : (highestBPM(in: haystack) ?? 0)
        if let tempoDelta = tempoDelta(forBPM: bpm) {
            total += tempoDelta
            if includeFactors { factors.append("\(signed(tempoDelta)) tempo declarado \(bpm) BPM") }
        } else if haystack.contains("velocidad") || haystack.contains("speed") || haystack.contains("rapido") || haystack.contains("shred") {
            total += 0.6
            if includeFactors { factors.append("+0,6 trabajo explícito de velocidad") }
        }

        if let legacyDelta = legacyLabelDelta(exercise.legacyCatalogDifficulty) {
            total += legacyDelta
            if includeFactors {
                factors.append("\(signed(legacyDelta)) etiqueta del catálogo original (\(exercise.legacyCatalogDifficulty ?? ""))")
            }
        }

        let capped = min(max(total, -modifierCap), modifierCap)
        if includeFactors, capped != total {
            factors.append("ajuste acotado a \(signed(capped)) para no salirse del alcance del libro")
        }

        // Se permite desbordar un punto el rango del libro: un ejercicio de tapping a ocho dedos en
        // un método intermedio sigue siendo más difícil que el resto de ese método.
        let bounded = min(max(base + capped, profile.floor - 1.0), profile.ceiling + 1.0)
        return (DifficultyRating(stars: bounded), factors, haystack)
    }

    /// Clasifica un concepto de teoría. Acá no hay exigencia física, así que manda el tema: nombrar
    /// las cuerdas al aire y explicar una sustitución tritonal no viven en el mismo lugar de la
    /// escala aunque estén en el mismo libro.
    static func assess(_ concept: LibraryConcept) -> DifficultyAssessment {
        let haystack = normalized([concept.title, concept.category, concept.summary].joined(separator: " "))
        var factors: [String] = []

        let topic = theoryTopics.first { entry in entry.keywords.contains { haystack.contains(normalized($0)) } }
        let base = topic?.stars ?? 4.0
        factors.append(topic.map { "tema «\($0.name)»: base \(format($0.stars))★" }
            ?? "tema general de teoría: base 4★")

        var total = 0.0
        if concept.isExercise {
            total += 0.3
            factors.append("+0,3 ejercicio a resolver, no solo lectura")
        }
        if let legacyDelta = legacyLabelDelta(concept.legacyCatalogLevel) {
            total += legacyDelta
            factors.append("\(signed(legacyDelta)) etiqueta del catálogo original (\(concept.legacyCatalogLevel ?? ""))")
        }

        let guidance = theoryGuidance(for: topic)
        let sourceSummary = conciseSourceText(concept.summary)
        let opening = sourceSummary.isEmpty
            ? "Este material estudia \((topic?.name ?? concept.category).lowercased())."
            : sourceSummary
        return DifficultyAssessment(
            rating: DifficultyRating(stars: base + total),
            factors: factors,
            summary: "\(opening) Dominarlo significa \(guidance.mastery)",
            demands: concept.isExercise
                ? ["Resolver o aplicar el concepto sin depender de una respuesta ya escrita.", guidance.mastery]
                : [guidance.mastery],
            prerequisites: [guidance.prerequisite],
            practiceFocus: guidance.practice
        )
    }

    /// Dificultad de adquisición de cada habilidad del Test Integral: cuánto cuesta llegar a
    /// dominarla, no cuánto sabe hoy el alumno (eso lo mide `SkillTopic.status`).
    static func assess(skillNamed name: String) -> DifficultyAssessment {
        let needle = normalized(name)
        if let entry = skillStars.first(where: { normalized($0.name) == needle }) {
            return DifficultyAssessment(
                rating: DifficultyRating(stars: entry.stars),
                factors: [entry.reason],
                summary: "Esta habilidad se valora por lo que cuesta dominarla de forma estable, no por conocer su definición. \(sentenceCased(entry.reason))",
                demands: ["Repetir el recurso con limpieza, tiempo y relajación, y conservarlo al aplicarlo en música real."],
                prerequisites: [prerequisiteForSkill(named: entry.name)],
                practiceFocus: "Aísla una variable —limpieza, tiempo o tensión— y exige tres repeticiones consistentes antes de aumentar la dificultad."
            )
        }
        // Habilidad agregada fuera del catálogo del Test Integral: se estima por sus palabras.
        let haystack = needle
        var stars = 4.5
        var reason = "habilidad fuera del Test Integral: estimada por su nombre"
        for modifier in modifiers where modifier.keywords.contains(where: { haystack.contains(normalized($0)) }) {
            stars += modifier.delta
            reason = modifier.reason
        }
        return DifficultyAssessment(
            rating: DifficultyRating(stars: stars),
            factors: [reason],
            summary: "Habilidad estimada a partir de la exigencia técnica expresada en su nombre.",
            demands: [sentenceCased(reason)],
            prerequisites: ["Pulso estable, postura relajada y control limpio del recurso anterior en la progresión."],
            practiceFocus: "Empieza con un patrón breve y medible; aumenta una sola variable por vez."
        )
    }

    // MARK: - Lectura pedagógica de descripciones y notas

    private struct PedagogicalProfile {
        let summary: String
        let demands: [String]
        let prerequisites: [String]
        let practiceFocus: String
    }

    private static func exercisePedagogy(
        technique: String,
        description: String,
        haystack: String
    ) -> PedagogicalProfile {
        let matches = pedagogicalSignals
            .filter { signal in signal.keywords.contains { haystack.contains(normalized($0)) } }
            .sorted { $0.priority > $1.priority }

        var seenLabels: Set<String> = []
        let distinct = matches.filter { seenLabels.insert($0.label).inserted }
        let leading = Array(distinct.prefix(3))

        let source = conciseSourceText(description)
        let focus = technique.trimmingCharacters(in: .whitespacesAndNewlines)
        let material = focus.isEmpty ? "la ejecución propuesta" : focus.lowercased()
        let difficultyReading: String
        if leading.isEmpty {
            difficultyReading = "La exigencia principal está en completar el patrón con sonido limpio, pulso estable y una mecánica relajada."
        } else {
            difficultyReading = "La dificultad real se concentra en \(naturalList(leading.map(\.label)))."
        }
        let opening = source.isEmpty ? "Trabajo de \(material)." : source

        return PedagogicalProfile(
            summary: "\(opening) \(difficultyReading)",
            demands: leading.isEmpty
                ? ["Mantener limpieza, tiempo y relajación de principio a fin, no solo acertar las notas."]
                : leading.map(\.demand),
            prerequisites: leading.isEmpty
                ? ["Poder tocar el material inmediatamente anterior del método sin detenerse ni acumular tensión."]
                : unique(leading.map(\.prerequisite)),
            practiceFocus: leading.first?.practice
                ?? "Divide el material en frases cortas, fija un tempo que permita tres repeticiones limpias y sube de 2–3 BPM."
        )
    }

    private struct TheoryGuidance {
        let mastery: String
        let prerequisite: String
        let practice: String
    }

    private static func theoryGuidance(for topic: TheoryTopic?) -> TheoryGuidance {
        switch topic?.name {
        case "Recursos no diatónicos":
            TheoryGuidance(
                mastery: "oír la tensión de un acorde ajeno a la tonalidad, explicar su función y conducirlo hacia una resolución convincente.",
                prerequisite: "Armonización de la escala mayor, funciones armónicas y acordes de séptima.",
                practice: "Reduce cada caso a dos acordes —tensión y resolución—, canta sus notas guía y recién después transpórtalo a otras tonalidades."
            )
        case "Conducción de voces":
            TheoryGuidance(
                mastery: "seguir cada voz de manera independiente y escoger inversiones por su movimiento, no por una forma memorizada.",
                prerequisite: "Tríadas, inversiones e intervalos dentro de los acordes.",
                practice: "Escribe primero bajo y voz superior; completa las voces internas procurando el menor movimiento posible."
            )
        case "Improvisación y relación acorde-escala":
            TheoryGuidance(
                mastery: "elegir notas en tiempo real según el acorde presente y construir frases que creen y resuelvan tensión.",
                prerequisite: "Arpegios, funciones armónicas y al menos una escala conectada en varias posiciones.",
                practice: "Improvisa primero solo con notas del acorde; añade una tensión disponible por vez y resuélvela conscientemente."
            )
        case "Oído y transcripción":
            TheoryGuidance(
                mastery: "convertir lo que se escucha en ritmo, intervalos, función y ubicación concreta en el instrumento.",
                prerequisite: "Pulso estable, intervalos básicos y mapa inicial del diapasón.",
                practice: "Trabaja fragmentos de dos a cuatro segundos: canta, identifica el ritmo y solo entonces busca las notas en la guitarra."
            )
        case "Modos":
            TheoryGuidance(
                mastery: "mantener un centro tonal audible y reconocer la nota característica que diferencia cada modo.",
                prerequisite: "Escala mayor, grados y funciones armónicas.",
                practice: "Usa un pedal de tónica y contrasta cada modo con mayor o menor; crea frases que destaquen una sola nota característica."
            )
        case "Transporte y afinaciones":
            TheoryGuidance(
                mastery: "mover relaciones interválicas y funciones sin depender de una tonalidad o digitación fija.",
                prerequisite: "Intervalos, notas raíz y formas transportables en el mástil.",
                practice: "Transporta una frase por cuartas y explica qué cambió en notas, digitación y registro."
            )
        case "Arpegios", "Inversiones y CAGED", "Tríadas", "Séptimas y extensiones":
            TheoryGuidance(
                mastery: "identificar la función de cada voz y localizarla en más de una forma útil del mástil.",
                prerequisite: "Intervalos y construcción de la escala mayor.",
                practice: "Nombra raíz, tercera, quinta y séptima mientras tocas; después enlaza dos acordes en la misma zona del mástil."
            )
        case "Funciones armónicas", "Armonización y progresiones":
            TheoryGuidance(
                mastery: "explicar hacia dónde empuja cada acorde y reconocer esa función dentro de una progresión real.",
                prerequisite: "Escala mayor por grados y construcción de tríadas.",
                practice: "Analiza una canción conocida con números romanos, reduce sus acordes a funciones y transpórtala a otra tonalidad."
            )
        case "Escalas menores", "Escala mayor y tonalidades", "Pentatónicas y blues":
            TheoryGuidance(
                mastery: "reconocer la estructura interválica, ubicar sus notas raíz y usar la escala sobre una armonía compatible.",
                prerequisite: "Tonos, semitonos e intervalos básicos.",
                practice: "Construye la escala desde una nota nueva, canta sus grados y crea una frase que termine claramente en la tónica."
            )
        case "Intervalos", "Alteraciones y enarmonía", "Notas y diapasón":
            TheoryGuidance(
                mastery: "nombrar y localizar la relación sin contar desde cero cada vez.",
                prerequisite: "Nombres de las notas y orientación básica por cuerdas y trastes.",
                practice: "Responde en ambos sentidos: del nombre a la guitarra y desde una nota tocada hacia su nombre y función."
            )
        case "Ritmo y compás":
            TheoryGuidance(
                mastery: "sentir, contar y ejecutar la subdivisión sin que el pulso dependa de las notas de la guitarra.",
                prerequisite: "Pulso de negras estable con metrónomo.",
                practice: "Cuenta y palmea el patrón, luego tócalo en una cuerda apagada y solo al final incorpora las alturas."
            )
        default:
            TheoryGuidance(
                mastery: "explicarlo con palabras propias, reconocerlo en música y aplicarlo sin copiar el ejemplo.",
                prerequisite: "Los conceptos inmediatamente anteriores del mismo capítulo.",
                practice: "Resume la idea en una frase, crea un ejemplo propio y busca un caso real en una canción conocida."
            )
        }
    }

    private static func prerequisiteForSkill(named name: String) -> String {
        let value = normalized(name)
        if value.contains("sweep") { return "Arpegios lentos, cambios de cuerda y muting independiente." }
        if value.contains("tapping") { return "Legato parejo y muting fiable antes de añadir la mano derecha al diapasón." }
        if value.contains("economy") || value.contains("string skipping") || value.contains("hybrid") {
            return "Púa alterna, cruces de cuerda y pulso estable a tempo moderado."
        }
        if value.contains("no diaton") || value.contains("voice leading") || value.contains("improvisacion") {
            return "Intervalos, tríadas, funciones armónicas y mapa funcional del diapasón."
        }
        if value.contains("modo") { return "Escala mayor, grados y capacidad de oír un centro tonal." }
        if value.contains("acorde") || value.contains("triada") || value.contains("arpegio") {
            return "Notas del diapasón e intervalos de raíz, tercera y quinta."
        }
        return "Postura relajada, pulso estable y control consciente de la habilidad inmediatamente anterior."
    }

    private static func conciseSourceText(_ value: String, limit: Int = 220) -> String {
        let collapsed = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }

        let firstSentence: String
        if let ending = collapsed.firstIndex(where: { [".", "!", "?"].contains($0) }) {
            firstSentence = String(collapsed[...ending])
        } else {
            firstSentence = collapsed
        }
        guard firstSentence.count > limit else { return sentenceCased(firstSentence) }
        let prefix = String(firstSentence.prefix(limit))
        let trimmed = prefix.split(separator: " ").dropLast().joined(separator: " ")
        return sentenceCased(trimmed) + "…"
    }

    private static func sentenceCased(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    private static func naturalList(_ values: [String]) -> String {
        switch values.count {
        case 0: return ""
        case 1: return values[0]
        case 2: return "\(values[0]) y \(values[1])"
        default: return values.dropLast().joined(separator: ", ") + " y " + (values.last ?? "")
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - Auxiliares

    /// 0 = principio del libro, 1 = final. Prefiere la numeración propia del ejercicio cuando esa
    /// numeración realmente progresa (Guitar Aerobics, Fretboard Freedom); si no, usa la página.
    private static func position(of exercise: LibraryExercise, in context: BookContext?) -> Double? {
        guard let context else { return nil }

        let pagePosition: Double? = if context.pageSpan > 0, exercise.page > 0 {
            min(max(Double(exercise.page - context.firstPage) / Double(context.pageSpan), 0), 1)
        } else {
            nil
        }

        if context.numberingIsProgressive, context.highestNumber > 1,
           let number = trailingNumber(in: exercise.exerciseNumber) {
            let numberPosition = min(max(Double(number - 1) / Double(context.highestNumber - 1), 0), 1)
            // En catálogos OCR aparece ocasionalmente un número grande en una página temprana. Si
            // ambas fuentes se contradicen mucho, la página del PDF es la evidencia más fiable.
            if let pagePosition {
                return abs(pagePosition - numberPosition) <= 0.2
                    ? (pagePosition + numberPosition) / 2
                    : pagePosition
            }
            return numberPosition
        }
        return pagePosition
    }

    /// Último número del título ("Ejercicio 196b" → 196, "Lick #365" → 365).
    static func trailingNumber(in title: String) -> Int? {
        let digits = title.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard let last = digits.last, let value = Int(last), value > 0, value < 10_000 else { return nil }
        return value
    }

    private static func highestBPM(in haystack: String) -> Int? {
        guard haystack.contains("bpm") else { return nil }
        let numbers = haystack.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
            .filter { (30...320).contains($0) }
        return numbers.max()
    }

    private static func tempoDelta(forBPM bpm: Int) -> Double? {
        switch bpm {
        case 200...: 1.2
        case 160..<200: 0.7
        case 120..<160: 0.2
        case 1..<80: -0.3
        default: nil
        }
    }

    private static func legacyLabelDelta(_ raw: String?) -> Double? {
        switch raw?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) {
        case "principiante": -0.6
        case "avanzado": 0.8
        default: nil
        }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func signed(_ value: Double) -> String {
        (value > 0 ? "+" : "") + format(value)
    }

    // MARK: - Tablas de referencia

    private struct TheoryTopic {
        let name: String
        let keywords: [String]
        let stars: Double
    }

    /// Orden importante: el primero que coincide gana, así que los temas más específicos van antes
    /// que los generales ("escala alterada" antes que "escala").
    private static let theoryTopics: [TheoryTopic] = [
        .init(name: "Recursos no diatónicos", keywords: ["sustitucion tritonal", "sustituciones tritonales", "dominante secundario", "dominantes secundarios", "prestamo modal", "prestamos modales", "intercambio modal", "acorde disminuido", "aumentado sexta"], stars: 8.5),
        .init(name: "Conducción de voces", keywords: ["voice leading", "conduccion de voces"], stars: 8.0),
        .init(name: "Improvisación y relación acorde-escala", keywords: ["acorde escala", "chord scale", "improvisacion"], stars: 7.5),
        .init(name: "Oído y transcripción", keywords: ["transcrip", "dictado", "reconocimiento auditivo"], stars: 7.5),
        .init(name: "Modos", keywords: ["modo", "modos", "dorico", "frigio", "lidio", "mixolidio", "eolico", "locrio"], stars: 7.0),
        .init(name: "Transporte y afinaciones", keywords: ["transporte", "transportar", "afinacion", "drop d", "capo"], stars: 6.0),
        .init(name: "Arpegios", keywords: ["arpegio"], stars: 5.5),
        .init(name: "Funciones armónicas", keywords: ["funcion armonica", "tonica", "subdominante", "dominante"], stars: 5.5),
        .init(name: "Inversiones y CAGED", keywords: ["inversion", "voicing", "caged"], stars: 5.5),
        .init(name: "Armonización y progresiones", keywords: ["armonizacion", "progresion", "cadencia", "grado"], stars: 5.0),
        .init(name: "Séptimas y extensiones", keywords: ["septima", "novena", "oncena", "trecena", "extension"], stars: 5.0),
        .init(name: "Tríadas", keywords: ["triada", "triadas"], stars: 3.5),
        .init(name: "Escalas menores", keywords: ["menor armonica", "menor melodica", "escala menor"], stars: 3.5),
        .init(name: "Escala mayor y tonalidades", keywords: ["escala mayor", "tonalidad", "armadura", "circulo de quintas"], stars: 3.0),
        .init(name: "Intervalos", keywords: ["intervalo"], stars: 3.0),
        .init(name: "Pentatónicas y blues", keywords: ["pentatonica", "escala de blues", "blue note"], stars: 2.5),
        .init(name: "Ritmo y compás", keywords: ["compas", "figura", "corchea", "negra", "subdivision", "metrica"], stars: 2.5),
        .init(name: "Alteraciones y enarmonía", keywords: ["alteracion", "sostenido", "bemol", "enarmon"], stars: 2.0),
        .init(name: "Notas y diapasón", keywords: ["nota", "diapason", "mastil", "traste", "cuerda al aire"], stars: 1.5)
    ]

    private struct SkillEntry {
        let name: String
        let stars: Double
        let reason: String
    }

    /// Las 38 habilidades sembradas por `SeedService`, con la dificultad real de llegar a dominarlas.
    /// Las de técnica siguen el orden del Test Integral (12 fundamentos + 6 de especialización) y las
    /// de teoría sus cuatro bloques.
    private static let skillStars: [SkillEntry] = [
        // Técnica — fundamentos
        .init(name: "Postura, relajación y mecánica general", stars: 1.5,
              reason: "es lo primero que se enseña, pero sostenerlo bajo presión cuesta toda la vida"),
        .init(name: "Acordes y guitarra rítmica", stars: 2.5,
              reason: "acordes abiertos y power chords son la puerta de entrada al instrumento"),
        .init(name: "Sincronización entre ambas manos", stars: 3.0,
              reason: "cuello de botella de casi todo lo demás: se nota apenas sube el tempo"),
        .init(name: "Slides y cambios de posición", stars: 3.0,
              reason: "llegar afinado tras el desplazamiento, no solo desplazarse"),
        .init(name: "Muting y palm muting", stars: 3.0,
              reason: "silenciar lo que no suena es la mitad de un sonido limpio"),
        .init(name: "Ritmo, subdivisión y groove", stars: 3.5,
              reason: "el pulso interno se construye durante años, no en un mes"),
        .init(name: "Alternate picking", stars: 3.5,
              reason: "el movimiento es simple; que sea parejo y económico no lo es"),
        .init(name: "Legato", stars: 4.0,
              reason: "hammer-ons con volumen real sin ayuda de la púa"),
        .init(name: "Bending", stars: 4.0,
              reason: "el destino tiene que quedar afinado, no aproximado"),
        .init(name: "Vibrato", stars: 4.5,
              reason: "lo último que se madura: es la firma de sonido de cada guitarrista"),
        .init(name: "Downpicking, tremolo picking y gallops", stars: 4.5,
              reason: "resistencia del antebrazo a tempo alto sin acumular tensión"),
        .init(name: "Aplicación musical, oído, teoría y repertorio", stars: 5.5,
              reason: "cruza todo lo demás: saberlo tocar y saber cuándo usarlo"),

        // Técnica — especialización
        .init(name: "Armónicos", stars: 6.0,
              reason: "naturales son accesibles; artificiales y golpeados piden precisión de púa"),
        .init(name: "String skipping", stars: 6.5,
              reason: "sin cuerda intermedia de referencia, el muting queda a cargo de ambas manos"),
        .init(name: "Tapping", stars: 7.0,
              reason: "una mano nueva sobre el diapasón, con su propio muting"),
        .init(name: "Economy picking", stars: 7.0,
              reason: "convive con la púa alterna y hay que elegir cuál usar en cada cambio"),
        .init(name: "Hybrid picking, fingerstyle y palanca", stars: 7.0,
              reason: "tres mecánicas distintas de mano derecha además de la púa"),
        .init(name: "Sweep picking", stars: 8.0,
              reason: "la técnica que más tiempo de muting rodante exige antes de sonar bien"),

        // Teoría — bloque A
        .init(name: "Notas musicales y organización del diapasón", stars: 1.5,
              reason: "el mapa mínimo: sin esto ningún otro módulo se sostiene"),
        .init(name: "Alteraciones y notas enarmónicas", stars: 2.0,
              reason: "consecuencia directa de conocer las notas"),
        .init(name: "Escalas pentatónicas y blues", stars: 2.5,
              reason: "cinco notas y una digitación que la guitarra regala"),
        .init(name: "Ritmo, figuras y compás", stars: 2.5,
              reason: "leer y contar subdivisiones, base de todo el resto"),
        .init(name: "Intervalos", stars: 3.0,
              reason: "unidad de medida de la armonía; hay que oírlos, no solo calcularlos"),
        .init(name: "Escala mayor y tonalidades", stars: 3.0,
              reason: "sistema de referencia del que salen grados, acordes y modos"),
        .init(name: "Escalas menores", stars: 3.5,
              reason: "tres menores distintas y cuándo aplica cada una"),
        .init(name: "Construcción de tríadas", stars: 3.5,
              reason: "primer paso de acordes como estructura y no como forma memorizada"),

        // Teoría — bloque B
        .init(name: "Acordes de séptima y extensiones", stars: 5.0,
              reason: "cuatro voces o más, y elegir cuáles se dejan fuera en la guitarra"),
        .init(name: "Armonización de la escala mayor", stars: 5.0,
              reason: "de la escala salen los siete acordes: acá empieza a explicarse el repertorio"),
        .init(name: "Progresiones y cadencias", stars: 5.0,
              reason: "reconocer de oído hacia dónde va la música"),
        .init(name: "Inversiones, voicings y sistema CAGED", stars: 5.5,
              reason: "el mismo acorde en cinco lugares, con criterio para elegir"),
        .init(name: "Funciones armónicas", stars: 5.5,
              reason: "explica por qué una progresión funciona, no solo cuál es"),
        .init(name: "Arpegios y notas del acorde", stars: 5.5,
              reason: "une armonía y digitación: el puente hacia improvisar sobre cambios"),

        // Teoría — bloque C y D
        .init(name: "Transporte y afinaciones", stars: 6.0,
              reason: "mover todo de tonalidad y sostenerlo en afinaciones alternativas"),
        .init(name: "Modos de la escala mayor", stars: 7.0,
              reason: "el tema donde más gente se queda: exige oír el centro tonal"),
        .init(name: "Improvisación y relación acorde-escala", stars: 7.5,
              reason: "decidir en tiempo real sobre armonía que se mueve"),
        .init(name: "Oído, transcripción, lectura y sonido eléctrico", stars: 7.5,
              reason: "sacar música de oído es la habilidad que más tarda en madurar"),
        .init(name: "Voice leading y conducción de voces", stars: 8.0,
              reason: "cada voz con su propio camino: criterio de arreglador"),
        .init(name: "Recursos armónicos no diatónicos", stars: 8.5,
              reason: "todo lo que se sale de la tonalidad y aun así suena inevitable")
    ]
}
