import Foundation

struct DailyPracticePoint: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Int
}

struct CategoryPracticePoint: Identifiable {
    let id = UUID()
    let category: PracticeCategory
    let minutes: Int
}

struct DailyPracticePlan {
    let tasks: [PracticeTask]
    let deferred: [PracticeTask]

    var plannedMinutes: Int {
        tasks.filter { !$0.isCompleted }.reduce(0) { $0 + $1.plannedMinutes }
    }
}

/// Elige una fecha real dentro de los próximos siete días para las acciones que prometen "Agregar a
/// esta semana". Antes esas acciones creaban todo con fecha de hoy; al abrir el Dashboard, el
/// rebalanceo podía enviar la tarea varias semanas hacia adelante y el botón parecía no funcionar.
enum WeeklyTaskScheduler {
    static let windowDays = 7

    static func scheduledDate(
        for plannedMinutes: Int,
        among tasks: [PracticeTask],
        excluding excludedID: UUID? = nil,
        dailyBudgetMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let days = (0..<windowDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
        guard let firstDay = days.first else { return today }

        var usage = Dictionary(uniqueKeysWithValues: days.map { ($0, 0) })
        for task in tasks where !task.isCompleted && task.id != excludedID {
            let scheduledDay = calendar.startOfDay(for: task.scheduledDate)
            // Lo vencido compite por el presupuesto de hoy, igual que en `DailyPracticePlanner`.
            let effectiveDay = scheduledDay < today ? today : scheduledDay
            if usage[effectiveDay] != nil {
                usage[effectiveDay, default: 0] += max(0, task.plannedMinutes)
            }
        }

        let budget = max(5, dailyBudgetMinutes)
        let duration = max(5, plannedMinutes)
        if let fittingDay = days.first(where: { usage[$0, default: 0] + duration <= budget }) {
            return fittingDay
        }

        // Si la semana ya está llena, la decisión explícita del usuario sigue respetándose: se usa
        // el día menos cargado de la ventana, en vez de mandar la tarea fuera de la semana.
        return days.min {
            let lhs = usage[$0, default: 0]
            let rhs = usage[$1, default: 0]
            return lhs == rhs ? $0 < $1 : lhs < rhs
        } ?? firstDay
    }

    static func contains(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? .distantFuture
        return date >= start && date < end
    }
}

/// Convierte el backlog en un plan ejecutable. El presupuesto es estricto salvo las rutinas diarias
/// explícitas, la reserva de una canción y, si una única tarea supera el presupuesto, su inclusión
/// para que el día no quede vacío.
enum DailyPracticePlanner {
    static func makePlan(
        tasks: [PracticeTask],
        budgetMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyPracticePlan {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .distantFuture
        let completedToday = tasks.filter {
            guard $0.isCompleted else { return false }
            let completionDate = $0.completedAt ?? $0.scheduledDate
            return completionDate >= start && completionDate < end
        }
        var due = tasks.filter { !$0.isCompleted && $0.scheduledDate < end }
        due.sort(by: taskOrder)

        var selected: [PracticeTask] = []
        var deferred: [PracticeTask] = []
        var usedMinutes = 0
        let budget = max(5, budgetMinutes)

        // Las rutinas diarias explícitas conservan su duración configurada aunque el resto del día
        // tenga que reprogramarse.
        for task in due where task.isRequiredDailyRoutine {
            selected.append(task)
            usedMinutes += task.plannedMinutes
        }
        due.removeAll(where: \.isRequiredDailyRoutine)

        // Repertorio tiene una reserva diaria propia. La IA semanal también lo pide, pero esta
        // garantía local hace que el resultado no dependa de una respuesta generativa ni de que el
        // recorte por presupuesto justo elimine la canción. Una sola tarea basta para conservar
        // variedad sin llenar el día con todo el repertorio atrasado.
        if !completedToday.contains(where: { $0.category == .repertoire }),
           let repertoireIndex = due.firstIndex(where: { $0.category == .repertoire }) {
            let repertoire = due.remove(at: repertoireIndex)
            selected.append(repertoire)
            usedMinutes += repertoire.plannedMinutes
        }

        // Dentro de cada prioridad se favorece una categoría que aún no apareció hoy. Así el plan
        // sigue respetando urgencia, pero no se llena innecesariamente con cinco tareas equivalentes.
        var remaining = due
        while !remaining.isEmpty {
            let chosenIndex = remaining.indices.min { lhs, rhs in
                let a = remaining[lhs]
                let b = remaining[rhs]
                if a.priority != b.priority { return a.priority < b.priority }
                let aRepeated = selected.contains { $0.category == a.category }
                let bRepeated = selected.contains { $0.category == b.category }
                if aRepeated != bRepeated { return !aRepeated }
                if a.scheduledDate != b.scheduledDate { return a.scheduledDate < b.scheduledDate }
                return a.createdAt < b.createdAt
            } ?? remaining.startIndex
            let task = remaining.remove(at: chosenIndex)
            let fits = usedMinutes + task.plannedMinutes <= budget
            if fits || selected.isEmpty {
                selected.append(task)
                usedMinutes += task.plannedMinutes
            } else {
                deferred.append(task)
            }
        }

        return DailyPracticePlan(
            tasks: (selected + completedToday).sorted(by: taskOrder),
            deferred: deferred.sorted(by: taskOrder)
        )
    }

    /// Asigna el excedente al primer día futuro con capacidad. Considera tareas que ya estaban
    /// programadas para esas fechas para no trasladar la misma sobrecarga de hoy a mañana.
    static func redistributedDates(
        for deferred: [PracticeTask],
        among allTasks: [PracticeTask],
        budgetMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [UUID: Date] {
        guard !deferred.isEmpty else { return [:] }
        let budget = max(5, budgetMinutes)
        let today = calendar.startOfDay(for: now)
        var usage: [Date: Int] = [:]
        let deferredIDs = Set(deferred.map(\.id))

        for task in allTasks where !task.isCompleted && !deferredIDs.contains(task.id) {
            let day = calendar.startOfDay(for: task.scheduledDate)
            guard day > today else { continue }
            usage[day, default: 0] += task.plannedMinutes
        }

        var assignments: [UUID: Date] = [:]
        for task in deferred.sorted(by: taskOrder) {
            for offset in 1...90 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let used = usage[day, default: 0]
                if used == 0 || used + task.plannedMinutes <= budget {
                    assignments[task.id] = day
                    usage[day] = used + task.plannedMinutes
                    break
                }
            }
        }
        return assignments
    }

    private static func taskOrder(_ lhs: PracticeTask, _ rhs: PracticeTask) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        if lhs.scheduledDate != rhs.scheduledDate { return lhs.scheduledDate < rhs.scheduledDate }
        return lhs.createdAt < rhs.createdAt
    }
}

/// Selecciona qué canción debe volver al plan diario cuando ninguna tarea de repertorio está
/// vencida. La rotación es reproducible: primero la menos practicada y, ante empate, la que menos
/// ha avanzado y luego el título. No usa IA porque el historial local es una señal más objetiva.
enum DailyRepertoirePlanner {
    static func isSatisfiedToday(
        tasks: [PracticeTask],
        sessions: [PracticeSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .distantFuture
        if sessions.contains(where: { $0.category == .repertoire && $0.date >= start && $0.date < end }) {
            return true
        }
        return tasks.contains { task in
            guard task.category == .repertoire else { return false }
            if !task.isCompleted { return task.scheduledDate < end }
            let completionDate = task.completedAt ?? task.scheduledDate
            return completionDate >= start && completionDate < end
        }
    }

    static func recommendedSong(
        songs: [Song],
        sessions: [PracticeSession]
    ) -> Song? {
        guard !songs.isEmpty else { return nil }
        var lastPracticed: [UUID: Date] = [:]
        for session in sessions where session.category == .repertoire {
            guard let sourceID = session.sourceID else { continue }
            lastPracticed[sourceID] = max(lastPracticed[sourceID] ?? .distantPast, session.date)
        }

        return songs.sorted { lhs, rhs in
            let lhsDate = lastPracticed[lhs.id] ?? .distantPast
            let rhsDate = lastPracticed[rhs.id] ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            if lhs.status.progressWeight != rhs.status.progressWeight {
                return lhs.status.progressWeight < rhs.status.progressWeight
            }
            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first
    }

    static func plannedMinutes(for song: Song) -> Int {
        guard song.durationSeconds > 0 else { return 10 }
        return max(5, Int(ceil(Double(song.durationSeconds) / 60.0)))
    }
}

enum PracticeAnalytics {
    static func startOfCurrentWeek(calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
    }

    static func sessionsThisWeek(_ sessions: [PracticeSession], calendar: Calendar = .current) -> [PracticeSession] {
        let start = startOfCurrentWeek(calendar: calendar)
        return sessions.filter { $0.date >= start }
    }

    /// Se recalcula filtrando por la fecha de hoy en vez de guardar un total aparte — así el
    /// contador queda en cero automáticamente al cambiar el día, sin ningún reset manual.
    static func sessionsToday(_ sessions: [PracticeSession], calendar: Calendar = .current) -> [PracticeSession] {
        sessions.filter { calendar.isDateInToday($0.date) }
    }

    static func totalMinutesToday(_ sessions: [PracticeSession], calendar: Calendar = .current) -> Int {
        roundedMinutes(sessionsToday(sessions, calendar: calendar))
    }

    static func totalMinutesThisWeek(_ sessions: [PracticeSession]) -> Int {
        roundedMinutes(sessionsThisWeek(sessions))
    }

    static func startOfCurrentMonth(calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: .now)?.start ?? calendar.startOfDay(for: .now)
    }

    static func sessionsThisMonth(_ sessions: [PracticeSession], calendar: Calendar = .current) -> [PracticeSession] {
        let start = startOfCurrentMonth(calendar: calendar)
        return sessions.filter { $0.date >= start }
    }

    static func totalMinutesThisMonth(_ sessions: [PracticeSession]) -> Int {
        roundedMinutes(sessionsThisMonth(sessions))
    }

    static func sessions(in period: SkillPracticePeriod, from sessions: [PracticeSession], calendar: Calendar = .current) -> [PracticeSession] {
        switch period {
        case .day: sessionsToday(sessions, calendar: calendar)
        case .week: sessionsThisWeek(sessions, calendar: calendar)
        case .month: sessionsThisMonth(sessions, calendar: calendar)
        }
    }

    static func practicedDaysThisWeek(_ sessions: [PracticeSession], calendar: Calendar = .current) -> Int {
        let days = sessionsThisWeek(sessions, calendar: calendar).map { calendar.startOfDay(for: $0.date) }
        return Set(days).count
    }

    static func dailyPoints(_ sessions: [PracticeSession], calendar: Calendar = .current) -> [DailyPracticePoint] {
        let start = startOfCurrentWeek(calendar: calendar)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let total = sessions
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
            let roundedTotal = roundedMinutes(total)
            return DailyPracticePoint(date: date, minutes: roundedTotal)
        }
    }

