import Foundation
import SwiftData

/// Presupuesto de las dos rutinas fijas del plan diario. Mantenerlo en un solo lugar evita que la
/// tarjeta de Hoy, las instrucciones y el entrenador del mástil terminen mostrando tiempos distintos.
enum DailyPracticeRoutine {
    static let chromaticMinutes = 6
    static let fretboardMinutes = 7
}

/// Rotación de combinaciones de dedos del calentamiento cromático diario (`SeedService`): la
/// combinación cambia cada día y después de recorrer la lista vuelve a comenzar. Función pura sobre `Date`, mismo patrón que
/// `RecurringPracticeScheduler`, para poder testear qué variación corresponde a una fecha sin
/// depender de `Calendar.current`.
enum ChromaticWarmupRotation {
    /// Identifica al `LibraryExercise` del calentamiento diario — `RecurringPracticeService` lo usa
    /// para saber cuándo debe recalcular la variación en vez de clonar el texto de la tarea anterior.
    static let techniqueMarker = "Cromático — calentamiento diario"
    static let daysPerVariation = 1

    struct Variation: Equatable {
        let title: String
        let instructions: String
    }

    /// Las 24 permutaciones posibles se agrupan con su inversa. Así quedan 12 ejercicios distintos
    /// sin repetir más adelante el mismo par en orden contrario (por ejemplo, 1234/4321 y
    /// 4321/1234 serían exactamente la misma variación).
    private static let fingerPatterns = [
        [1, 2, 3, 4], [1, 2, 4, 3], [1, 3, 2, 4], [1, 3, 4, 2], [1, 4, 2, 3], [1, 4, 3, 2],
        [2, 1, 3, 4], [2, 1, 4, 3], [2, 3, 1, 4], [2, 4, 1, 3], [3, 1, 2, 4], [3, 2, 1, 4]
    ]

    private static func makeVariation(pattern: [Int]) -> Variation {
        let ascending = pattern.map(String.init).joined(separator: "-")
        let descending = pattern.reversed().map(String.init).joined(separator: "-")
        return Variation(
            title: "Cromático \(ascending) / \(descending)",
            instructions: "Un dedo por traste: índice 1, medio 2, anular 3 y meñique 4. Toca \(ascending) al avanzar y \(descending) al regresar en cada cuerda. Elige la figura rítmica según el tempo y el objetivo de hoy. Practica los \(DailyPracticeRoutine.chromaticMinutes) minutos completos a un tempo cómodo, con sonido uniforme y sin acumular tensión; el objetivo es activar las manos, no perseguir velocidad."
        )
    }

    /// Fecha fija de referencia para calcular en qué período de `daysPerVariation` días cae una
    /// fecha dada — arbitraria, solo necesita ser estable en el tiempo para que la rotación no
    /// salte al cambiar de dispositivo o reinstalar.
    private static let anchor: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }()

    static func variation(for date: Date, calendar: Calendar = .current) -> Variation {
        let startOfDay = calendar.startOfDay(for: date)
        let startOfAnchor = calendar.startOfDay(for: anchor)
        let days = calendar.dateComponents([.day], from: startOfAnchor, to: startOfDay).day ?? 0
        let period = Int(floor(Double(days) / Double(daysPerVariation)))
        let fingerIndex = ((period % fingerPatterns.count) + fingerPatterns.count) % fingerPatterns.count
        return makeVariation(pattern: fingerPatterns[fingerIndex])
    }
}

/// Decide cuándo debe volver a agendarse una `PracticeTask` con origen (Biblioteca/Repertorio)
/// después de completarse, según el `ExerciseStatus` del ítem vinculado: todos los días mientras
/// esté en progreso, cada `periodicReviewIntervalDays` una vez que pasó por Dominado. Función pura
/// e inyectable (mismo patrón que `PracticeReminderPlanner`) para poder testear la fecha sin
/// depender de `Calendar.current`.
enum RecurringPracticeScheduler {
    static let periodicReviewIntervalDays = 15

    enum Recurrence: Equatable {
        case nextTask(scheduledDate: Date)
        case stop
    }

    static func nextOccurrence(
        for status: ExerciseStatus,
        completedAt: Date,
        calendar: Calendar = .current
    ) -> Recurrence {
        switch status {
        case .notStarted, .mastered:
            return .stop
        case .learning, .consolidating, .reducedTempo:
            guard let next = calendar.date(byAdding: .day, value: 1, to: completedAt) else { return .stop }
            return .nextTask(scheduledDate: next)
        case .periodicReview:
            guard let next = calendar.date(byAdding: .day, value: periodicReviewIntervalDays, to: completedAt) else { return .stop }
            return .nextTask(scheduledDate: next)
        }
    }

