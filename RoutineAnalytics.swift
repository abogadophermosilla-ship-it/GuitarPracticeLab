import Foundation

/// Sesiones y minutos promedio para un día de la semana (`Calendar.component(.weekday)`, 1 = domingo).
struct WeekdayPracticePoint: Identifiable {
    let id = UUID()
    let weekday: Int
    let sessionCount: Int
    let averageMinutes: Int
}

/// Minutos de una categoría en la mitad temprana vs. la mitad reciente de la ventana analizada —
/// para detectar "hace N semanas que esta categoría bajó", no solo su total.
struct CategoryTrendPoint: Identifiable {
    let id = UUID()
    let category: PracticeCategory
    let earlyMinutes: Int
    let recentMinutes: Int
}

/// BPM del primer vs. el último registro de un mismo ejercicio dentro de la ventana, agrupado por
/// `exerciseTitle` — el mismo campo que ya identifica un ejercicio recurrente en `PracticeSession`.
struct ExerciseBPMTrend: Identifiable {
    let id = UUID()
    let exerciseTitle: String
    let firstBPM: Int
    let lastBPM: Int
    let sessionCount: Int
}

struct RoutineSignals {
    let windowWeeks: Int
    let totalSessions: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let weekdayPoints: [WeekdayPracticePoint]
    let categoryTrends: [CategoryTrendPoint]
    let bpmTrends: [ExerciseBPMTrend]
    let levelUpsEarlierHalf: Int
    let levelUpsRecentHalf: Int

    /// Piso mínimo de datos reales antes de que tenga sentido gastar una llamada al modelo —
    /// con menos de esto, cualquier "patrón" detectado sería ruido.
    var hasEnoughData: Bool { totalSessions >= 4 }
}

/// Agregación 100% determinística sobre `PracticeSession`/`ProgressMilestone` — mismo espíritu que
/// `PracticeAnalytics`/`ProgressAnalytics`/`TheoryFlashcardScheduler`: cálculo puro, sin IA,
/// instantáneo. `RoutineCoachService` solo recibe el resultado ya resumido de `promptSummary`, nunca
/// sesiones crudas, para no tener que enviar meses de historial a ningún proveedor.
enum RoutineAnalytics {
    /// Piso de muestra codificado (no solo una instrucción de texto al modelo) antes de considerar
    /// confiable una señal de balance por categoría — mismo mínimo que ya usa
    /// `SkillAssessmentCoachService.combinedStatus` para evidencia práctica, para no dejarle a un
    /// modelo generativo la responsabilidad de autocensurarse con datos insuficientes.
    private static let minSessionsForCategorySignal = 2
    private static let minSessionsForBPMTrend = 2

    static func computeSignals(
        sessions: [PracticeSession],
        milestones: [ProgressMilestone],
        windowWeeks: Int = 10,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> RoutineSignals {
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: now) ?? now
        let windowSessions = sessions.filter { $0.date >= windowStart && $0.date <= now }
        let midpoint = calendar.date(byAdding: .weekOfYear, value: -windowWeeks / 2, to: now) ?? windowStart

        let (currentStreak, longestStreak) = streaks(sessions: sessions, calendar: calendar, now: now)
        let windowMilestones = milestones.filter { $0.date >= windowStart && $0.date <= now }

        return RoutineSignals(
            windowWeeks: windowWeeks,
            totalSessions: windowSessions.count,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            weekdayPoints: computeWeekdayPoints(windowSessions, calendar: calendar),
            categoryTrends: computeCategoryTrends(windowSessions, midpoint: midpoint),
            bpmTrends: computeBPMTrends(windowSessions),
            levelUpsEarlierHalf: windowMilestones.filter { $0.date < midpoint }.count,
            levelUpsRecentHalf: windowMilestones.filter { $0.date >= midpoint }.count
        )
    }

