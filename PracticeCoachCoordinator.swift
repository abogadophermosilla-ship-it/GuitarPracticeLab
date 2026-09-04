import Foundation
import SwiftData

/// Eventos concretos que pueden invalidar la recomendación canónica. Mantenerlos tipados permite
/// ignorar reevaluaciones repetidas y explicar por qué cambió (o no cambió) el plan.
enum PracticeCoachTrigger: String, Codable, CaseIterable {
    case appLaunch
    case sessionCompleted
    case taskCompleted
    case assessmentCompleted
    case weeklyPlanSaved
    case routineReviewSaved
    case teacherInstructionSaved
    case manualRefresh
}

enum PracticeCoachPriority: String, Codable, Equatable {
    case safety
    case teacherInstruction
    case stagnation
    case progression
    case repertoireRecovery
    case categoryBalance
    case spacedReview
    case scheduledTask
    case maintainPlan

    var title: String {
        switch self {
        case .safety: "Recuperar control y relajación"
        case .teacherInstruction: "Prioridad de la clase"
        case .stagnation: "Romper el estancamiento"
        case .progression: "Consolidar el avance"
        case .repertoireRecovery: "Recuperar repertorio"
        case .categoryBalance: "Compensar un área postergada"
        case .spacedReview: "Revisión reprogramada"
        case .scheduledTask: "Siguiente tarea del plan"
        case .maintainPlan: "Mantener el plan"
        }
    }
}

struct PracticeCoachEvidenceItem: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var detail: String
}

enum PracticeCoachChangeKind: String, Codable, Equatable {
    case none
    case focus
    case targetBPM
    case priority
    case schedule
}

/// Una propuesta puede describir un cambio importante, pero nunca lo ejecuta. El único punto que
/// modifica una tarea es `approveCurrentChange`, llamado desde una confirmación explícita de UI.
struct PracticeCoachChange: Codable, Equatable {
    var kind: PracticeCoachChangeKind
    var summary: String
    var requiresConfirmation: Bool
    var taskID: UUID?
    var proposedTargetBPM: Int?
    var proposedPriority: Int?
    var proposedScheduledDate: Date?

    static let none = PracticeCoachChange(
        kind: .none,
        summary: "La evidencia nueva no exige cambiar el plan.",
        requiresConfirmation: false
    )
}

struct PracticeCoachDecision: Codable, Equatable {
    var snapshotFingerprint: String
    var evaluatedAt: Date
    var trigger: PracticeCoachTrigger
    var priority: PracticeCoachPriority
    var title: String
    var nextAction: String
    var suggestedMinutes: Int
    var targetBPM: Int
    var categoryRaw: String
    var reason: String
    var evidence: [PracticeCoachEvidenceItem]
    var change: PracticeCoachChange
    var taskID: UUID?
    var sourceKindRaw: String
    var sourceID: UUID?
    var sourceTitle: String
    var exerciseTitle: String

    var category: PracticeCategory {
        PracticeCategory(rawValue: categoryRaw) ?? .technique
    }

    var sourceKind: TaskSourceKind {
        TaskSourceKind(rawValue: sourceKindRaw) ?? .manual
    }

    var recommendationForExplanation: PracticeRecommendation {
        PracticeRecommendation(
            focusSkill: priority.title,
            reason: reason,
            exerciseTitle: exerciseTitle.isEmpty ? nextAction : exerciseTitle,
            exerciseSource: sourceTitle,
            suggestedMinutes: suggestedMinutes,
            targetBPM: targetBPM,
            specialInstructions: nextAction
        )
    }
}

struct PracticeCoachSessionSnapshot: Codable, Equatable {
    var id: UUID
    var date: Date
    var durationMinutes: Int
    var categoryRaw: String
    var sourceKindRaw: String
    var sourceID: UUID?
    var sourceTitle: String
    var exerciseTitle: String
    var startBPM: Int
    var endBPM: Int
    var resultRaw: String
    var correctRepetitions: Int
    var tensionRating: Int
    var practiceContextRaw: String
    var wasColdCheck: Bool

    var category: PracticeCategory { PracticeCategory(rawValue: categoryRaw) ?? .technique }

    var isStableSuccess: Bool {
        resultRaw == PracticeResult.targetTempo.rawValue && correctRepetitions >= 3 && tensionRating <= 2
    }

    var comparisonKey: String {
        if let sourceID { return "\(sourceKindRaw)|\(sourceID.uuidString.lowercased())" }
        return "\(categoryRaw)|\(PracticeCoachText.normalized(exerciseTitle))"
    }
}

