import Foundation
import SwiftData

@Model
final class LibraryExercise {
    @Attribute(.unique) var id: UUID
    var collectionName: String
    var bookTitle: String
    var chapter: String
    var exerciseNumber: String
    var page: Int
    var technique: String
    var targetBPM: Int
    var statusRaw: String
    var notes: String
    var isFavorite: Bool
    /// Nivel de dificultad del ejercicio en su libro de origen (distinto de `status`, que es el
    /// progreso del alumno) — opcional porque los ejercicios agregados a mano no siempre lo tienen.
    var difficultyRaw: String?
    /// Habilidades vinculadas por `LibraryCatalogEnrichmentService`, señal adicional junto al
    /// matching por texto de `SkillAssessmentCoachService.matchingSkills`. `aiSkillsEnrichedAt` nil
    /// significa "todavía no procesado por el lote", no "sin habilidades relacionadas".
    var aiSkillIDs: [UUID] = []
    var aiSkillsEnrichedAt: Date?

    init(
        id: UUID = UUID(),
        collectionName: String,
        bookTitle: String,
        chapter: String = "",
        exerciseNumber: String = "",
        page: Int = 0,
        technique: String,
        targetBPM: Int = 0,
        status: ExerciseStatus = .notStarted,
        notes: String = "",
        isFavorite: Bool = false,
        difficulty: SkillLevel? = nil
    ) {
        self.id = id
        self.collectionName = collectionName
        self.bookTitle = bookTitle
        self.chapter = chapter
        self.exerciseNumber = exerciseNumber
        self.page = page
        self.technique = technique
        self.targetBPM = targetBPM
        self.statusRaw = status.rawValue
        self.notes = notes
        self.isFavorite = isFavorite
        self.difficultyRaw = difficulty?.rawValue
    }

    var status: ExerciseStatus {
        get { ExerciseStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var difficulty: SkillLevel? {
        get { difficultyRaw.flatMap { SkillLevel(rawValue: $0) } }
        set { difficultyRaw = newValue?.rawValue }
    }

    /// Etiqueta gruesa que venía en el catálogo original. Se conserva únicamente como una señal
    /// secundaria del clasificador de 10 estrellas; nunca se muestra como dificultad al usuario.
    var legacyCatalogDifficulty: String? {
        guard let raw = difficultyRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let numeric = Double(raw.replacingOccurrences(of: ",", with: "."))
        return numeric == nil ? raw : nil
    }

    var displayName: String {
        let parts = [chapter.isEmpty ? nil : "Cap. \(chapter)", exerciseNumber.isEmpty ? nil : "Ej. \(exerciseNumber)"]
            .compactMap { $0 }
        return parts.isEmpty ? technique : "\(parts.joined(separator: " · ")) — \(technique)"
    }
}