    /// Variante adaptativa: una ejecución lograda durante la sesión todavía no demuestra retención.
    /// Por eso primero vuelve en tres días y solo amplía el intervalo cuando el alumno la supera "en
    /// frío", con repeticiones limpias y sin tensión relevante.
    static func nextOccurrence(
        for status: ExerciseStatus,
        outcome: PracticeOutcome,
        successfulReviews: Int,
        completedAt: Date,
        calendar: Calendar = .current
    ) -> Recurrence {
        guard status != .notStarted, status != .mastered else { return .stop }

        let days: Int
        switch outcome.result {
        case .started, .learning, .review:
            days = 1
        case .reducedTempo:
            days = outcome.tensionRating >= 4 ? 1 : 2
        case .targetTempo:
            guard outcome.isStableSuccess else {
                days = 1
                break
            }
            if !outcome.wasColdCheck {
                days = 3
            } else {
                let adaptiveDays: Int
                switch successfulReviews {
                case 0...1: adaptiveDays = 5
                case 2: adaptiveDays = 7
                case 3: adaptiveDays = 15
                default: adaptiveDays = 30
                }
                days = status == .periodicReview ? max(periodicReviewIntervalDays, adaptiveDays) : adaptiveDays
            }
        }

        guard let next = calendar.date(byAdding: .day, value: days, to: completedAt) else { return .stop }
        return .nextTask(scheduledDate: next)
    }
}

/// Evaluación breve que acompaña al cierre de una tarea. Es un value type para que el planificador
/// adaptativo se pueda probar sin SwiftData y para usar exactamente la misma regla desde el timer,
/// el formulario de sesión y el checkbox.
struct PracticeOutcome: Equatable {
    var result: PracticeResult
    var endBPM: Int
    var correctRepetitions: Int
    var tensionRating: Int
    var context: PracticeApplicationContext
    var wasColdCheck: Bool

    static let learning = PracticeOutcome(
        result: .learning,
        endBPM: 0,
        correctRepetitions: 0,
        tensionRating: 1,
        context: .isolated,
        wasColdCheck: false
    )

    var isStableSuccess: Bool {
        result == .targetTempo && correctRepetitions >= 3 && tensionRating <= 2
    }
}