struct PracticeCoachTaskSnapshot: Codable, Equatable {
    var id: UUID
    var title: String
    var categoryRaw: String
    var plannedMinutes: Int
    var sourceTitle: String
    var exerciseTitle: String
    var targetBPM: Int
    var priority: Int
    var isCompleted: Bool
    var scheduledDate: Date
    var sourceKindRaw: String
    var sourceID: UUID?
    var instructions: String

    var category: PracticeCategory { PracticeCategory(rawValue: categoryRaw) ?? .technique }
}

struct PracticeCoachSongSnapshot: Codable, Equatable {
    var id: UUID
    var title: String
    var artist: String
    var statusRaw: String
    var targetBPM: Int
    var lastPracticedAt: Date?
}

struct PracticeCoachSkillSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var domainRaw: String
    var statusRaw: String
    var progressWeight: Int
}

struct PracticeCoachTeacherInstruction: Codable, Equatable {
    var lessonID: UUID
    var date: Date
    var objective: String
    var topics: String
}

/// Instantánea inmutable y ordenada. Sus arrays no conservan referencias SwiftData, de modo que el
/// mismo estado de entrada produce siempre el mismo fingerprint y la misma decisión.
struct PracticeCoachSnapshot: Codable, Equatable {
    var evaluatedAt: Date
    var dailyBudgetMinutes: Int
    var practicedTodayMinutes: Int
    var plannedTaskIDs: [UUID]
    var sessions: [PracticeCoachSessionSnapshot]
    var tasks: [PracticeCoachTaskSnapshot]
    var songs: [PracticeCoachSongSnapshot]
    var skills: [PracticeCoachSkillSnapshot]
    var latestTeacherInstruction: PracticeCoachTeacherInstruction?

    var remainingBudgetMinutes: Int {
        max(0, dailyBudgetMinutes - practicedTodayMinutes)
    }

    /// `evaluatedAt` se excluye a propósito: abrir dos veces la misma pantalla no constituye nueva
    /// evidencia y no debe reescribir el estado persistente.
    var fingerprint: String {
        let payload = PracticeCoachFingerprintPayload(
            dailyBudgetMinutes: dailyBudgetMinutes,
            practicedTodayMinutes: practicedTodayMinutes,
            plannedTaskIDs: plannedTaskIDs,
            sessions: sessions,
            tasks: tasks,
            songs: songs,
            skills: skills,
            latestTeacherInstruction: latestTeacherInstruction
        )
        return PracticeCoachFingerprint.make(payload)
    }
}

private struct PracticeCoachFingerprintPayload: Codable {
    var dailyBudgetMinutes: Int
    var practicedTodayMinutes: Int
    var plannedTaskIDs: [UUID]
    var sessions: [PracticeCoachSessionSnapshot]
    var tasks: [PracticeCoachTaskSnapshot]
    var songs: [PracticeCoachSongSnapshot]
    var skills: [PracticeCoachSkillSnapshot]
    var latestTeacherInstruction: PracticeCoachTeacherInstruction?
}

@Model
final class PracticeCoachStateRecord {
    @Attribute(.unique) var key: String
    var currentDecisionData: Data
    var previousDecisionData: Data?
    var snapshotFingerprint: String
    var lastTriggerRaw: String
    var updatedAt: Date
    var appliedChangeFingerprint: String

    init(
        key: String = "adaptive-practice-coach-v1",
        currentDecisionData: Data = Data(),
        previousDecisionData: Data? = nil,
        snapshotFingerprint: String = "",
        lastTriggerRaw: String = PracticeCoachTrigger.appLaunch.rawValue,
        updatedAt: Date = .now,
        appliedChangeFingerprint: String = ""
    ) {
        self.key = key
        self.currentDecisionData = currentDecisionData
        self.previousDecisionData = previousDecisionData
        self.snapshotFingerprint = snapshotFingerprint
        self.lastTriggerRaw = lastTriggerRaw
        self.updatedAt = updatedAt
        self.appliedChangeFingerprint = appliedChangeFingerprint
    }

    var currentDecision: PracticeCoachDecision? {
        try? JSONDecoder().decode(PracticeCoachDecision.self, from: currentDecisionData)
    }

    var previousDecision: PracticeCoachDecision? {
        guard let previousDecisionData else { return nil }
        return try? JSONDecoder().decode(PracticeCoachDecision.self, from: previousDecisionData)
    }

    var hasAppliedCurrentChange: Bool {
        guard let decision = currentDecision else { return false }
        return appliedChangeFingerprint == decision.snapshotFingerprint
    }
}

