import Foundation
import SwiftData

/// Concepto (o ejercicio teórico) de un libro, citable con página real — distinto de
/// `LibraryExercise`, que son ejercicios técnicos. Importado desde el catálogo de teoría compilado
/// por la sesión paralela, ver `LibraryConceptImporter`.
@Model
final class LibraryConcept {
    @Attribute(.unique) var id: UUID
    var bookTitle: String
    var title: String
    var page: Int
    var category: String
    var levelRaw: String?
    var summary: String
    /// `true` para "ejercicio_teorico" (ej. resolver un ejercicio de teoría), `false` para
    /// "concepto" (explicación) — tal como vienen clasificados en el catálogo de origen.
    var isExercise: Bool
    /// Mismo campo y mismo significado que `LibraryExercise.aiSkillIDs` — ver
    /// `LibraryCatalogEnrichmentService`.
    var aiSkillIDs: [UUID] = []
    var aiSkillsEnrichedAt: Date?

    init(
        id: UUID = UUID(),
        bookTitle: String,
        title: String,
        page: Int = 0,
        category: String = "",
        level: SkillLevel? = nil,
        summary: String = "",
        isExercise: Bool = false
    ) {
        self.id = id
        self.bookTitle = bookTitle
        self.title = title
        self.page = page
        self.category = category
        self.levelRaw = level?.rawValue
        self.summary = summary
        self.isExercise = isExercise
    }

    var level: SkillLevel? {
        get { levelRaw.flatMap { SkillLevel(rawValue: $0) } }
        set { levelRaw = newValue?.rawValue }
    }

    /// Etiqueta histórica del catálogo, usada solo como señal débil al recalcular la dificultad.
    var legacyCatalogLevel: String? {
        guard let raw = levelRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let numeric = Double(raw.replacingOccurrences(of: ",", with: "."))
        return numeric == nil ? raw : nil
    }
}