    static func categoryPoints(_ sessions: [PracticeSession]) -> [CategoryPracticePoint] {
        let weekly = sessionsThisWeek(sessions)
        return PracticeCategory.allCases.compactMap { category in
            let minutes = roundedMinutes(weekly.filter { $0.category == category })
            return minutes > 0 ? CategoryPracticePoint(category: category, minutes: minutes) : nil
        }
    }

    private static func roundedMinutes(_ sessions: [PracticeSession]) -> Int {
        let seconds = sessions.reduce(0) { $0 + $1.effectiveDurationSeconds }
        guard seconds > 0 else { return 0 }
        return Int(ceil(Double(seconds) / 60.0))
    }

    static func recommendation(sessions: [PracticeSession], tasks: [PracticeTask]) -> String {
        let categories = categoryPoints(sessions)
        let weakest = PracticeCategory.allCases
            .filter { category in tasks.contains { !$0.isCompleted && $0.category == category } }
            .min { lhs, rhs in
                let lhsMinutes = categories.first(where: { $0.category == lhs })?.minutes ?? 0
                let rhsMinutes = categories.first(where: { $0.category == rhs })?.minutes ?? 0
                return lhsMinutes < rhsMinutes
            }

        guard let weakest else {
            return "Tu plan está al día. Registra una nueva indicación del profesor o selecciona un ejercicio de la biblioteca para continuar."
        }

        let pending = tasks.first { !$0.isCompleted && $0.category == weakest }
        if let pending {
            return "Prioriza \(pending.title.lowercased()) durante \(pending.plannedMinutes) minutos. Mantén un tempo cómodo y aumenta solo cuando puedas repetirlo sin tensión."
        }

        return "La categoría con menor dedicación reciente es \(weakest.rawValue.lowercased()). Incluye un bloque breve y medible en la próxima sesión."
    }
}
