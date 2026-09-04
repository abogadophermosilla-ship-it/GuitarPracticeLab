import Foundation
import SwiftData

enum AcademyQuestionType: String, CaseIterable, Codable, Identifiable {
    case multipleChoice = "Opción múltiple"
    case trueFalse = "Verdadero o falso"
    case fillBlank = "Completar palabra"

    var id: String { rawValue }
}

/// Pregunta creada por el usuario para la Academia. Puede usar texto solo o un recorte de una
/// página real de un PDF ya registrado en Biblioteca.
@Model
final class AcademyQuestion {
    @Attribute(.unique) var id: UUID
    var topicID: UUID?
    var typeRaw: String
    var prompt: String
    var options: [String]
    var correctAnswer: String
    var explanation: String
    var imageData: Data?
    var sourceBookID: UUID?
    var sourceBookTitle: String
    var sourcePage: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        topicID: UUID? = nil,
        type: AcademyQuestionType,
        prompt: String,
        options: [String] = [],
        correctAnswer: String,
        explanation: String = "",
        imageData: Data? = nil,
        sourceBookID: UUID? = nil,
        sourceBookTitle: String = "",
        sourcePage: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.topicID = topicID
        self.typeRaw = type.rawValue
        self.prompt = prompt
        self.options = options
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.imageData = imageData
        self.sourceBookID = sourceBookID
        self.sourceBookTitle = sourceBookTitle
        self.sourcePage = sourcePage
        self.createdAt = createdAt
    }

    var type: AcademyQuestionType {
        get { AcademyQuestionType(rawValue: typeRaw) ?? .multipleChoice }
        set { typeRaw = newValue.rawValue }
    }
}
