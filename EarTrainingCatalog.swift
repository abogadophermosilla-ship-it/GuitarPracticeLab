import Foundation

/// Intervalo melódico dentro de una octava — contenido fijo, no generado por IA, mismo espíritu que
/// las preguntas del Test Integral.
enum EarInterval: Int, CaseIterable, Identifiable, Codable {
    case minor2 = 1
    case major2 = 2
    case minor3 = 3
    case major3 = 4
    case perfect4 = 5
    case tritone = 6
    case perfect5 = 7
    case minor6 = 8
    case major6 = 9
    case minor7 = 10
    case major7 = 11

    var id: Int { rawValue }
    var semitones: Int { rawValue }

    /// Clave estable para IDs de progreso — independiente de `label`, que es lo que se muestra en
    /// pantalla y podría cambiar de texto.
    var key: String {
        switch self {
        case .minor2: "2m"
        case .major2: "2M"
        case .minor3: "3m"
        case .major3: "3M"
        case .perfect4: "4J"
        case .tritone: "triton"
        case .perfect5: "5J"
        case .minor6: "6m"
        case .major6: "6M"
        case .minor7: "7m"
        case .major7: "7M"
        }
    }

    var label: String {
        switch self {
        case .minor2: "2ª menor"
        case .major2: "2ª mayor"
        case .minor3: "3ª menor"
        case .major3: "3ª mayor"
        case .perfect4: "4ª justa"
        case .tritone: "Tritono"
        case .perfect5: "5ª justa"
        case .minor6: "6ª menor"
        case .major6: "6ª mayor"
        case .minor7: "7ª menor"
        case .major7: "7ª mayor"
        }
    }
}

/// Calidad de acorde en posición fundamental — 5 calidades fijas.
enum EarChordQuality: String, CaseIterable, Identifiable, Codable {
    case major, minor, dominant7, diminished, augmented

    var id: String { rawValue }
    var key: String { rawValue }

    var label: String {
        switch self {
        case .major: "Mayor"
        case .minor: "Menor"
        case .dominant7: "Séptima dominante"
        case .diminished: "Disminuido"
        case .augmented: "Aumentado"
        }
    }

    var semitoneOffsets: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .dominant7: [0, 4, 7, 10]
        case .diminished: [0, 3, 6]
        case .augmented: [0, 4, 8]
        }
    }
}

/// Uno de los 16 ítems fijos del entrenamiento de oído (11 intervalos + 5 acordes).
enum EarTrainingItem: Identifiable, Hashable {
    case interval(EarInterval)
    case chord(EarChordQuality)

    static let all: [EarTrainingItem] =
        EarInterval.allCases.map { .interval($0) } + EarChordQuality.allCases.map { .chord($0) }

    var id: String {
        switch self {
        case .interval(let value): "interval#\(value.key)"
        case .chord(let value): "chord#\(value.key)"
        }
    }

    var label: String {
        switch self {
        case .interval(let value): value.label
        case .chord(let value): value.label
        }
    }

    var kindTitle: String {
        switch self {
        case .interval: "Intervalo"
        case .chord: "Acorde"
        }
    }

    /// Las opciones de una pregunta solo compiten contra ítems de su mismo tipo — mezclar
    /// intervalos y acordes en la misma grilla no ayuda a entrenar el oído, solo confunde.
    var siblingOptions: [EarTrainingItem] {
        switch self {
        case .interval: EarInterval.allCases.map { .interval($0) }
        case .chord: EarChordQuality.allCases.map { .chord($0) }
        }
    }
}

/// Una pregunta concreta: qué ítem hay que reconocer y con qué raíz MIDI se generó, para poder
/// reproducirla de nuevo con "Repetir" sin cambiar la nota a mitad de la pregunta.
struct EarTrainingQuestion: Identifiable {
    let id = UUID()
    let item: EarTrainingItem
    let rootMidi: Int

    /// E2–E5 en MIDI (40–76): deja margen para que la nota más aguda de un acorde de séptima o de un
    /// intervalo de 7ª mayor no se salga del rango cómodo de guitarra (E6 = 88).
    static func random(item: EarTrainingItem) -> EarTrainingQuestion {
        EarTrainingQuestion(item: item, rootMidi: Int.random(in: 40...76))
    }
}
