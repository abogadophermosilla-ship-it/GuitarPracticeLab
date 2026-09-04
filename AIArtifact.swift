import Foundation
import SwiftData

enum AIArtifactKind: String, CaseIterable, Codable, Identifiable {
    case lessonTranscription = "Transcripción de clase"
    case recordingTranscription = "Transcripción de grabación"
    case performanceAnalysis = "Análisis de interpretación"
    case stems = "Stems"
    case weeklyPlan = "Plan semanal"
    case skillLadder = "Escalera de habilidades"
    case videoResearch = "Videos recomendados"
    case groove = "Groove MIDI"
    case vision = "Análisis visual"
    case routineReview = "Revisión de rutina"

    var id: String { rawValue }
}

/// Resultado durable producido por una herramienta de IA. `sourceID` enlaza de forma liviana con
/// una clase, grabación, pregunta u otro elemento sin crear relaciones SwiftData innecesarias.
@Model
final class AIArtifact {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var body: String
    var sourceID: UUID?
    var sourceName: String
    var filePaths: [String]
    var links: [String] = []
    var metadataJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AIArtifactKind,
        title: String,
        body: String = "",
        sourceID: UUID? = nil,
        sourceName: String = "",
        filePaths: [String] = [],
        links: [String] = [],
        metadataJSON: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.filePaths = filePaths
        self.links = links
        self.metadataJSON = metadataJSON
        self.createdAt = createdAt
    }

    var kind: AIArtifactKind {
        get { AIArtifactKind(rawValue: kindRaw) ?? .vision }
        set { kindRaw = newValue.rawValue }
    }
}

/// Una sugerencia concreta de práctica que el Profesor (chat) propuso dentro de su respuesta —
/// distinta de `WeeklyPracticePlanItem` porque no trae fecha (se asigna recién cuando el usuario
/// decide agregarla a la semana con el botón "Agregar a esta semana").
struct PracticeSuggestion: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var categoryRaw: String
    var minutes: Int
    var instructions: String = ""
    var sourceTitle: String = ""
    var wasAdded: Bool = false
    /// Fecha finalmente confirmada por "Agregar a esta semana". Opcional para seguir leyendo las
    /// conversaciones guardadas antes de que la acción comenzara a programar una fecha explícita.
    var addedScheduledDate: Date? = nil

    var category: PracticeCategory {
        get { PracticeCategory(rawValue: categoryRaw) ?? .technique }
        set { categoryRaw = newValue.rawValue }
    }
}

/// Sobre compatible con los mensajes antiguos, que guardaban solamente el arreglo de sugerencias.
/// Reutilizar este JSON evita cambiar el esquema SwiftData solo para añadir la procedencia.
private struct TeacherChatPayload: Codable {
    var suggestedPractice: [PracticeSuggestion]
    var completionSource: AICompletionSource?
    /// Opcional para decodificar sin migración los mensajes guardados antes de incorporar Internet.
    var webSources: [WebSource]?
    var searchAttributionHTML: String?
}

