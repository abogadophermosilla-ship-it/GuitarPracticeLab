import Foundation

enum AcademyCardSource {
    case legacy(TheoryFlashcard)
    case authored(AcademyQuestion)
}

struct AcademyCard: Identifiable {
    let id: String
    let source: AcademyCardSource
    let topicName: String

    var prompt: String {
        switch source {
        case .legacy(let card): card.question.question
        case .authored(let question): question.prompt
        }
    }

    var imageData: Data? {
        if case .authored(let question) = source { return question.imageData }
        return nil
    }
}

enum AcademyScheduler {
    private struct Ranked {
        let card: AcademyCard
        let box: Int
        let wrong: Int
        let nextReview: Date
        let isDue: Bool
    }

    /// Crea un único pool con las 100 preguntas fijas y las preguntas creadas en la Academia.
    static func rankedCards(
        topics: [SkillTopic],
        legacyProgress: [TheoryFlashcardProgress],
        authoredQuestions: [AcademyQuestion],
        authoredProgress: [AcademyQuestionProgress],
        now: Date = .now
    ) -> (cards: [AcademyCard], dueCount: Int) {
        let topicByID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        let legacyByID = Dictionary(uniqueKeysWithValues: legacyProgress.map { ($0.id, $0) })
        let authoredByID = Dictionary(uniqueKeysWithValues: authoredProgress.map { ($0.questionID, $0) })

        var ranked: [Ranked] = []

        for topic in topics where topic.domain == .theory {
            for index in topic.assessmentQuestions.indices {
                let legacy = TheoryFlashcard(
                    id: TheoryFlashcardProgress.makeID(topicID: topic.id, questionIndex: index),
                    topic: topic,
                    questionIndex: index
                )
                let progress = legacyByID[legacy.id]
                let next = progress?.nextReviewDate ?? .distantPast
                ranked.append(Ranked(
                    card: AcademyCard(id: "legacy:\(legacy.id)", source: .legacy(legacy), topicName: topic.name),
                    box: progress?.boxLevel ?? 1,
                    wrong: progress?.wrongCount ?? 0,
                    nextReview: next,
                    isDue: progress == nil || next <= now
                ))
            }
        }

        for question in authoredQuestions {
            let progress = authoredByID[question.id]
            let next = progress?.nextReviewDate ?? .distantPast
            let topicName = question.topicID.flatMap { topicByID[$0]?.name } ?? "Teoría general"
            ranked.append(Ranked(
                card: AcademyCard(
                    id: "academy:\(question.id.uuidString)",
                    source: .authored(question),
                    topicName: topicName
                ),
                box: progress?.boxLevel ?? 1,
                wrong: progress?.wrongCount ?? 0,
                nextReview: next,
                isDue: progress == nil || next <= now
            ))
        }

        let sorted = ranked.sorted { lhs, rhs in
            if lhs.isDue != rhs.isDue { return lhs.isDue }
            if lhs.box != rhs.box { return lhs.box < rhs.box }
            if lhs.wrong != rhs.wrong { return lhs.wrong > rhs.wrong }
            return lhs.nextReview < rhs.nextReview
        }
        return (sorted.map(\.card), sorted.filter(\.isDue).count)
    }

    static func record(_ progress: AcademyQuestionProgress, isCorrect: Bool, now: Date = .now) {
        if isCorrect {
            progress.correctCount += 1
            progress.boxLevel = min(progress.boxLevel + 1, 5)
        } else {
            progress.wrongCount += 1
            progress.boxLevel = 1
        }
        progress.lastReviewedDate = now
        let days = TheoryFlashcardScheduler.boxIntervalDays[progress.boxLevel] ?? 0
        progress.nextReviewDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
    }
}
