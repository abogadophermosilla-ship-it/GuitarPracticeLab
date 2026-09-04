import Foundation
import SwiftUI

enum PracticeCategory: String, CaseIterable, Codable, Identifiable {
    case technique = "Técnica"
    case rhythm = "Ritmo"
    case repertoire = "Repertorio"
    case improvisation = "Improvisación"
    case theory = "Teoría"
    case earTraining = "Oído"
    case tone = "Sonido"
    case production = "Producción"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .technique: "metronome"
        case .rhythm: "waveform.path"
        case .repertoire: "music.note.list"
        case .improvisation: "sparkles"
        case .theory: "book.closed"
        case .earTraining: "ear"
        case .tone: "dial.medium"
        case .production: "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .technique: .blue
        case .rhythm: .orange
        case .repertoire: .green
        case .improvisation: .purple
        case .theory: .indigo
        case .earTraining: .pink
        case .tone: .teal
        case .production: .brown
        }
    }

    /// Áreas en las que tiene sentido registrar una figura o subdivisión junto al BPM.
    var supportsRhythmicFigure: Bool {
        switch self {
        case .technique, .rhythm, .repertoire, .improvisation: true
        case .theory, .earTraining, .tone, .production: false
        }
    }
}

/// Forma concreta de abordar una tarea de teoría. Se guarda como texto en `PracticeTask` para que
/// las tareas no se limiten a decir qué estudiar: también explican cómo trabajarlo.
enum TheoryTaskMode: String, CaseIterable, Codable, Identifiable {
    case readAndExplain = "Leer y explicar"
    case writtenSummary = "Resumir por escrito"
    case flashcards = "Repasar con flashcards"
    case answerQuestions = "Responder preguntas"
    case applyOnGuitar = "Aplicar en la guitarra"
    case guided = "Seguir indicaciones"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .readAndExplain: "book.pages"
        case .writtenSummary: "square.and.pencil"
        case .flashcards: "rectangle.on.rectangle"
        case .answerQuestions: "checkmark.bubble"
        case .applyOnGuitar: "music.note"
        case .guided: "list.bullet.clipboard"
        }
    }

    var defaultInstructions: String {
        switch self {
        case .readAndExplain:
            "Lee el material y después explícalo con tus propias palabras sin mirarlo."
        case .writtenSummary:
            "Escribe un resumen breve con las ideas principales y al menos un ejemplo."
        case .flashcards:
            "Completa un repaso de flashcards y revisa cada respuesta incorrecta."
        case .answerQuestions:
            "Responde preguntas sin consultar el material y revisa los errores al terminar."
        case .applyOnGuitar:
            "Ubica el concepto en el diapasón y toca al menos un ejemplo."
        case .guided:
            "Sigue los pasos indicados en la tarea y comprueba el resultado al terminar."
        }
    }
}

/// Forma concreta de trabajar una tarea rítmica. Complementa la figura/subdivisión: la figura dice
/// qué tocar y este modo indica cómo estudiarla.
enum RhythmTaskMode: String, CaseIterable, Codable, Identifiable {
    case countAndClap = "Contar y palmear"
    case metronome = "Tocar con metrónomo"
    case strumming = "Aplicar con rasgueo"
    case backingTrack = "Tocar con backing track"
    case sightReading = "Hacer lectura rítmica"
    case guided = "Seguir indicaciones"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .countAndClap: "hands.clap"
        case .metronome: "metronome"
        case .strumming: "music.note"
        case .backingTrack: "waveform"
        case .sightReading: "music.quarternote.3"
        case .guided: "list.bullet.clipboard"
        }
    }

    var defaultInstructions: String {
        switch self {
        case .countAndClap:
            "Marca el pulso con el pie, cuenta la subdivisión en voz alta y palmea la figura antes de tocarla."
        case .metronome:
            "Empieza a un tempo cómodo con metrónomo, mantén la subdivisión pareja y sube el BPM solo cuando salga estable."
        case .strumming:
            "Mantén el pulso con el pie y aplica el patrón de rasgueo sin cortar el movimiento de la mano."
        case .backingTrack:
            "Toca sobre un groove o backing track, escuchando el pulso y comprobando que no te adelantes ni te atrases."
        case .sightReading:
            "Lee y cuenta cada compás antes de tocarlo; después ejecútalo sin detener el pulso ante un error."
        case .guided:
            "Sigue los pasos indicados en la tarea y comprueba que el pulso y la subdivisión se mantengan estables."
        }
    }
}

