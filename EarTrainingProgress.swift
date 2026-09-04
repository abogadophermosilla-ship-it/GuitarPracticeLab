import Foundation
import SwiftData

/// Progreso de repetición espaciada de un ítem de Entrenamiento de oído — mismo mecanismo que
/// `TheoryFlashcardProgress`, aplicado a los 16 ítems fijos de `EarTrainingItem.all` (`id` =
/// `EarTrainingItem.id`) en vez de preguntas de texto.
@Model
final class EarTrainingProgress {
    @Attribute(.unique) var id: String
    var boxLevel: Int
    var correctCount: Int
    var wrongCount: Int
    var lastReviewedDate: Date?
    var nextReviewDate: Date

    init(id: String) {
        self.id = id
        self.boxLevel = 1
        self.correctCount = 0
        self.wrongCount = 0
        self.lastReviewedDate = nil
        self.nextReviewDate = .distantPast
    }
}

/// Contador agregado de Entrenamiento de oído (racha de aciertos consecutivos, mejor racha, totales)
/// — no cabe en `EarTrainingProgress` porque es por ítem; esto es global, un único registro
/// ("singleton", `id == "singleton"`). Alimenta las insignias de racha de oído.
@Model
final class EarTrainingStats {
    @Attribute(.unique) var id: String
    var currentStreak: Int
    var bestStreak: Int
    var totalAnswered: Int
    var totalCorrect: Int

    init(id: String = "singleton") {
        self.id = id
        self.currentStreak = 0
        self.bestStreak = 0
        self.totalAnswered = 0
        self.totalCorrect = 0
    }

    static func fetchOrCreate(in context: ModelContext) -> EarTrainingStats {
        if let existing = try? context.fetch(FetchDescriptor<EarTrainingStats>()).first {
            return existing
        }
        let created = EarTrainingStats()
        context.insert(created)
        return created
    }

    func record(isCorrect: Bool) {
        totalAnswered += 1
        if isCorrect {
            totalCorrect += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            currentStreak = 0
        }
    }
}
