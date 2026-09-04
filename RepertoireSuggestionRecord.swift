import Foundation
import SwiftData

@Model
final class RepertoireSuggestionRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var reason: String
    var targetSkill: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        reason: String = "",
        targetSkill: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.reason = reason
        self.targetSkill = targetSkill
        self.createdAt = createdAt
    }
}

enum RepertoireSuggestionStore {
    /// Reemplaza las sugerencias guardadas por las nuevas, para que siempre reflejen
    /// el estado más reciente de las habilidades del alumno.
    static func replace(_ suggestions: [AssessmentAnalysis.RepertoireSuggestion], in context: ModelContext) {
        if let existing = try? context.fetch(FetchDescriptor<RepertoireSuggestionRecord>()) {
            existing.forEach(context.delete)
        }
        for suggestion in suggestions {
            context.insert(RepertoireSuggestionRecord(
                title: suggestion.title,
                artist: suggestion.artist,
                reason: suggestion.reason,
                targetSkill: suggestion.targetSkill
            ))
        }
    }
}