/// Forma concreta de trabajar una canción del repertorio. Permite que la tarea indique si toca
/// aislar una sección, consolidar tempo o comprobar la ejecución completa.
enum RepertoireTaskMode: String, CaseIterable, Codable, Identifiable {
    case bySections = "Trabajar por secciones"
    case slowTempo = "Practicar a tempo lento"
    case originalRecording = "Tocar con la grabación"
    case fullRun = "Hacer una pasada completa"
    case fromMemory = "Tocar de memoria"
    case guided = "Seguir indicaciones"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bySections: "square.split.2x1"
        case .slowTempo: "metronome"
        case .originalRecording: "play.circle"
        case .fullRun: "music.note.list"
        case .fromMemory: "brain.head.profile"
        case .guided: "list.bullet.clipboard"
        }
    }

    var defaultInstructions: String {
        switch self {
        case .bySections:
            "Elige una sección, divídela en pasajes cortos y únelos solo cuando cada parte salga estable."
        case .slowTempo:
            "Empieza a un tempo en el que puedas tocar limpio y sube el BPM gradualmente sin perder precisión."
        case .originalRecording:
            "Toca junto a la grabación original, prestando atención a entradas, cortes, dinámica y cambios de sección."
        case .fullRun:
            "Toca la canción completa sin detenerte y anota al terminar las secciones que necesitan trabajo aislado."
        case .fromMemory:
            "Toca sin partitura ni tablatura; si dudas, identifica el punto exacto antes de volver a consultar el material."
        case .guided:
            "Sigue los pasos indicados en la tarea y comprueba el avance dentro de la canción al terminar."
        }
    }
}

/// Agrupa las 8 `PracticeCategory` en 5 casilleros para Sesiones y Tareas, pedido explícito del
/// usuario (Repertorio / Ejercicios / Improvisación / Teoría / Otros) sin tocar el modelo de datos.
enum PracticeBucket: String, CaseIterable, Identifiable {
    case repertorio = "Repertorio"
    case ejercicios = "Ejercicios"
    case improvisacion = "Improvisación"
    case teoria = "Teoría"
    case otros = "Otros"

    var id: String { rawValue }

    static func bucket(for category: PracticeCategory) -> PracticeBucket {
        switch category {
        case .repertoire: .repertorio
        case .technique: .ejercicios
        case .improvisation: .improvisacion
        case .theory: .teoria
        case .rhythm, .earTraining, .tone, .production: .otros
        }
    }
}

/// Período de agregación para el desglose de minutos por habilidad puntual en Progreso — distinto
/// de `PracticeBucket`, que agrupa categorías amplias, no habilidades individuales.
enum SkillPracticePeriod: String, CaseIterable, Identifiable {
    case day = "Hoy"
    case week = "Esta semana"
    case month = "Este mes"

    var id: String { rawValue }
}

