import Foundation

/// Repetición espaciada de Entrenamiento de oído — copia literal de la lógica de
/// `TheoryFlashcardScheduler`, operando sobre los 16 ítems fijos de `EarTrainingItem.all` en vez de
/// preguntas de un topic.
enum EarTrainingScheduler {
    static let boxIntervalDays: [Int: Int] = [1: 0, 2: 1, 3: 3, 4: 7, 5: 14]
    private static let maxBoxLevel = 5

    /// Igual criterio de orden que `TheoryFlashcardScheduler.rankedCards`: vencidos primero (caja más
    /// baja, luego más fallos), después los que todavía no vencen, para que una sesión nunca quede
    /// vacía.
    static func rankedItems(
        progress: [EarTrainingProgress],
        now: Date = .now
    ) -> (items: [EarTrainingItem], dueCount: Int) {
        let progressByID = Dictionary(uniqueKeysWithValues: progress.map { ($0.id, $0) })
        let all = EarTrainingItem.all.map { (item: $0, progress: progressByID[$0.id]) }

        let due = all.filter { $0.progress == nil || $0.progress!.nextReviewDate <= now }
        let notDue = all.filter { !($0.progress == nil || $0.progress!.nextReviewDate <= now) }

        func rank(_ items: [(item: EarTrainingItem, progress: EarTrainingProgress?)]) -> [EarTrainingItem] {
            items.sorted { lhs, rhs in
                let lBox = lhs.progress?.boxLevel ?? 1
                let rBox = rhs.progress?.boxLevel ?? 1
                if lBox != rBox { return lBox < rBox }
                let lWrong = lhs.progress?.wrongCount ?? 0
                let rWrong = rhs.progress?.wrongCount ?? 0
                if lWrong != rWrong { return lWrong > rWrong }
                return (lhs.progress?.nextReviewDate ?? .distantPast) < (rhs.progress?.nextReviewDate ?? .distantPast)
            }.map(\.item)
        }

        return (items: rank(due) + rank(notDue), dueCount: due.count)
    }

    static func record(_ progress: EarTrainingProgress, isCorrect: Bool, now: Date = .now) {
        if isCorrect {
            progress.correctCount += 1
            progress.boxLevel = min(progress.boxLevel + 1, maxBoxLevel)
        } else {
            progress.wrongCount += 1
            progress.boxLevel = 1
        }
        progress.lastReviewedDate = now
        let days = boxIntervalDays[progress.boxLevel] ?? 0
        progress.nextReviewDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
    }
}
