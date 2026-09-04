import Foundation
import SwiftData

@Model
final class PracticeTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var categoryRaw: String
    var plannedMinutes: Int
    var sourceTitle: String
    var exerciseTitle: String
    var targetBPM: Int
    var priority: Int
    var isCompleted: Bool
    var createdAt: Date
    var instructions: String = ""
    var scheduledDate: Date = Date.now
    var sourceKindRaw: String = TaskSourceKind.manual.rawValue
    var sourceID: UUID?
    var completedAt: Date?
    /// Resultado de la evaluación que cerró esta ocurrencia. Estos valores viajan a la próxima
    /// tarea recurrente para que el intervalo dependa de retención demostrada y no de un checkbox.
    var lastResultRaw: String = PracticeResult.learning.rawValue
    var lastEndBPM: Int = 0
    var lastCorrectRepetitions: Int = 0
    var lastTensionRating: Int = 1
    var lastPracticeContextRaw: String = PracticeApplicationContext.isolated.rawValue
    var lastWasColdCheck: Bool = false
    var successfulReviewCount: Int = 0
    var theoryTaskModeRaw: String = TheoryTaskMode.guided.rawValue
    var rhythmTaskModeRaw: String = RhythmTaskMode.guided.rawValue
    var repertoireTaskModeRaw: String = RepertoireTaskMode.guided.rawValue
    var rhythmicFigureRaw: String?
    /// Objetivo verificable opcional. Una tarea común puede no tenerlo; los retos del mapa y las
    /// propuestas confirmadas de Hermes siempre apuntan a una habilidad y una dimensión.
    var targetSkillID: UUID?
    var evidenceDimensionRaw: String?
    var successCriterionRaw: String?
    var isDiagnosticChallengeRaw: Bool?

    init(
        id: UUID = UUID(),
        title: String,
        category: PracticeCategory,
        plannedMinutes: Int,
        sourceTitle: String = "",
        exerciseTitle: String = "",
        targetBPM: Int = 0,
        priority: Int = 2,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        instructions: String = "",
        theoryTaskMode: TheoryTaskMode = .guided,
        rhythmTaskMode: RhythmTaskMode = .guided,
        repertoireTaskMode: RepertoireTaskMode = .guided,
        scheduledDate: Date = .now,
        sourceKind: TaskSourceKind = .manual,
        sourceID: UUID? = nil,
        completedAt: Date? = nil,
        lastResult: PracticeResult = .learning,
        lastEndBPM: Int = 0,
        lastCorrectRepetitions: Int = 0,
        lastTensionRating: Int = 1,
        lastPracticeContext: PracticeApplicationContext = .isolated,
        lastWasColdCheck: Bool = false,
        successfulReviewCount: Int = 0,
        rhythmicFigure: RhythmicFigure = .unspecified,
        targetSkillID: UUID? = nil,
        evidenceDimension: SkillEvidenceDimension? = nil,
        successCriterion: String = "",
        isDiagnosticChallenge: Bool = false
    ) {
        self.id = id
        self.title = title
        self.categoryRaw = category.rawValue
        self.plannedMinutes = plannedMinutes
        self.sourceTitle = sourceTitle
        self.exerciseTitle = exerciseTitle
        self.targetBPM = targetBPM
        self.priority = priority
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.instructions = instructions
        self.theoryTaskModeRaw = theoryTaskMode.rawValue
        self.rhythmTaskModeRaw = rhythmTaskMode.rawValue
        self.repertoireTaskModeRaw = repertoireTaskMode.rawValue
        self.scheduledDate = scheduledDate
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceID = sourceID
        self.completedAt = completedAt
        self.lastResultRaw = lastResult.rawValue
        self.lastEndBPM = lastEndBPM
        self.lastCorrectRepetitions = lastCorrectRepetitions
        self.lastTensionRating = lastTensionRating
        self.lastPracticeContextRaw = lastPracticeContext.rawValue
        self.lastWasColdCheck = lastWasColdCheck
        self.successfulReviewCount = successfulReviewCount
        self.rhythmicFigureRaw = rhythmicFigure.rawValue
        self.targetSkillID = targetSkillID
        self.evidenceDimensionRaw = evidenceDimension?.rawValue
        self.successCriterionRaw = successCriterion
        self.isDiagnosticChallengeRaw = isDiagnosticChallenge
    }

    var category: PracticeCategory {
        get { PracticeCategory(rawValue: categoryRaw) ?? .technique }
        set { categoryRaw = newValue.rawValue }
    }

    var sourceKind: TaskSourceKind {
        get { TaskSourceKind(rawValue: sourceKindRaw) ?? .manual }
        set { sourceKindRaw = newValue.rawValue }
    }

    var theoryTaskMode: TheoryTaskMode {
        get { TheoryTaskMode(rawValue: theoryTaskModeRaw) ?? .guided }
        set { theoryTaskModeRaw = newValue.rawValue }
    }

    var rhythmTaskMode: RhythmTaskMode {
        get { RhythmTaskMode(rawValue: rhythmTaskModeRaw) ?? .guided }
        set { rhythmTaskModeRaw = newValue.rawValue }
    }

    var repertoireTaskMode: RepertoireTaskMode {
        get { RepertoireTaskMode(rawValue: repertoireTaskModeRaw) ?? .guided }
        set { repertoireTaskModeRaw = newValue.rawValue }
    }

    var taskModeLabel: String? {
        switch category {
        case .theory: theoryTaskMode.rawValue
        case .rhythm: rhythmTaskMode.rawValue
        case .repertoire: repertoireTaskMode.rawValue
        default: nil
        }
    }

    var taskModeIcon: String {
        switch category {
        case .theory: theoryTaskMode.icon
        case .rhythm: rhythmTaskMode.icon
        case .repertoire: repertoireTaskMode.icon
        default: "list.bullet.clipboard"
        }
    }

    var lastResult: PracticeResult {
        get { PracticeResult(rawValue: lastResultRaw) ?? .learning }
        set { lastResultRaw = newValue.rawValue }
    }

    var lastPracticeContext: PracticeApplicationContext {
        get { PracticeApplicationContext(rawValue: lastPracticeContextRaw) ?? .isolated }
        set { lastPracticeContextRaw = newValue.rawValue }
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

    var isDiagnosticChallenge: Bool {
        get { isDiagnosticChallengeRaw ?? false }
        set { isDiagnosticChallengeRaw = newValue }
    }

    var isDailyChromaticWarmup: Bool {
        sourceKind == .library && title.localizedCaseInsensitiveContains("cromático")
    }

    var isDailyFretboardTraining: Bool {
        sourceKind == .fretboard
    }

    var isRequiredDailyRoutine: Bool {
        isDailyChromaticWarmup || isDailyFretboardTraining
    }
}