/// De dónde vino una `PracticeTask` (o, desde que también lo adoptó `PracticeSession`, una sesión),
/// para poder mostrar un vínculo de vuelta al origen en Tareas y Sesiones. Orden pensado para el
/// picker de "Tarea" del timer de práctica: biblioteca y Profesor primero (los dos casos que pidió
/// el usuario explícitamente), manual al final.
enum TaskSourceKind: String, CaseIterable, Codable, Identifiable {
    /// Entrenador interactivo de notas del mástil. No necesita `sourceID`: el origen es el módulo
    /// único y su tarea diaria se identifica por este valor estable.
    case fretboard
    case library
    /// Concepto o ejercicio teórico de Biblioteca (`LibraryConcept`) — distinto de `.library`, que
    /// apunta a un `LibraryExercise`, porque ambos catálogos tienen su propio espacio de `UUID` y
    /// el origen necesita saber a qué modelo resolver el `sourceID`.
    case libraryConcept
    case profesor
    /// Escalón de una `SkillLadder` — distinto de `.profesor` porque necesita recurrencia diaria
    /// hasta que el escalón se marque logrado (`RecurringPracticeService`), no solo un vínculo de
    /// "ver en Profesor IA"; `sourceID` guarda el `id` del `SkillLadderStep`.
    case skillLadder
    case repertoire
    case academia
    case clases
    case manual

    var id: String { rawValue }

    /// Título de sección al agrupar tareas/sesiones por origen (picker del timer, Tareas, Sesiones).
    var sectionTitle: String {
        switch self {
        case .manual: "Manual"
        case .fretboard: "Mástil"
        case .library, .libraryConcept: "Biblioteca"
        case .repertoire: "Repertorio"
        case .academia: "Academia"
        case .profesor, .skillLadder: "Profesor IA"
        case .clases: "Clases"
        }
    }

    var label: String {
        switch self {
        case .manual: ""
        case .fretboard: "Abrir entrenador del mástil"
        case .library, .libraryConcept: "Ver en Biblioteca"
        case .repertoire: "Ver en Repertorio"
        case .academia: "Ver en Academia"
        case .profesor, .skillLadder: "Ir a Profesor IA"
        case .clases: "Ver en Clases"
        }
    }

    var icon: String {
        switch self {
        case .manual: ""
        case .fretboard: "guitars.fill"
        case .library: "books.vertical.fill"
        case .libraryConcept: "book.closed.fill"
        case .repertoire: "music.note.list"
        case .academia: "brain.head.profile"
        case .profesor, .skillLadder: "person.wave.2.fill"
        case .clases: "graduationcap.fill"
        }
    }

    var targetSection: SidebarSection? {
        switch self {
        case .manual: nil
        case .fretboard: .fretboard
        case .library, .libraryConcept: .library
        case .repertoire: .repertoire
        case .academia: .academy
        case .profesor, .skillLadder: .aiCoach
        case .clases: .lessons
        }
    }
}

enum PracticeResult: String, CaseIterable, Codable, Identifiable {
    case started = "Iniciado"
    case learning = "En aprendizaje"
    case reducedTempo = "Logrado a tempo reducido"
    case targetTempo = "Logrado a tempo objetivo"
    case review = "Requiere revisión"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .started: "Pudiste comenzar, pero el pasaje todavía se bloquea."
        case .learning: "Hubo avance, aunque todavía no es estable."
        case .reducedTempo: "Salió limpio por debajo del tempo objetivo."
        case .targetTempo: "Salió al tempo objetivo; la retención se confirmará más adelante."
        case .review: "Aparecieron errores que conviene aislar y corregir."
        }
    }
}

/// Contexto en que se comprobó el resultado. Una repetición aislada y una ejecución dentro de la
/// canción no demuestran exactamente lo mismo, por eso este dato acompaña al BPM y al resultado.
enum PracticeApplicationContext: String, CaseIterable, Codable, Identifiable {
    case isolated = "Pasaje aislado"
    case metronome = "Con metrónomo"
    case backingTrack = "Con backing track"
    case fullPiece = "En canción o pieza completa"
    case fromMemory = "De memoria / de oído"

    var id: String { rawValue }
}

