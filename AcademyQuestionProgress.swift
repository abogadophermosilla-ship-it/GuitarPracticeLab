import Foundation
import SwiftData

/// Progreso Leitner de una pregunta creada en la Academia. Se mantiene separado del progreso de
/// las 100 preguntas fijas porque esas tarjetas antiguas se identifican por tema+índice.
@Model
final class AcademyQuestionProgress {
    @Attribute(.unique) var id: UUID
    var questionID: UUID
    var boxLevel: Int
    var correctCount: Int
    var wrongCount: Int
    var lastReviewedDate: Date?
    var nextReviewDate: Date

    init(questionID: UUID) {
        self.id = questionID
        self.questionID = questionID
        self.boxLevel = 1
        self.correctCount = 0
        self.wrongCount = 0
        self.lastReviewedDate = nil
        self.nextReviewDate = .distantPast
    }
}