enum PracticeCoachSnapshotBuilder {
    static func build(
        sessions: [PracticeSession],
        tasks: [PracticeTask],
        songs: [Song],
        lessons: [GuitarLesson],
        skills: [SkillTopic],
        dailyBudgetMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PracticeCoachSnapshot {
        let sortedSessions = sessions.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        let sortedTasks = tasks.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.scheduledDate != $1.scheduledDate { return $0.scheduledDate < $1.scheduledDate }
            return $0.id.uuidString < $1.id.uuidString
        }
        let plan = DailyPracticePlanner.makePlan(
            tasks: sortedTasks,
            budgetMinutes: max(5, dailyBudgetMinutes),
            now: now,
            calendar: calendar
        )
        let startOfToday = calendar.startOfDay(for: now)
        let practicedToday = sortedSessions
            .filter { calendar.startOfDay(for: $0.date) == startOfToday }
            .reduce(0) { $0 + max(0, $1.durationMinutes) }

        let sessionValues = sortedSessions.prefix(120).map {
            PracticeCoachSessionSnapshot(
                id: $0.id,
                date: $0.date,
                durationMinutes: $0.durationMinutes,
                categoryRaw: $0.categoryRaw,
                sourceKindRaw: $0.sourceKindRaw,
                sourceID: $0.sourceID,
                sourceTitle: $0.sourceTitle,
                exerciseTitle: $0.exerciseTitle,
                startBPM: $0.startBPM,
                endBPM: $0.endBPM,
                resultRaw: $0.resultRaw,
                correctRepetitions: $0.correctRepetitions,
                tensionRating: $0.tensionRating,
                practiceContextRaw: $0.practiceContextRaw ?? PracticeApplicationContext.isolated.rawValue,
                wasColdCheck: $0.wasColdCheck
            )
        }
        let taskValues = sortedTasks.map {
            PracticeCoachTaskSnapshot(
                id: $0.id,
                title: $0.title,
                categoryRaw: $0.categoryRaw,
                plannedMinutes: $0.plannedMinutes,
                sourceTitle: $0.sourceTitle,
                exerciseTitle: $0.exerciseTitle,
                targetBPM: $0.targetBPM,
                priority: $0.priority,
                isCompleted: $0.isCompleted,
                scheduledDate: $0.scheduledDate,
                sourceKindRaw: $0.sourceKindRaw,
                sourceID: $0.sourceID,
                instructions: $0.instructions
            )
        }
        let songValues = songs.sorted {
            let lhs = "\($0.artist)|\($0.title)|\($0.id.uuidString)"
            let rhs = "\($1.artist)|\($1.title)|\($1.id.uuidString)"
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { song in
            PracticeCoachSongSnapshot(
                id: song.id,
                title: song.title,
                artist: song.artist,
                statusRaw: song.statusRaw,
                targetBPM: song.targetTempo,
                lastPracticedAt: sortedSessions.first { $0.sourceKind == .repertoire && $0.sourceID == song.id }?.date
            )
        }
        let skillValues = skills.sorted {
            if $0.status.progressWeight != $1.status.progressWeight {
                return $0.status.progressWeight < $1.status.progressWeight
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map {
            PracticeCoachSkillSnapshot(
                id: $0.id,
                name: $0.name,
                domainRaw: $0.domain.rawValue,
                statusRaw: $0.status.rawValue,
                progressWeight: $0.status.progressWeight
            )
        }
        let instruction = lessons
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first { !$0.nextObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                PracticeCoachTeacherInstruction(
                    lessonID: $0.id,
                    date: $0.date,
                    objective: $0.nextObjective.trimmingCharacters(in: .whitespacesAndNewlines),
                    topics: $0.topics.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

        return PracticeCoachSnapshot(
            evaluatedAt: now,
            dailyBudgetMinutes: max(5, dailyBudgetMinutes),
            practicedTodayMinutes: practicedToday,
            plannedTaskIDs: plan.tasks.filter { !$0.isCompleted }.map(\.id),
            sessions: sessionValues,
            tasks: taskValues,
            songs: songValues,
            skills: skillValues,
            latestTeacherInstruction: instruction
        )
    }
}

enum PracticeCoachDecisionEngine {
    static let stagnationMinimumSessions = 3

    static func decide(
        snapshot: PracticeCoachSnapshot,
        previous: PracticeCoachDecision? = nil,
        trigger: PracticeCoachTrigger
    ) -> PracticeCoachDecision {
        let fingerprint = snapshot.fingerprint
        let pending = snapshot.tasks.filter { !$0.isCompleted }
        let latestSession = snapshot.sessions.first

        if let tense = recentHighTensionSession(in: snapshot),
           let task = bestMatchingTask(for: tense, among: pending) {
            let safeBPM = tense.endBPM > 0
                ? min(tense.endBPM, task.targetBPM > 0 ? task.targetBPM : tense.endBPM)
                : 0
            let proposal = task.targetBPM > safeBPM && safeBPM > 0
                ? PracticeCoachChange(
                    kind: .targetBPM,
                    summary: "Bajar temporalmente la meta de \(task.targetBPM) a \(safeBPM) BPM.",
                    requiresConfirmation: true,
                    taskID: task.id,
                    proposedTargetBPM: safeBPM
                )
                : .none
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .safety,
                task: task,
                title: "Primero, tocar sin tensión",
                action: snapshot.remainingBudgetMinutes == 0
                    ? "Cierra la práctica de hoy y retoma descansado."
                    : "Reduce el tempo, suelta ambas manos y detente si reaparece la tensión.",
                minutes: min(10, snapshot.remainingBudgetMinutes),
                targetBPM: safeBPM,
                reason: "La última práctica comparable registró tensión \(tense.tensionRating)/5. La seguridad física bloquea cualquier aumento de tempo.",
                evidence: [
                    evidence("tension", "Tensión registrada", "\(tense.tensionRating)/5 en \(displayName(for: tense))"),
                    evidence("tempo", "Tempo observado", tempoDescription(tense))
                ],
                change: proposal
            )
        }

        // Una sesión de otro material no debe hacer saltar la recomendación que sigue pendiente.
        if trigger == .sessionCompleted,
           let previous,
           let latestSession,
           !isRelevant(latestSession, to: previous),
           previous.taskID.flatMap({ id in pending.first { $0.id == id } }) != nil {
            return maintained(previous, snapshot: snapshot, trigger: trigger,
                              reason: "La sesión nueva corresponde a otro material; la prioridad anterior sigue pendiente.")
        }

        if let instruction = activeTeacherInstruction(in: snapshot),
           let task = bestTask(for: instruction, among: pending) {
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .teacherInstruction,
                task: task,
                title: instruction.objective,
                action: task.instructions.isEmpty ? "Trabaja el objetivo indicado en la última clase." : task.instructions,
                minutes: boundedMinutes(task.plannedMinutes, in: snapshot),
                targetBPM: task.targetBPM,
                reason: "Es el próximo objetivo explícito del profesor y todavía no aparece demostrado en una sesión posterior.",
                evidence: [
                    evidence("lesson", "Última indicación", instruction.objective),
                    evidence("lesson-date", "Clase", instruction.date.formatted(date: .abbreviated, time: .omitted))
                ],
                change: focusChange(from: previous, to: task, priority: .teacherInstruction)
            )
        }

        if let stagnant = stagnationCandidate(in: snapshot),
           let task = bestMatchingTask(for: stagnant.latest, among: pending) {
            let priorityChange = task.priority > 0
                ? PracticeCoachChange(
                    kind: .priority,
                    summary: "Subir temporalmente esta tarea a prioridad alta para trabajar el bloqueo.",
                    requiresConfirmation: true,
                    taskID: task.id,
                    proposedPriority: 0
                )
                : .none
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .stagnation,
                task: task,
                title: "Cambia el criterio, no persigas más BPM",
                action: "Aísla el punto de error y exige tres repeticiones limpias antes de volver a subir el tempo.",
                minutes: boundedMinutes(task.plannedMinutes, in: snapshot),
                targetBPM: stagnant.latest.endBPM,
                reason: "Hay \(stagnant.sessions.count) sesiones comparables sin una mejora de tempo suficiente.",
                evidence: [
                    evidence("stagnation-count", "Sesiones comparables", "\(stagnant.sessions.count) dentro de los últimos 28 días"),
                    evidence("stagnation-range", "Rango de tempo", "\(stagnant.minBPM)–\(stagnant.maxBPM) BPM")
                ],
                change: priorityChange
            )
        }

        if let latestSession, latestSession.isStableSuccess,
           let task = bestMatchingTask(for: latestSession, among: pending),
           latestSession.endBPM > 0,
           task.targetBPM <= latestSession.endBPM {
            let proposed = latestSession.endBPM + 5
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .progression,
                task: task,
                title: "Consolida y sube un paso pequeño",
                action: "Repite primero el tempo logrado; solo después prueba el aumento de 5 BPM.",
                minutes: boundedMinutes(task.plannedMinutes, in: snapshot),
                targetBPM: proposed,
                reason: "La sesión más reciente tuvo al menos tres repeticiones correctas, tempo objetivo y tensión baja.",
                evidence: [
                    evidence("success", "Ejecución estable", "\(latestSession.correctRepetitions) repeticiones, tensión \(latestSession.tensionRating)/5"),
                    evidence("achieved-bpm", "Tempo logrado", "\(latestSession.endBPM) BPM")
                ],
                change: PracticeCoachChange(
                    kind: .targetBPM,
                    summary: "Cambiar la meta de \(task.targetBPM) a \(proposed) BPM.",
                    requiresConfirmation: true,
                    taskID: task.id,
                    proposedTargetBPM: proposed
                )
            )
        }

        if let recovery = repertoireRecoveryCandidate(in: snapshot),
           let task = pending.first(where: { $0.sourceKindRaw == TaskSourceKind.repertoire.rawValue && $0.sourceID == recovery.id }) {
            let days = recovery.lastPracticedAt.map {
                Calendar.current.dateComponents([.day], from: $0, to: snapshot.evaluatedAt).day ?? 14
            }
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .repertoireRecovery,
                task: task,
                title: recovery.title,
                action: "Haz una pasada completa y después aísla la sección menos estable.",
                minutes: boundedMinutes(task.plannedMinutes, in: snapshot),
                targetBPM: task.targetBPM > 0 ? task.targetBPM : recovery.targetBPM,
                reason: days.map { "Esta canción lleva \($0) días sin una sesión registrada." }
                    ?? "Esta canción activa aún no tiene práctica registrada.",
                evidence: [evidence("repertoire-gap", "Última práctica", recovery.lastPracticedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Sin registro")],
                change: focusChange(from: previous, to: task, priority: .repertoireRecovery)
            )
        }

        if let task = underpracticedCategoryTask(in: snapshot) {
            let weeklyMinutes = weeklyMinutesByCategory(in: snapshot)[task.categoryRaw, default: 0]
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .categoryBalance,
                task: task,
                title: task.title,
                action: task.instructions.isEmpty ? "Completa un bloque breve y medible de esta área." : task.instructions,
                minutes: boundedMinutes(task.plannedMinutes, in: snapshot),
                targetBPM: task.targetBPM,
                reason: "Esta categoría tiene solo \(weeklyMinutes) minutos esta semana y ya existe una tarea adecuada en el plan.",
                evidence: [evidence("category-minutes", "Carga semanal", "\(task.category.rawValue): \(weeklyMinutes) min")],
                change: focusChange(from: previous, to: task, priority: .categoryBalance)
            )
        }

        if plannedTask(in: snapshot) == nil,
           let nextReview = pending.filter({
               $0.sourceKindRaw == TaskSourceKind.library.rawValue ||
                   $0.sourceKindRaw == TaskSourceKind.repertoire.rawValue
           }).sorted(by: { $0.scheduledDate < $1.scheduledDate }).first,
           nextReview.scheduledDate > Calendar.current.startOfDay(for: snapshot.evaluatedAt) {
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: .spacedReview,
                task: nextReview,
                title: nextReview.title,
                action: "La próxima comprobación queda para \(nextReview.scheduledDate.formatted(date: .abbreviated, time: .omitted)); hoy no hace falta adelantarla.",
                minutes: 0,
                targetBPM: nextReview.targetBPM,
                reason: "El motor de recurrencia ya separó la siguiente revisión para medir retención, sin duplicar tareas.",
                evidence: [
                    evidence("review-date", "Próxima revisión", nextReview.scheduledDate.formatted(date: .abbreviated, time: .omitted)),
                    evidence("recurrence", "Recurrencia", "Una única tarea pendiente para este material")
                ],
                change: .none
            )
        }

        if let task = plannedTask(in: snapshot) ?? pending.first {
            let priority: PracticeCoachPriority = previous?.taskID == task.id ? .maintainPlan : .scheduledTask
            return makeDecision(
                snapshot: snapshot,
                trigger: trigger,
                priority: priority,
                task: task,
                title: task.title,
                action: task.instructions.isEmpty ? "Completa la tarea con un criterio observable y sin dolor." : task.instructions,
                minutes: boundedMinutes(task.plannedMinutes, in: snapshot),
                targetBPM: task.targetBPM,
                reason: priority == .maintainPlan
                    ? "No apareció evidencia suficiente para desplazar la prioridad actual."
                    : "Es la siguiente tarea que cabe en el presupuesto diario y respeta las prioridades existentes.",
                evidence: [
                    evidence("schedule", "Programada", task.scheduledDate.formatted(date: .abbreviated, time: .omitted)),
                    evidence("budget", "Presupuesto restante", "\(snapshot.remainingBudgetMinutes) min")
                ],
                change: focusChange(from: previous, to: task, priority: priority)
            )
        }

        let weakest = snapshot.skills.first
        return PracticeCoachDecision(
            snapshotFingerprint: fingerprint,
            evaluatedAt: snapshot.evaluatedAt,
            trigger: trigger,
            priority: .maintainPlan,
            title: "Plan al día",
            nextAction: weakest.map { "Cuando agregues una tarea, prioriza \($0.name)." }
                ?? "Registra una sesión o crea una tarea concreta para recibir una prioridad adaptativa.",
            suggestedMinutes: 0,
            targetBPM: 0,
            categoryRaw: PracticeCategory.technique.rawValue,
            reason: "No hay tareas pendientes que requieran reorganización.",
            evidence: [evidence("empty-plan", "Estado", "Sin tareas pendientes")],
            change: .none,
            taskID: nil,
            sourceKindRaw: TaskSourceKind.manual.rawValue,
            sourceID: nil,
            sourceTitle: "",
            exerciseTitle: ""
        )
    }