/// Figura o subdivisión elegida por el usuario para una práctica. Se guarda separada del BPM:
/// 80 BPM en negras y 80 BPM en semicorcheas tienen el mismo pulso, pero una velocidad real de
/// notas completamente distinta. `unspecified` permite empezar una tarea sin que la app imponga
/// de antemano cómo hay que tocarla.
enum RhythmicFigure: String, CaseIterable, Codable, Identifiable, Hashable {
    case unspecified
    case wholeNotes
    case dottedHalfNotes
    case halfNotes
    case quarterNotes
    case dottedQuarterNotes
    case quarterNoteTriplets
    case eighthNotes
    case eighthNoteTriplets
    case sixteenthNotes
    case quintuplets
    case sextuplets
    case septuplets
    case thirtySecondNotes
    case dottedLongShort
    case dottedShortLong
    case shuffle
    case gallop
    case reverseGallop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified: "Sin definir"
        case .wholeNotes: "Redondas"
        case .dottedHalfNotes: "Blancas con puntillo"
        case .halfNotes: "Blancas"
        case .quarterNotes: "Negras"
        case .dottedQuarterNotes: "Negras con puntillo"
        case .quarterNoteTriplets: "Tresillos de negras"
        case .eighthNotes: "Corcheas"
        case .eighthNoteTriplets: "Tresillos de corcheas"
        case .sixteenthNotes: "Semicorcheas"
        case .quintuplets: "Quintillos"
        case .sextuplets: "Seisillos / sextillos"
        case .septuplets: "Septillos"
        case .thirtySecondNotes: "Fusas"
        case .dottedLongShort: "Largo-corto"
        case .dottedShortLong: "Corto-largo"
        case .shuffle: "Shuffle / swing"
        case .gallop: "Galope"
        case .reverseGallop: "Galope invertido"
        }
    }

    var pulseDescription: String {
        switch self {
        case .unspecified: "Elígela según el tempo y el objetivo del ejercicio."
        case .wholeNotes: "1 nota cada 4 pulsos"
        case .dottedHalfNotes: "1 nota cada 3 pulsos"
        case .halfNotes: "1 nota cada 2 pulsos"
        case .quarterNotes: "1 nota por pulso"
        case .dottedQuarterNotes: "1 nota cada pulso y medio; unidad de pulso habitual en 6/8"
        case .quarterNoteTriplets: "3 notas repartidas en 2 pulsos"
        case .eighthNotes: "2 notas por pulso"
        case .eighthNoteTriplets: "3 notas por pulso"
        case .sixteenthNotes: "4 notas por pulso"
        case .quintuplets: "5 notas por pulso"
        case .sextuplets: "6 notas por pulso"
        case .septuplets: "7 notas por pulso"
        case .thirtySecondNotes: "8 notas por pulso"
        case .dottedLongShort: "Corchea con puntillo + semicorchea"
        case .dottedShortLong: "Semicorchea + corchea con puntillo"
        case .shuffle: "Subdivisión ternaria con sensación largo-corto"
        case .gallop: "Corchea + dos semicorcheas"
        case .reverseGallop: "Dos semicorcheas + corchea"
        }
    }

    var countingGuide: String {
        switch self {
        case .unspecified: ""
        case .wholeNotes: "Sostén una nota durante cuatro clics."
        case .dottedHalfNotes: "Sostén una nota durante tres clics."
        case .halfNotes: "Toca en los pulsos 1 y 3 de un compás de 4/4."
        case .quarterNotes: "Cuenta 1, 2, 3, 4."
        case .dottedQuarterNotes: "En 6/8, siente dos pulsos grandes por compás."
        case .quarterNoteTriplets: "Distribuye tres ataques uniformes a lo largo de dos clics."
        case .eighthNotes: "Cuenta 1-y, 2-y, 3-y, 4-y."
        case .eighthNoteTriplets: "Cuenta 1-ta-ta, 2-ta-ta…"
        case .sixteenthNotes: "Cuenta 1-e-y-a, 2-e-y-a…"
        case .quintuplets: "Divide cada clic en cinco partes iguales."
        case .sextuplets: "Divide cada clic en seis partes iguales y acentúa la primera."
        case .septuplets: "Divide cada clic en siete partes iguales."
        case .thirtySecondNotes: "Divide cada clic en ocho partes iguales."
        case .dottedLongShort: "Alterna una duración de tres semicorcheas y otra de una."
        case .dottedShortLong: "Alterna una duración de una semicorchea y otra de tres."
        case .shuffle: "Piensa el pulso como un tresillo y toca la primera y la tercera parte."
        case .gallop: "Cuenta 1--y-a, 2--y-a…"
        case .reverseGallop: "Cuenta 1-e--, 2-e--…"
        }
    }

    var isSpecified: Bool { self != .unspecified }
}