/// Resuelve el ejercicio/canción de origen de una `PracticeTask` completada y crea la próxima
/// ocurrencia según `RecurringPracticeScheduler`, si corresponde. No duplica si ya existe una
/// tarea pendiente para el mismo origen.
enum RecurringPracticeService {
    @discardableResult
    static func scheduleNextIfNeeded(
        after task: PracticeTask,
        completedAt: Date,
        outcome: PracticeOutcome? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> PracticeTask? {
        let hasMaterialSource = task.sourceKind == .library || task.sourceKind == .repertoire
        guard hasMaterialSource || task.isDailyFretboardTraining || (task.isDiagnosticChallenge && task.targetSkillID != nil) else { return nil }

        let status: ExerciseStatus
        var libraryExercise: LibraryExercise?
        switch task.sourceKind {
        case .fretboard:
            status = .learning
        case .library:
            guard let sourceID = task.sourceID else { return nil }
            guard let exercise = LibraryLookup.exercise(id: sourceID, in: context) else { return nil }
            status = exercise.status
            libraryExercise = exercise
        case .repertoire:
            guard let sourceID = task.sourceID else { return nil }
            guard let song = resolveSong(id: sourceID, in: context) else { return nil }
            status = song.status
        default:
            status = .learning
        }

        let recurrence: RecurringPracticeScheduler.Recurrence
        if libraryExercise?.technique == ChromaticWarmupRotation.techniqueMarker || task.isDailyFretboardTraining {
            // Es una rutina diaria explícita: conserva su duración configurada y vuelve al
            // día siguiente. La evaluación cambia el feedback, no la frecuencia de este calentamiento.
            recurrence = RecurringPracticeScheduler.nextOccurrence(
                for: .learning, completedAt: completedAt, calendar: calendar
            )
        } else if let outcome {
            recurrence = RecurringPracticeScheduler.nextOccurrence(
                for: status,
                outcome: outcome,
                successfulReviews: task.successfulReviewCount,
                completedAt: completedAt,
                calendar: calendar
            )
        } else {
            recurrence = RecurringPracticeScheduler.nextOccurrence(
                for: status, completedAt: completedAt, calendar: calendar
            )
        }
        guard case .nextTask(let scheduledDate) = recurrence else { return nil }

        let pending = (try? context.fetch(FetchDescriptor<PracticeTask>(
            predicate: #Predicate { !$0.isCompleted }
        ))) ?? []
        if pending.contains(where: {
            if task.isDailyFretboardTraining {
                return $0.isDailyFretboardTraining
            }
            if task.isDiagnosticChallenge {
                return $0.isDiagnosticChallenge && $0.targetSkillID == task.targetSkillID
            }
            return $0.sourceID == task.sourceID && $0.sourceKindRaw == task.sourceKindRaw
        }) {
            return nil
        }

        // El calentamiento cromático no clona el título/instrucciones de la tarea anterior como el
        // resto de las tareas recurrentes: cambia de combinación cada `daysPerVariation` días, así
        // que la próxima ocurrencia recalcula la variación según la fecha en la que quedará agendada.
        let chromaticVariation = libraryExercise?.technique == ChromaticWarmupRotation.techniqueMarker
            ? ChromaticWarmupRotation.variation(for: scheduledDate, calendar: calendar)
            : nil

        let becomesColdReview = task.isDiagnosticChallenge && outcome?.isStableSuccess == true && outcome?.wasColdCheck == false
        let nextDimension: SkillEvidenceDimension? = becomesColdReview ? .retention : task.evidenceDimension
        let nextCriterion = becomesColdReview
            ? SkillChallengeBuilder.criterion(for: .retention, targetBPM: task.targetBPM)
            : task.successCriterion
        let nextInstructions = becomesColdReview
            ? "Objetivo: \(SkillEvidenceDimension.retention.rawValue). \(nextCriterion) Registra resultado, repeticiones, tensión y contexto al terminar."
            : (chromaticVariation?.instructions ?? task.instructions)
        let next = PracticeTask(
            title: becomesColdReview ? "Revisión en frío · \(task.title.replacingOccurrences(of: "Comprobar · ", with: ""))" : (chromaticVariation?.title ?? task.title),
            category: task.category,
            plannedMinutes: task.plannedMinutes,
            sourceTitle: task.sourceTitle,
            exerciseTitle: chromaticVariation?.title ?? task.exerciseTitle,
            targetBPM: task.targetBPM,
            priority: task.priority,
            instructions: nextInstructions,
            theoryTaskMode: task.theoryTaskMode,
            rhythmTaskMode: task.rhythmTaskMode,
            repertoireTaskMode: task.repertoireTaskMode,
            scheduledDate: scheduledDate,
            sourceKind: task.sourceKind,
            sourceID: task.sourceID,
            lastResult: task.lastResult,
            lastEndBPM: task.lastEndBPM,
            lastCorrectRepetitions: task.lastCorrectRepetitions,
            lastTensionRating: task.lastTensionRating,
            lastPracticeContext: task.lastPracticeContext,
            lastWasColdCheck: task.lastWasColdCheck,
            successfulReviewCount: task.successfulReviewCount,
            // La digitación cromática del nuevo día vuelve sin figura impuesta; las demás tareas
            // recurrentes conservan la figura que el usuario eligió manualmente.
            rhythmicFigure: chromaticVariation == nil ? task.rhythmicFigure : .unspecified,
            targetSkillID: task.targetSkillID,
            evidenceDimension: nextDimension,
            successCriterion: nextCriterion,
            isDiagnosticChallenge: task.isDiagnosticChallenge
        )
        context.insert(next)
        return next
    }

    /// Marca la tarea como completada y encadena `scheduleNextIfNeeded` — el punto único que usan
    /// el checkbox del Dashboard, el cronómetro y "Iniciar tarea" para no repetir esta secuencia
    /// en los tres lugares y arriesgar que se desincronicen.
    @discardableResult
    static func completeTask(
        _ task: PracticeTask,
        completedAt: Date = .now,
        outcome: PracticeOutcome = .learning,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> PracticeTask? {
        task.isCompleted = true
        task.completedAt = completedAt
        task.lastResult = outcome.result
        task.lastEndBPM = outcome.endBPM
        task.lastCorrectRepetitions = outcome.correctRepetitions
        task.lastTensionRating = outcome.tensionRating
        task.lastPracticeContext = outcome.context
        task.lastWasColdCheck = outcome.wasColdCheck
        task.successfulReviewCount = outcome.isStableSuccess && outcome.wasColdCheck
            ? task.successfulReviewCount + 1
            : (outcome.isStableSuccess ? task.successfulReviewCount : 0)
        return scheduleNextIfNeeded(
            after: task,
            completedAt: completedAt,
            outcome: outcome,
            in: context,
            calendar: calendar
        )
    }

    private static func resolveSong(id: UUID, in context: ModelContext) -> Song? {
        var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
