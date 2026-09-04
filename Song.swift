import Foundation
import SwiftData

/// Avance de una sección concreta de la canción (intro, verso, solo...), para poder ir marcando
/// "sacado intro y verso, falta el solo" en vez de un único estado global por canción. `id` es
/// estable frente a reordenamientos/borrados del array — no usar el índice como clave externa
/// (ej. para cachear sugerencias de IA por sección), porque el índice cambia al borrar una sección.
struct SongSectionProgress: Codable {
    var id: UUID = UUID()
    var name: String
    var isLearned: Bool = false
    var weaknessNotes: String = ""
}

@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var sections: String
    var statusRaw: String
    var targetTempo: Int
    /// Duración de la versión que realmente practica el usuario. Se guarda en segundos para no
    /// perder precisión en canciones que no duran un número entero de minutos.
    var durationSeconds: Int = 0
    var notes: String
    var gpFileName: String = ""
    var gpBookmarkData: Data?
    var sectionProgress: [SongSectionProgress] = []
    var band: Band?
    /// Habilidades (`SkillTopic.id`) que esta canción refuerza — sugeridas por IA a partir de
    /// título/artista/secciones y confirmadas por el usuario, nunca inventadas silenciosamente.
    /// Junto con `status`, alimenta la evidencia práctica que ayuda a determinar el nivel real de
    /// cada habilidad (ver `SkillAssessmentCoachService.practiceEvidence`).
    var linkedSkillIDs: [UUID] = []
    /// Clave del catálogo evolutivo que respalda la dificultad. La ficha se copia también en la
    /// canción para que exportaciones, búsquedas y coaches puedan usarla sin tener que consultar otro
    /// modelo SwiftData en cada lectura.
    var difficultyCatalogKey: String = ""
    var difficultyStars: Double?
    var difficultySourceRaw: String = ""
    var difficultyConfidenceRaw: String = ""
    var difficultySummary: String = ""
    var difficultyFactors: [String] = []
    var difficultyDemands: [String] = []
    var difficultyPrerequisites: [String] = []
    var difficultyPracticeFocus: String = ""
    var difficultyTechnique: Double?
    var difficultySpeed: Double?
    var difficultyRhythm: Double?
    var difficultyEndurance: Double?
    var difficultySolo: Double?
    var difficultyForm: Double?
    var difficultyRoleRaw: String = SongGuitarRole.fullArrangement.rawValue
    var difficultyAnalyzedAt: Date?
    var difficultyAnalysisVersion: Int = 0

    init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        sections: String = "",
        status: ExerciseStatus = .notStarted,
        targetTempo: Int = 0,
        durationSeconds: Int = 0,
        notes: String = "",
        gpFileName: String = "",
        gpBookmarkData: Data? = nil,
        sectionProgress: [SongSectionProgress] = [],
        band: Band? = nil,
        linkedSkillIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.sections = sections
        self.statusRaw = status.rawValue
        self.targetTempo = targetTempo
        self.durationSeconds = max(0, durationSeconds)
        self.notes = notes
        self.gpFileName = gpFileName
        self.gpBookmarkData = gpBookmarkData
        self.sectionProgress = sectionProgress
        self.band = band
        self.linkedSkillIDs = linkedSkillIDs
        self.difficultyStars = nil
        self.difficultyTechnique = nil
        self.difficultySpeed = nil
        self.difficultyRhythm = nil
        self.difficultyEndurance = nil
        self.difficultySolo = nil
        self.difficultyForm = nil
        self.difficultyAnalyzedAt = nil
    }

    var status: ExerciseStatus {
        get { ExerciseStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var formattedDuration: String? {
        guard durationSeconds > 0 else { return nil }
        return PracticeDurationFormatter.clockText(seconds: durationSeconds)
    }

    var guitarRole: SongGuitarRole {
        get { SongGuitarRole(rawValue: difficultyRoleRaw) ?? .fullArrangement }
        set { difficultyRoleRaw = newValue.rawValue }
    }

    var persistedDifficultyProfile: SongDifficultyProfile? {
        guard let difficultyStars else { return nil }
        return SongDifficultyProfile(
            title: title,
            artist: artist,
            role: guitarRole,
            rating: DifficultyRating(stars: difficultyStars),
            dimensions: SongDifficultyDimensions(
                technique: difficultyTechnique ?? difficultyStars,
                speed: difficultySpeed ?? difficultyStars,
                rhythm: difficultyRhythm ?? difficultyStars,
                endurance: difficultyEndurance ?? difficultyStars,
                solo: difficultySolo ?? difficultyStars,
                form: difficultyForm ?? difficultyStars
            ),
            source: SongDifficultySource(rawValue: difficultySourceRaw) ?? .legacyHeuristic,
            confidence: SongDifficultyConfidence(rawValue: difficultyConfidenceRaw) ?? .low,
            summary: difficultySummary,
            factors: difficultyFactors,
            demands: difficultyDemands,
            prerequisites: difficultyPrerequisites,
            practiceFocus: difficultyPracticeFocus,
            suggestedSections: sections
                .split(whereSeparator: { [",", ";", "|", "/"].contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            analyzedAt: difficultyAnalyzedAt ?? .distantPast,
            analysisVersion: difficultyAnalysisVersion
        )
    }

    func applyDifficultyProfile(_ profile: SongDifficultyProfile) {
        difficultyCatalogKey = profile.catalogKey
        difficultyStars = profile.rating.stars
        difficultySourceRaw = profile.source.rawValue
        difficultyConfidenceRaw = profile.confidence.rawValue
        difficultySummary = profile.summary
        difficultyFactors = profile.factors
        difficultyDemands = profile.demands
        difficultyPrerequisites = profile.prerequisites
        difficultyPracticeFocus = profile.practiceFocus
        difficultyTechnique = profile.dimensions.technique
        difficultySpeed = profile.dimensions.speed
        difficultyRhythm = profile.dimensions.rhythm
        difficultyEndurance = profile.dimensions.endurance
        difficultySolo = profile.dimensions.solo
        difficultyForm = profile.dimensions.form
        difficultyRoleRaw = profile.role.rawValue
        difficultyAnalyzedAt = profile.analyzedAt
        difficultyAnalysisVersion = profile.analysisVersion
    }
}