    /// Racha más larga dentro de TODO el historial (no solo la ventana) y racha actual contando
    /// hacia atrás desde hoy — si todavía no hay sesión de hoy, la racha sigue viva hasta que pase
    /// un día entero sin practicar.
    private static func streaks(sessions: [PracticeSession], calendar: Calendar, now: Date) -> (current: Int, longest: Int) {
        let practicedDays = Set(sessions.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !practicedDays.isEmpty else { return (0, 0) }

        var longest = 1
        var run = 1
        for index in 1..<practicedDays.count {
            let dayDiff = calendar.dateComponents([.day], from: practicedDays[index - 1], to: practicedDays[index]).day ?? 0
            run = dayDiff == 1 ? run + 1 : 1
            longest = max(longest, run)
        }

        let today = calendar.startOfDay(for: now)
        var cursor = practicedDays.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var current = 0
        while practicedDays.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        return (current, longest)
    }

    private static func computeWeekdayPoints(_ sessions: [PracticeSession], calendar: Calendar) -> [WeekdayPracticePoint] {
        (1...7).map { weekday in
            let matching = sessions.filter { calendar.component(.weekday, from: $0.date) == weekday }
            let totalMinutes = matching.reduce(0) { $0 + $1.durationMinutes }
            return WeekdayPracticePoint(
                weekday: weekday,
                sessionCount: matching.count,
                averageMinutes: matching.isEmpty ? 0 : totalMinutes / matching.count
            )
        }
    }

    private static func computeCategoryTrends(_ sessions: [PracticeSession], midpoint: Date) -> [CategoryTrendPoint] {
        PracticeCategory.allCases.compactMap { category in
            let categorySessions = sessions.filter { $0.category == category }
            guard categorySessions.count >= minSessionsForCategorySignal else { return nil }
            let early = categorySessions.filter { $0.date < midpoint }.reduce(0) { $0 + $1.durationMinutes }
            let recent = categorySessions.filter { $0.date >= midpoint }.reduce(0) { $0 + $1.durationMinutes }
            return CategoryTrendPoint(category: category, earlyMinutes: early, recentMinutes: recent)
        }
    }

    /// Agrupa por `exerciseTitle` antes de mirar BPM — un BPM sin agrupar no dice nada, porque
    /// mezcla ejercicios distintos con objetivos de tempo distintos.
    private static func computeBPMTrends(_ sessions: [PracticeSession]) -> [ExerciseBPMTrend] {
        let named = sessions.filter { !$0.exerciseTitle.isEmpty && $0.endBPM > 0 }
        let grouped = Dictionary(grouping: named, by: \.exerciseTitle)
        return grouped.compactMap { title, group -> ExerciseBPMTrend? in
            guard group.count >= minSessionsForBPMTrend else { return nil }
            let sorted = group.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            return ExerciseBPMTrend(exerciseTitle: title, firstBPM: first.endBPM, lastBPM: last.endBPM, sessionCount: group.count)
        }
        .sorted { abs($0.lastBPM - $0.firstBPM) > abs($1.lastBPM - $1.firstBPM) }
        .prefix(8)
        .map { $0 }
    }

    /// Serializa las señales ya agregadas a texto para el prompt — nunca sesiones crudas, para que
    /// el tamaño del contexto no dependa de cuántos meses de historial real tenga el usuario.
    static func promptSummary(_ signals: RoutineSignals) -> String {
        let weekdayNames = ["", "Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
        let weekdayLine = signals.weekdayPoints
            .map { "\(weekdayNames[$0.weekday]): \($0.sessionCount) sesión(es), \($0.averageMinutes) min prom." }
            .joined(separator: "; ")

        let categoryLine = signals.categoryTrends.isEmpty
            ? "sin suficientes datos todavía"
            : signals.categoryTrends
                .map { "\($0.category.rawValue) \($0.earlyMinutes)→\($0.recentMinutes) min" }
                .joined(separator: "; ")

        // Categorías que ni siquiera juntaron las 2 sesiones mínimas para aparecer en categoryLine —
        // sin esto el modelo solo ve las categorías que YA se practican y nunca detecta las que
        // faltan por completo (típicamente Repertorio y Teoría, relegadas frente a Técnica).
        let coveredCategories = Set(signals.categoryTrends.map(\.category))
        let missingCategories = PracticeCategory.allCases.filter { !coveredCategories.contains($0) }
        let missingLine = missingCategories.isEmpty
            ? "ninguna, todas tienen datos"
            : missingCategories.map(\.rawValue).joined(separator: ", ")

        let bpmLine = signals.bpmTrends.isEmpty
            ? "sin ejercicios con suficientes sesiones repetidas todavía"
            : signals.bpmTrends
                .map { "\($0.exerciseTitle): \($0.firstBPM)→\($0.lastBPM) BPM (\($0.sessionCount) sesiones)" }
                .joined(separator: "; ")

        return """
        Ventana: últimas \(signals.windowWeeks) semanas (\(signals.totalSessions) sesiones).
        Racha actual: \(signals.currentStreakDays) días seguidos. Racha más larga en la ventana: \(signals.longestStreakDays) días.
        Sesiones por día de la semana: \(weekdayLine).
        Minutos por categoría, mitad temprana vs. reciente de la ventana: \(categoryLine).
        Categorías casi sin práctica registrada en la ventana (menos de 2 sesiones): \(missingLine).
        Tendencia de tempo por ejercicio (BPM inicial → más reciente, con al menos 2 sesiones): \(bpmLine).
        Subidas de nivel: \(signals.levelUpsEarlierHalf) en la primera mitad de la ventana vs. \(signals.levelUpsRecentHalf) en la reciente.
        """
    }
}
