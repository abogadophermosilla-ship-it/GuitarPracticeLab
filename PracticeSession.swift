import Foundation
import SwiftData

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationMinutes: Int
    /// Tiempo exacto medido o calculado. Las sesiones heredadas quedan en cero y usan
    /// `durationMinutes` como respaldo en `effectiveDurationSeconds`.
    var durationSeconds: Int = 0
    var instrumentName: String
    var categoryRaw: String
    var sourceTitle: String
    var exerciseTitle: String
    var startBPM: Int
    var endBPM: Int
    var difficulty: Int
    var resultRaw: String
    var notes: String
    /// De dónde vino la tarea con la que se inició esta sesión (mismo mecanismo que
    /// `PracticeTask.sourceKind`/`sourceID`) — `.manual` con `sourceID` `nil` para "Sesión libre" o
    /// una sesión cargada a mano desde Sesiones, sin task asociada.
    var sourceKindRaw: String = TaskSourceKind.manual.rawValue
    var sourceID: UUID?
    var correctRepetitions: Int = 0
    /// Cantidad de interpretaciones completas de una canción. No se reutiliza
    /// `correctRepetitions`, porque esa métrica representa una racha técnica limpia, no pasadas.
    var repertoireRepetitions: Int = 0
    /// Instantánea de la duración de la canción al registrar la sesión. Si luego se edita la
    /// versión del repertorio, el historial conserva el cálculo que se usó originalmente.
    var repertoireSongDurationSeconds: Int = 0
    var tensionRating: Int = 1
    /// Opcional en almacenamiento por compatibilidad con una sesión creada durante la migración
    /// anterior; la API pública siempre entrega `.isolated` cuando el valor heredado es nulo.
    var practiceContextRaw: String? = PracticeApplicationContext.isolated.rawValue
    var wasColdCheck: Bool = false
    var rhythmicFigureRaw: String?
    var targetSkillID: UUID?
    var evidenceDimensionRaw: String?
    var successCriterionRaw: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        durationMinutes: Int = 30,
        durationSeconds: Int = 0,
        instrumentName: String = "",
        category: PracticeCategory = .technique,
        sourceTitle: String = "",
        exerciseTitle: String = "",
        startBPM: Int = 0,
        endBPM: Int = 0,
        difficulty: Int = 3,
        result: PracticeResult = .learning,
        notes: String = "",
        sourceKind: TaskSourceKind = .manual,
        sourceID: UUID? = nil,
        correctRepetitions: Int = 0,
        repertoireRepetitions: Int = 0,
        repertoireSongDurationSeconds: Int = 0,
        tensionRating: Int = 1,
        practiceContext: PracticeApplicationContext = .isolated,
        wasColdCheck: Bool = false,
        rhythmicFigure: RhythmicFigure = .unspecified,
        targetSkillID: UUID? = nil,
        evidenceDimension: SkillEvidenceDimension? = nil,
        successCriterion: String = ""
    ) {
        self.id = id
        self.date = date
        self.durationMinutes = durationMinutes
        self.durationSeconds = max(0, durationSeconds)
        self.instrumentName = instrumentName
        self.categoryRaw = category.rawValue
        self.sourceTitle = sourceTitle
        self.exerciseTitle = exerciseTitle
        self.startBPM = startBPM
        self.endBPM = endBPM
        self.difficulty = difficulty
        self.resultRaw = result.rawValue
        self.notes = notes
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceID = sourceID
        self.correctRepetitions = correctRepetitions
        self.repertoireRepetitions = max(0, repertoireRepetitions)
        self.repertoireSongDurationSeconds = max(0, repertoireSongDurationSeconds)
        self.tensionRating = tensionRating
        self.practiceContextRaw = practiceContext.rawValue
        self.wasColdCheck = wasColdCheck
        self.rhythmicFigureRaw = rhythmicFigure.rawValue
        self.targetSkillID = targetSkillID
        self.evidenceDimensionRaw = evidenceDimension?.rawValue
        self.successCriterionRaw = successCriterion
    }

    var category: PracticeCategory {
        get { PracticeCategory(rawValue: categoryRaw) ?? .technique }
        set { categoryRaw = newValue.rawValue }
    }

    var result: PracticeResult {
        get { PracticeResult(rawValue: resultRaw) ?? .learning }
        set { resultRaw = newValue.rawValue }
    }

    var sourceKind: TaskSourceKind {
        get { TaskSourceKind(rawValue: sourceKindRaw) ?? .manual }
        set { sourceKindRaw = newValue.rawValue }
    }

    var practiceContext: PracticeApplicationContext {
        get { practiceContextRaw.flatMap(PracticeApplicationContext.init(rawValue:)) ?? .isolated }
        set { practiceContextRaw = newValue.rawValue }
    }

    var rhythmicFigure: RhythmicFigure {
        get { rhythmicFigureRaw.flatMap(RhythmicFigure.init(rawValue:)) ?? .unspecified }
        set { rhythmicFigureRaw = newValue.rawValue }
    }

    var evidenceDimension: SkillEvidenceDimension? {
        get { evidenceDimensionRaw.flatMap(SkillEvidenceDimension.init(rawValue:)) }
        set { evidenceDimensionRaw = newValue?.rawValue }
    }

    var successCriterion: String {
        get { successCriterionRaw ?? "" }
        set { successCriterionRaw = newValue }
    }

    var effectiveDurationSeconds: Int {
        durationSeconds > 0 ? durationSeconds : max(0, durationMinutes * 60)
    }

    var formattedDuration: String {
        durationSeconds > 0
            ? PracticeDurationFormatter.clockText(seconds: durationSeconds)
            : "\(durationMinutes) min"
    }

    var expectedRepertoireSeconds: Int {
        repertoireSongDurationSeconds * repertoireRepetitions
    }
}

enum PracticeDurationFormatter {
    static func clockText(seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainingSeconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
