import Foundation

/// Une una pregunta de teoría (`SkillTopic.assessmentQuestions`, dominio `.theory`) con su
/// `TheoryFlashcardProgress` si existe.
struct TheoryFlashcard: Identifiable {
    let id: String
    let topic: SkillTopic
    let questionIndex: Int

    var question: AssessmentQuestion { topic.assessmentQuestions[questionIndex] }

    /// Las preguntas de teoría siempre tienen exactamente una opción con puntaje > 0 (ver `tq()`
    /// en `SkillAssessmentQuestionBank`). Si esa invariante alguna vez se rompe, es mejor fallar
    /// fuerte en debug que marcar en silencio la opción A como correcta.
    var correctIndex: Int {
        guard let index = question.options.firstIndex(where: { $0.points > 0 }) else {
            assertionFailure("Pregunta de teoría sin opción correcta: \(question.question)")
            return 0
        }
        return index
    }
}

enum TheoryFlashcardScheduler {
    static let boxIntervalDays: [Int: Int] = [1: 0, 2: 1, 3: 3, 4: 7, 5: 14]
    private static let maxBoxLevel = 5

    /// Ordena todas las tarjetas de teoría: primero las que ya vencieron (`nextReviewDate <= now`,
    /// o sin progreso todavía) de más a menos urgentes — caja más baja primero, porque una sola
    /// falla resetea a caja 1 y eso ya las vuelve máxima prioridad; dentro de la misma caja, más
    /// fallos históricos primero como desempate. Las que aún no vencen van después, en el mismo
    /// orden, para que una sesión nunca quede vacía si el usuario quiere practicar de más.
    static func rankedCards(
        topics: [SkillTopic],
        progress: [TheoryFlashcardProgress],
        now: Date = .now
    ) -> (cards: [TheoryFlashcard], dueCount: Int) {
        let progressByID = Dictionary(uniqueKeysWithValues: progress.map { ($0.id, $0) })

        let all: [(card: TheoryFlashcard, progress: TheoryFlashcardProgress?)] = topics
            .filter { $0.domain == .theory }
            .flatMap { topic in
                topic.assessmentQuestions.indices.map { index in
                    let id = TheoryFlashcardProgress.makeID(topicID: topic.id, questionIndex: index)
                    return (TheoryFlashcard(id: id, topic: topic, questionIndex: index), progressByID[id])
                }
            }

        let due = all.filter { $0.progress == nil || $0.progress!.nextReviewDate <= now }
        let notDue = all.filter { !($0.progress == nil || $0.progress!.nextReviewDate <= now) }

        func rank(_ items: [(card: TheoryFlashcard, progress: TheoryFlashcardProgress?)]) -> [TheoryFlashcard] {
            items.sorted { lhs, rhs in
                let lBox = lhs.progress?.boxLevel ?? 1
                let rBox = rhs.progress?.boxLevel ?? 1
                if lBox != rBox { return lBox < rBox }
                let lWrong = lhs.progress?.wrongCount ?? 0
                let rWrong = rhs.progress?.wrongCount ?? 0
                if lWrong != rWrong { return lWrong > rWrong }
                return (lhs.progress?.nextReviewDate ?? .distantPast) < (rhs.progress?.nextReviewDate ?? .distantPast)
            }.map(\.card)
        }

        return (cards: rank(due) + rank(notDue), dueCount: due.count)
    }

    /// Actualiza el progreso tras responder: acierto sube una caja (tope 5, intervalo más largo);
    /// fallo resetea a caja 1, la máxima prioridad de nuevo — así se implementa el "peso por fallos".
    static func record(_ progress: TheoryFlashcardProgress, isCorrect: Bool, now: Date = .now) {
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