    private struct StagnationCandidate {
        var sessions: [PracticeCoachSessionSnapshot]
        var latest: PracticeCoachSessionSnapshot
        var minBPM: Int
        var maxBPM: Int
    }

    private static func recentHighTensionSession(in snapshot: PracticeCoachSnapshot) -> PracticeCoachSessionSnapshot? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: snapshot.evaluatedAt) ?? .distantPast
        return snapshot.sessions.first { $0.date >= cutoff && $0.tensionRating >= 4 }
    }

    private static func activeTeacherInstruction(in snapshot: PracticeCoachSnapshot) -> PracticeCoachTeacherInstruction? {
        guard let instruction = snapshot.latestTeacherInstruction,
              instruction.date >= (Calendar.current.date(byAdding: .day, value: -21, to: snapshot.evaluatedAt) ?? .distantPast)
        else { return nil }
        let objective = PracticeCoachText.normalized("\(instruction.objective) \(instruction.topics)")
        let demonstratedAfterLesson = snapshot.sessions.contains {
            $0.date > instruction.date && PracticeCoachText.overlaps(
                objective,
                PracticeCoachText.normalized("\($0.exerciseTitle) \($0.sourceTitle)")
            )
        }
        return demonstratedAfterLesson ? nil : instruction
    }

    private static func bestTask(
        for instruction: PracticeCoachTeacherInstruction,
        among tasks: [PracticeCoachTaskSnapshot]
    ) -> PracticeCoachTaskSnapshot? {
        tasks.first { $0.sourceKindRaw == TaskSourceKind.clases.rawValue && $0.sourceID == instruction.lessonID }
            ?? tasks.first {
                PracticeCoachText.overlaps(
                    PracticeCoachText.normalized("\(instruction.objective) \(instruction.topics)"),
                    PracticeCoachText.normalized("\($0.title) \($0.exerciseTitle) \($0.instructions)")
                )
            }
    }

    private static func stagnationCandidate(in snapshot: PracticeCoachSnapshot) -> StagnationCandidate? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: snapshot.evaluatedAt) ?? .distantPast
        let comparable = snapshot.sessions.filter { $0.date >= cutoff && $0.endBPM > 0 && $0.tensionRating < 4 }
        let groups = Dictionary(grouping: comparable, by: \.comparisonKey)
        return groups.values.compactMap { values -> StagnationCandidate? in
            let ordered = values.sorted { $0.date < $1.date }
            guard ordered.count >= stagnationMinimumSessions else { return nil }
            let bpms = ordered.map(\.endBPM)
            guard let minimum = bpms.min(), let maximum = bpms.max(), maximum - minimum <= 2,
                  let first = ordered.first, let latest = ordered.last, latest.endBPM <= first.endBPM + 2
            else { return nil }
            return StagnationCandidate(sessions: ordered, latest: latest, minBPM: minimum, maxBPM: maximum)
        }.sorted { $0.latest.date > $1.latest.date }.first
    }

    private static func repertoireRecoveryCandidate(in snapshot: PracticeCoachSnapshot) -> PracticeCoachSongSnapshot? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: snapshot.evaluatedAt) ?? .distantPast
        let activeStatuses = [
            ExerciseStatus.learning.rawValue,
            ExerciseStatus.consolidating.rawValue,
            ExerciseStatus.reducedTempo.rawValue,
            ExerciseStatus.periodicReview.rawValue
        ]
        return snapshot.songs.filter {
            activeStatuses.contains($0.statusRaw) && ($0.lastPracticedAt == nil || $0.lastPracticedAt! < cutoff)
        }.sorted {
            ($0.lastPracticedAt ?? .distantPast) < ($1.lastPracticedAt ?? .distantPast)
        }.first
    }

    private static func weeklyMinutesByCategory(in snapshot: PracticeCoachSnapshot) -> [String: Int] {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: snapshot.evaluatedAt)?.start ?? .distantPast
        return Dictionary(grouping: snapshot.sessions.filter { $0.date >= start }, by: \.categoryRaw)
            .mapValues { $0.reduce(0) { $0 + max(0, $1.durationMinutes) } }
    }

    private static func underpracticedCategoryTask(in snapshot: PracticeCoachSnapshot) -> PracticeCoachTaskSnapshot? {
        let planned = snapshot.plannedTaskIDs.compactMap { id in
            snapshot.tasks.first { $0.id == id && !$0.isCompleted }
        }
        guard planned.count > 1 else { return nil }
        let minutes = weeklyMinutesByCategory(in: snapshot)
        let maxMinutes = minutes.values.max() ?? 0
        guard maxMinutes >= 20 else { return nil }
        return planned.sorted {
            let lhs = minutes[$0.categoryRaw, default: 0]
            let rhs = minutes[$1.categoryRaw, default: 0]
            if lhs != rhs { return lhs < rhs }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id.uuidString < $1.id.uuidString
        }.first { minutes[$0.categoryRaw, default: 0] <= max(5, maxMinutes / 4) }
    }

    private static func plannedTask(in snapshot: PracticeCoachSnapshot) -> PracticeCoachTaskSnapshot? {
        snapshot.plannedTaskIDs.compactMap { id in snapshot.tasks.first { $0.id == id && !$0.isCompleted } }.first
    }

    private static func bestMatchingTask(
        for session: PracticeCoachSessionSnapshot,
        among tasks: [PracticeCoachTaskSnapshot]
    ) -> PracticeCoachTaskSnapshot? {
        if let sourceID = session.sourceID,
           let exact = tasks.first(where: { $0.sourceID == sourceID && $0.sourceKindRaw == session.sourceKindRaw }) {
            return exact
        }
        let sessionText = PracticeCoachText.normalized("\(session.exerciseTitle) \(session.sourceTitle)")
        return tasks.first {
            PracticeCoachText.overlaps(
                sessionText,
                PracticeCoachText.normalized("\($0.title) \($0.exerciseTitle) \($0.sourceTitle)")
            )
        }
    }

    private static func isRelevant(_ session: PracticeCoachSessionSnapshot, to decision: PracticeCoachDecision) -> Bool {
        if let sourceID = session.sourceID, sourceID == decision.sourceID { return true }
        return PracticeCoachText.overlaps(
            PracticeCoachText.normalized("\(session.exerciseTitle) \(session.sourceTitle)"),
            PracticeCoachText.normalized("\(decision.exerciseTitle) \(decision.sourceTitle) \(decision.title)")
        )
    }

    private static func boundedMinutes(_ requested: Int, in snapshot: PracticeCoachSnapshot) -> Int {
        min(max(5, requested), snapshot.remainingBudgetMinutes)
    }

    private static func focusChange(
        from previous: PracticeCoachDecision?,
        to task: PracticeCoachTaskSnapshot,
        priority: PracticeCoachPriority
    ) -> PracticeCoachChange {
        guard let previous, previous.taskID != task.id else { return .none }
        return PracticeCoachChange(
            kind: .focus,
            summary: "La prioridad pasa de «\(previous.title)» a «\(priority.title)» por la evidencia disponible.",
            requiresConfirmation: false
        )
    }

    private static func maintained(
        _ previous: PracticeCoachDecision,
        snapshot: PracticeCoachSnapshot,
        trigger: PracticeCoachTrigger,
        reason: String
    ) -> PracticeCoachDecision {
        var result = previous
        result.snapshotFingerprint = snapshot.fingerprint
        result.evaluatedAt = snapshot.evaluatedAt
        result.trigger = trigger
        result.priority = .maintainPlan
        result.reason = reason
        result.change = .none
        return result
    }

    private static func makeDecision(
        snapshot: PracticeCoachSnapshot,
        trigger: PracticeCoachTrigger,
        priority: PracticeCoachPriority,
        task: PracticeCoachTaskSnapshot,
        title: String,
        action: String,
        minutes: Int,
        targetBPM: Int,
        reason: String,
        evidence: [PracticeCoachEvidenceItem],
        change: PracticeCoachChange
    ) -> PracticeCoachDecision {
        PracticeCoachDecision(
            snapshotFingerprint: snapshot.fingerprint,
            evaluatedAt: snapshot.evaluatedAt,
            trigger: trigger,
            priority: priority,
            title: title,
            nextAction: action,
            suggestedMinutes: max(0, minutes),
            targetBPM: max(0, targetBPM),
            categoryRaw: task.categoryRaw,
            reason: reason,
            evidence: Array(evidence.prefix(3)),
            change: change,
            taskID: task.id,
            sourceKindRaw: task.sourceKindRaw,
            sourceID: task.sourceID,
            sourceTitle: task.sourceTitle,
            exerciseTitle: task.exerciseTitle.isEmpty ? task.title : task.exerciseTitle
        )
    }

    private static func evidence(_ id: String, _ label: String, _ detail: String) -> PracticeCoachEvidenceItem {
        PracticeCoachEvidenceItem(id: id, label: label, detail: detail)
    }

    private static func displayName(for session: PracticeCoachSessionSnapshot) -> String {
        session.exerciseTitle.isEmpty ? session.category.rawValue : session.exerciseTitle
    }

    private static func tempoDescription(_ session: PracticeCoachSessionSnapshot) -> String {
        guard session.startBPM > 0 || session.endBPM > 0 else { return "Sin BPM registrado" }
        return "\(session.startBPM)→\(session.endBPM) BPM"
    }
}