enum ExerciseStatus: String, CaseIterable, Codable, Identifiable {
    case notStarted = "No iniciado"
    case learning = "En aprendizaje"
    case consolidating = "En consolidación"
    case reducedTempo = "Dominado a tempo reducido"
    case mastered = "Dominado"
    case periodicReview = "Revisión periódica"

    var id: String { rawValue }

    /// Orden de progreso (0 a 5) usado para detectar subidas de nivel en Progreso y para ordenar
    /// por avance sin repetir esta lógica en cada servicio. `periodicReview` cuenta como más
    /// avanzado que `learning` porque implica que ya se dominó antes y solo falta repaso.
    var progressWeight: Int {
        switch self {
        case .notStarted: 0
        case .learning: 1
        case .periodicReview: 2
        case .consolidating: 3
        case .reducedTempo: 4
        case .mastered: 5
        }
    }
}

enum AssetType: String, CaseIterable, Codable, Identifiable {
    case hardware = "Hardware"
    case software = "Software"

    var id: String { rawValue }
}

enum SkillDomain: String, CaseIterable, Codable, Identifiable {
    case technique = "Técnica"
    case theory = "Teoría"

    var id: String { rawValue }
}

enum SkillLevel: String, CaseIterable, Codable, Identifiable {
    case basic = "Básico"
    case intermediate = "Intermedio"
    case advanced = "Avanzado"

    var id: String { rawValue }
}

/// Banda de dominio demostrado de una habilidad. Desde SchemaV2 la calcula `SkillMasteryEngine`
/// usando evidencia multidimensional; el resultado aislado del Test Integral vive por separado en
/// `SkillTopic.testStatus`. Es distinto de `ExerciseStatus`, que mide ejercicios sueltos.
enum SkillMasteryLevel: String, CaseIterable, Codable, Identifiable {
    case notStarted = "No iniciado"
    case initial = "Inicial"
    case basic = "Básico"
    case intermediate = "Intermedio"
    case advanced = "Avanzado"
    case consolidated = "Consolidado"

    var id: String { rawValue }

    /// Mismo propósito que `ExerciseStatus.progressWeight`, para las 6 bandas del Test Integral.
    var progressWeight: Int {
        switch self {
        case .notStarted: 0
        case .initial: 1
        case .basic: 2
        case .intermediate: 3
        case .advanced: 4
        case .consolidated: 5
        }
    }
}

/// Nivel general del guitarrista (distinto de `SkillMasteryLevel`, que es por habilidad individual) —
/// bandas del Test Integral para el resultado ponderado de fundamentos + especialización.
enum OverallLevelBand: String, CaseIterable, Identifiable {
    case initial = "Inicial"
    case beginner = "Principiante"
    case basic = "Básico"
    case intermediate = "Intermedio"
    case intermediateHigh = "Intermedio alto"
    case advanced = "Avanzado"
    case advancedConsolidated = "Avanzado consolidado"

    var id: String { rawValue }
}

/// Las cuatro materias que la pestaña Progreso mide por separado.
enum ProgressCategory: String, CaseIterable, Codable, Identifiable {
    case technique = "Técnica"
    case theory = "Teoría"
    case exercise = "Ejercicio"
    case repertoire = "Repertorio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .technique: "hand.raised.fingers.spread"
        case .theory: "book.closed.fill"
        case .exercise: "checklist"
        case .repertoire: "music.note.list"
        }
    }

    var color: Color {
        switch self {
        case .technique: .blue
        case .theory: .indigo
        case .exercise: .teal
        case .repertoire: .green
        }
    }
}