@Model
final class TeacherChatMessage {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var citations: [String]
    var createdAt: Date
    var suggestedPracticeJSON: String = ""

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        citations: [String] = [],
        createdAt: Date = .now,
        suggestedPractice: [PracticeSuggestion] = [],
        completionSource: AICompletionSource? = nil,
        webSources: [WebSource] = [],
        searchAttributionHTML: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.citations = citations
        self.createdAt = createdAt
        storePayload(
            suggestedPractice: suggestedPractice,
            completionSource: completionSource,
            webSources: webSources,
            searchAttributionHTML: searchAttributionHTML
        )
    }

    var suggestedPractice: [PracticeSuggestion] {
        get {
            if let payload = decodedPayload() { return payload.suggestedPractice }
            guard let data = suggestedPracticeJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([PracticeSuggestion].self, from: data) else {
                return []
            }
            return items
        }
        set {
            storePayload(
                suggestedPractice: newValue,
                completionSource: completionSource,
                webSources: webSources,
                searchAttributionHTML: searchAttributionHTML
            )
        }
    }

    var completionSource: AICompletionSource? {
        get { decodedPayload()?.completionSource }
        set {
            storePayload(
                suggestedPractice: suggestedPractice,
                completionSource: newValue,
                webSources: webSources,
                searchAttributionHTML: searchAttributionHTML
            )
        }
    }

    var webSources: [WebSource] {
        get { decodedPayload()?.webSources ?? [] }
        set {
            storePayload(
                suggestedPractice: suggestedPractice,
                completionSource: completionSource,
                webSources: newValue,
                searchAttributionHTML: searchAttributionHTML
            )
        }
    }

    var searchAttributionHTML: String? {
        get { decodedPayload()?.searchAttributionHTML }
        set {
            storePayload(
                suggestedPractice: suggestedPractice,
                completionSource: completionSource,
                webSources: webSources,
                searchAttributionHTML: newValue
            )
        }
    }

    private func decodedPayload() -> TeacherChatPayload? {
        guard let data = suggestedPracticeJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TeacherChatPayload.self, from: data)
    }

    private func storePayload(
        suggestedPractice: [PracticeSuggestion],
        completionSource: AICompletionSource?,
        webSources: [WebSource],
        searchAttributionHTML: String?
    ) {
        let payload = TeacherChatPayload(
            suggestedPractice: suggestedPractice,
            completionSource: completionSource,
            webSources: webSources,
            searchAttributionHTML: searchAttributionHTML
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            suggestedPracticeJSON = ""
            return
        }
        suggestedPracticeJSON = json
    }
}

struct WeeklyPracticePlanItem: Codable, Identifiable {
    var id: UUID = UUID()
    var scheduledDate: Date
    var title: String
    var categoryRaw: String
    var minutes: Int
    var sourceTitle: String = ""
    var exerciseTitle: String = ""
    var targetBPM: Int = 0
    var instructions: String = ""
    var isSelected: Bool = true
    var wasAddedToTasks: Bool = false
    /// Origen de intención que eligió el planificador (clases, banda, técnica elegida, punto débil
    /// o disfrute). Es opcional para que los planes guardados antes de incorporar el perfil de
    /// enfoque sigan decodificando sin migraciones.
    var planningFocusRaw: String?

    var category: PracticeCategory {
        get { PracticeCategory(rawValue: categoryRaw) ?? .technique }
        set { categoryRaw = newValue.rawValue }
    }

    var planningFocus: PracticePlanFocus? {
        get { planningFocusRaw.flatMap(PracticePlanFocus.init(rawValue:)) }
        set { planningFocusRaw = newValue?.rawValue }
    }
}

@Model
final class WeeklyPracticePlan {
    @Attribute(.unique) var id: UUID
    var weekStart: Date
    var summary: String
    var items: [WeeklyPracticePlanItem]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        weekStart: Date,
        summary: String,
        items: [WeeklyPracticePlanItem],
        createdAt: Date = .now
    ) {
        self.id = id
        self.weekStart = weekStart
        self.summary = summary
        self.items = items
        self.createdAt = createdAt
    }
}

/// Progresión persistente hacia un objetivo concreto del alumno ("aprender Fear of the Dark de Iron
/// Maiden") — antes de esto, `SkillLadderService.generate` solo se archivaba como texto en un
/// `AIArtifact` de solo lectura y nunca creaba una tarea real. `steps` guarda el mismo struct que usa
/// el generador (`SkillLadderStep`, en `AICoachServices.swift`) para no duplicar el modelo, ahora con
/// campos mutables de progreso (`isAchieved`/`achievedAt`) que `SkillLadderProgressService` actualiza.
@Model
final class SkillLadder {
    @Attribute(.unique) var id: UUID
    var goal: String
    var title: String
    var rationale: String
    var steps: [SkillLadderStep]
    var isArchived: Bool = false
    var createdAt: Date

    init(
        id: UUID = UUID(),
        goal: String,
        title: String,
        rationale: String,
        steps: [SkillLadderStep],
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.goal = goal
        self.title = title
        self.rationale = rationale
        self.steps = steps
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    /// El primer escalón sin lograr — el que debería tener una tarea activa en este momento. `nil`
    /// cuando ya se lograron todos (la escalera está completa).
    var currentStep: SkillLadderStep? {
        steps.first { !$0.isAchieved }
    }
}
