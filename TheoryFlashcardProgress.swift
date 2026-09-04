import Foundation
import SwiftData

/// Progreso de repetición espaciada de una tarjeta de teoría, identificada por (topicID,
/// questionIndex) porque `AssessmentQuestion` no tiene identidad propia dentro del array de
/// `SkillTopic.assessmentQuestions` — ver el aviso en `SeedService.seedSkillTopics` sobre no
/// reordenar las preguntas de un tema existente en `SkillAssessmentQuestionBank`.
@Model
final class TheoryFlashcardProgress {
    @Attribute(.unique) var id: String
    var topicID: UUID
    var questionIndex: Int
    var boxLevel: Int
    var correctCount: Int
    var wrongCount: Int
    var lastReviewedDate: Date?
    var nextReviewDate: Date

    init(topicID: UUID, questionIndex: Int) {
        self.id = TheoryFlashcardProgress.makeID(topicID: topicID, questionIndex: questionIndex)
        self.topicID = topicID
        self.questionIndex = questionIndex
        self.boxLevel = 1
        self.correctCount = 0
        self.wrongCount = 0
        self.lastReviewedDate = nil
        self.nextReviewDate = .distantPast
    }

    static func makeID(topicID: UUID, questionIndex: Int) -> String {
        "\(topicID.uuidString)#\(questionIndex)"
    }
}
