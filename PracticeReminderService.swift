import Foundation
import UserNotifications

/// Cuándo avisar: días de la semana (`Calendar.component(.weekday)`, 1 = domingo) y hora habitual.
struct ReminderSchedule: Equatable {
    var weekdays: [Int]
    var hour: Int
    var minute: Int

    var weekdayNames: [String] {
        let symbols = Calendar.current.weekdaySymbols
        return weekdays.compactMap { index in
            let position = index - 1
            guard symbols.indices.contains(position) else { return nil }
            return symbols[position]
        }
    }

    var readableTime: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// Deduce el horario habitual de práctica a partir del historial real. Cálculo puro y
/// determinístico, sin IA y sin tocar el sistema de notificaciones — igual que `RoutineAnalytics`,
/// para que se pueda probar sin permisos ni entorno gráfico.
enum PracticeReminderPlanner {
    /// Ventana de historial que se mira para deducir el hábito.
    static let windowWeeks = 8
    /// Menos que esto es ruido: no se programa nada.
    static let minimumSessions = 6
    /// Un día cuenta como "día de práctica" si acumula al menos esta fracción de las sesiones del
    /// día más practicado. Evita que un martes suelto de hace dos meses genere un recordatorio.
    static let weekdayThreshold = 0.4

    /// Recibe solo las fechas y no las `PracticeSession` a propósito: los modelos de SwiftData no
    /// son `Sendable`, y esto se llama desde contextos asíncronos.
    static func schedule(
        from sessionDates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ReminderSchedule? {
        guard let windowStart = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: now) else { return nil }
        let recent = sessionDates.filter { $0 >= windowStart && $0 <= now }
        guard recent.count >= minimumSessions else { return nil }

        var countsByWeekday: [Int: Int] = [:]
        for date in recent {
            let weekday = calendar.component(.weekday, from: date)
            countsByWeekday[weekday, default: 0] += 1
        }
        guard let busiest = countsByWeekday.values.max(), busiest > 0 else { return nil }

        let threshold = Double(busiest) * weekdayThreshold
        let weekdays = countsByWeekday
            .filter { Double($0.value) >= threshold }
            .keys
            .sorted()
        guard !weekdays.isEmpty else { return nil }

        // Mediana de la hora de inicio, no promedio: una sesión de madrugada no corre el horario.
        let minutesOfDay = recent
            .filter { weekdays.contains(calendar.component(.weekday, from: $0)) }
            .map { date -> Int in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                return (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
            .sorted()
        guard !minutesOfDay.isEmpty else { return nil }

        let median = minutesOfDay[minutesOfDay.count / 2]
        // Se redondea a la media hora más cercana: "a las 20:00" es un recordatorio, no un cronómetro.
        let rounded = Int((Double(median) / 30.0).rounded()) * 30
        let clamped = min(rounded, 23 * 60 + 30)

        return ReminderSchedule(weekdays: weekdays, hour: clamped / 60, minute: clamped % 60)
    }

    /// `true` si ya hay una sesión registrada hoy — el recordatorio de hoy sobra.
    static func didPractice(on day: Date, sessionDates: [Date], calendar: Calendar = .current) -> Bool {
        sessionDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }
}

/// Programa los recordatorios en el sistema. Se reprograma completo cada vez (borrar + volver a
/// crear) en vez de usar un disparador semanal repetitivo: así se puede saltar el aviso de un día en
/// el que ya practicaste, cosa que un `UNCalendarNotificationTrigger` con `repeats: true` no permite.
enum PracticeReminderService {
    static let enabledKey = "practiceRemindersEnabled"
    /// Cuántos días hacia adelante se dejan programados en cada refresco.
    private static let horizonDays = 14
    private static let identifierPrefix = "practice-reminder-"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    @discardableResult
    static func refresh(
        sessionDates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) async -> ReminderSchedule? {
        cancelAll()
        guard isEnabled else { return nil }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return nil
        }

        guard let schedule = PracticeReminderPlanner.schedule(from: sessionDates, calendar: calendar, now: now) else {
            return nil
        }

        let center = UNUserNotificationCenter.current()
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            guard schedule.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = schedule.hour
            components.minute = schedule.minute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }
            if PracticeReminderPlanner.didPractice(on: day, sessionDates: sessionDates, calendar: calendar) { continue }

            let content = UNMutableNotificationContent()
            content.title = "Hora de practicar"
            content.body = "Es tu horario habitual de guitarra. Aunque sean 15 minutos, la constancia es lo que mueve el nivel."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }

        return schedule
    }
}
