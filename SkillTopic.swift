import Foundation
import SwiftData

struct AssessmentOption: Codable {
    var text: String
    var points: Int
}

struct AssessmentQuestion: Codable {
    var question: String
    var options: [AssessmentOption]
    var selectedIndex: Int? = nil
}

@Model
final class SkillTopic {
    @Attribute(.unique) var id: UUID
    var name: String
    var detail: String
    var domainRaw: String
    var levelRaw: String
    var statusRaw: String
    var resource: String
    var notes: String
    /// Guía de referencia por técnica, provista por el usuario (no generada por IA).
    var concept: String
    var correctExecution: String
    var commonErrors: String
    var assessmentQuestions: [AssessmentQuestion] = []
    /// Candidatas recién generadas por Gemini o su respaldo local en la sesión actual, todavía sin
    /// aprobar ni descartar — ver `SkillAssessmentQuestionDraftService`/`SkillAssessmentQuestionReviewView`.
    var pendingCandidateQuestions: [AssessmentQuestion] = []
    /// Archivo acumulado de preguntas aprobadas a lo largo de los meses (nunca incluye las de
    /// `assessmentQuestions`). Crece con cada sesión de revisión; `activeRotationQuestions` es una
    /// muestra de esto, no el todo.
    var approvedRotationPool: [AssessmentQuestion] = []
    /// Muestra rotativa de `approvedRotationPool` vigente para el ciclo actual — esto es lo que
    /// realmente se muestra y se responde en el test, junto a `assessmentQuestions` (nunca mezclado
    /// con ese array: las de Teoría están indexadas por posición desde `TheoryFlashcardProgress`, así
    /// que `assessmentQuestions` no se reordena ni se reemplaza jamás).
    var activeRotationQuestions: [AssessmentQuestion] = []
    /// Resultado aislado del Test Integral. `statusRaw` representa desde SchemaV2 el dominio
    /// demostrado por todas las evidencias; mantener ambos evita presentar el test como verdad final.
    var testStatusRaw: String?
    var demonstratedConfidenceRaw: String?
    /// `true` cuando el usuario eligió el estado a mano desde el picker de `SkillTopicDetailView`,
    /// en vez de venir del Test Integral. Mientras esté en `true`, el recálculo automático por
    /// evidencia práctica (canciones/ejercicios dominados, ver `SkillAssessmentCoachService`) NO
    /// pisa ese valor — solo terminar una autoevaluación nueva lo vuelve a poner en `false`, porque
    /// esa es la próxima vez que el usuario da una señal explícita y completa de su nivel real.
    var statusIsManual: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        detail: String = "",
        domain: SkillDomain,
        level: SkillLevel,
        status: SkillMasteryLevel = .notStarted,
        resource: String = "",
        notes: String = "",
        concept: String = "",
        correctExecution: String = "",
        commonErrors: String = "",
        assessmentQuestions: [AssessmentQuestion] = [],
        statusIsManual: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.domainRaw = domain.rawValue
        self.levelRaw = level.rawValue
        self.statusRaw = status.rawValue
        self.resource = resource
        self.notes = notes
        self.concept = concept
        self.correctExecution = correctExecution
        self.commonErrors = commonErrors
        self.assessmentQuestions = assessmentQuestions
        self.statusIsManual = statusIsManual
    }

    var domain: SkillDomain {
        get { SkillDomain(rawValue: domainRaw) ?? .technique }
        set { domainRaw = newValue.rawValue }
    }

    var level: SkillLevel {
        get { SkillLevel(rawValue: levelRaw) ?? .basic }
        set { levelRaw = newValue.rawValue }
    }

    var status: SkillMasteryLevel {
        get { SkillMasteryLevel(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var testStatus: SkillMasteryLevel? {
        get { testStatusRaw.flatMap(SkillMasteryLevel.init(rawValue:)) }
        set { testStatusRaw = newValue?.rawValue }
    }

    var demonstratedConfidence: SkillProfileConfidence {
        get { demonstratedConfidenceRaw.flatMap(SkillProfileConfidence.init(rawValue:)) ?? .low }
        set { demonstratedConfidenceRaw = newValue.rawValue }
    }
}