@MainActor
enum PracticeCoachCoordinator {
    @discardableResult
    static func reevaluate(
        trigger: PracticeCoachTrigger,
        in context: ModelContext,
        dailyBudgetMinutes: Int = UserDefaults.standard.integer(forKey: "dailyPracticeGoalMinutes"),
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> PracticeCoachDecision {
        let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
        let tasks = try context.fetch(FetchDescriptor<PracticeTask>())
        let songs = try context.fetch(FetchDescriptor<Song>())
        let lessons = try context.fetch(FetchDescriptor<GuitarLesson>())
        let skills = try context.fetch(FetchDescriptor<SkillTopic>())
        let snapshot = PracticeCoachSnapshotBuilder.build(
            sessions: sessions,
            tasks: tasks,
            songs: songs,
            lessons: lessons,
            skills: skills,
            dailyBudgetMinutes: dailyBudgetMinutes > 0 ? dailyBudgetMinutes : 45,
            now: now,
            calendar: calendar
        )
        let state = try stateRecord(in: context)
        if state.snapshotFingerprint == snapshot.fingerprint, let current = state.currentDecision {
            return current
        }

        let previous = state.currentDecision
        let decision = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot,
            previous: previous,
            trigger: trigger
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let previous { state.previousDecisionData = try encoder.encode(previous) }
        state.currentDecisionData = try encoder.encode(decision)
        state.snapshotFingerprint = snapshot.fingerprint
        state.lastTriggerRaw = trigger.rawValue
        state.updatedAt = now
        state.appliedChangeFingerprint = ""
        try context.save()
        return decision
    }

    static func currentDecision(in context: ModelContext) -> PracticeCoachDecision? {
        (try? existingStateRecord(in: context))?.currentDecision
    }

    /// Aplica solo el delta expresamente confirmado; no crea tareas ni altera recurrencias.
    @discardableResult
    static func approveCurrentChange(in context: ModelContext) throws -> PracticeTask? {
        guard let state = try existingStateRecord(in: context),
              let decision = state.currentDecision,
              decision.change.requiresConfirmation,
              let taskID = decision.change.taskID
        else { return nil }
        var descriptor = FetchDescriptor<PracticeTask>(predicate: #Predicate { $0.id == taskID })
        descriptor.fetchLimit = 1
        guard let task = try context.fetch(descriptor).first else { return nil }
        if let targetBPM = decision.change.proposedTargetBPM { task.targetBPM = max(0, targetBPM) }
        if let priority = decision.change.proposedPriority { task.priority = min(2, max(0, priority)) }
        if let date = decision.change.proposedScheduledDate { task.scheduledDate = date }
        state.appliedChangeFingerprint = decision.snapshotFingerprint
        try context.save()
        return task
    }

    private static func stateRecord(in context: ModelContext) throws -> PracticeCoachStateRecord {
        if let existing = try existingStateRecord(in: context) { return existing }
        let state = PracticeCoachStateRecord()
        context.insert(state)
        return state
    }

    private static func existingStateRecord(in context: ModelContext) throws -> PracticeCoachStateRecord? {
        var descriptor = FetchDescriptor<PracticeCoachStateRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

private enum PracticeCoachFingerprint {
    static func make<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private enum PracticeCoachText {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \Character.isWhitespace)
            .filter { $0.count >= 3 }
            .joined(separator: " ")
    }

    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        let left = Set(lhs.split(separator: " ").map(String.init))
        let right = Set(rhs.split(separator: " ").map(String.init))
        return !left.intersection(right).isEmpty
    }
}
