import Foundation

/// Práctica en curso guardada fuera de la vista, para que cerrar la ventana (o la app) no la pierda.
/// Vive en `UserDefaults` y no en SwiftData a propósito: es estado efímero de la UI, no un registro
/// del diario — solo se convierte en `PracticeSession` cuando el usuario aprieta "Finalizar y
/// guardar".
struct PracticeTimerDraft: Codable {
    var accumulatedSeconds: TimeInterval
    var runStartedAt: Date?
    var savedAt: Date
    var taskID: UUID?
    var exerciseID: UUID?
    var songID: UUID?
    var categoryRaw: String
    var instrumentName: String
    var startBPM: Int
    var endBPM: Int
    var notes: String
    var difficulty: Int? = nil
    var resultRaw: String? = nil
    var correctRepetitions: Int? = nil
    var repertoireRepetitions: Int? = nil
    var tensionRating: Int? = nil
    var practiceContextRaw: String? = nil
    var wasColdCheck: Bool? = nil
    /// Opcional para recuperar borradores creados antes de que existiera este selector.
    var rhythmicFigureRaw: String? = nil

    private static let key = "practiceTimerDraft"

    static func save(_ draft: PracticeTimerDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> PracticeTimerDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PracticeTimerDraft.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

