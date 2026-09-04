import XCTest
@testable import GuitarPracticeLab

/// Calendario fijo (gregoriano, UTC, semana que empieza el domingo) para que los tests no dependan
/// de la zona horaria ni de la configuración regional de la máquina que los corre.
private var fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 19, _ minute: Int = 0) -> Date {
    fixedCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

final class PracticeReminderPlannerTests: XCTestCase {

    private let now = date(2026, 3, 1, 12, 0)

    func testDevuelveNilConPocasSesiones() {
        let dates = [date(2026, 2, 24), date(2026, 2, 26)]
        XCTAssertNil(PracticeReminderPlanner.schedule(from: dates, calendar: fixedCalendar, now: now))
    }

    func testDetectaLosDiasHabitualesYDescartaLosSueltos() {
        // Seis martes y jueves seguidos, más un domingo aislado que no debería generar aviso.
        var dates: [Date] = []
        for week in 0..<3 {
            dates.append(date(2026, 2, 3 + week * 7, 20, 0))  // martes
            dates.append(date(2026, 2, 5 + week * 7, 20, 0))  // jueves
        }
        dates.append(date(2026, 2, 8, 11, 0))                 // domingo suelto

        let schedule = PracticeReminderPlanner.schedule(from: dates, calendar: fixedCalendar, now: now)

        // 3 = martes y 5 = jueves en `Calendar.weekday` (1 = domingo).
        XCTAssertEqual(schedule?.weekdays, [3, 5])
        XCTAssertEqual(schedule?.hour, 20)
        XCTAssertEqual(schedule?.minute, 0)
    }

    func testIgnoraSesionesFueraDeLaVentana() {
        let viejas = (0..<10).map { date(2025, 6, 1 + $0) }
        XCTAssertNil(PracticeReminderPlanner.schedule(from: viejas, calendar: fixedCalendar, now: now))
    }

    func testUsaLaMedianaYRedondeaAMediaHora() {
        // Una sesión de madrugada no debe correr el horario habitual de la tarde.
        let dates = [
            date(2026, 2, 3, 3, 0),
            date(2026, 2, 10, 18, 40),
            date(2026, 2, 17, 18, 50),
            date(2026, 2, 24, 19, 10),
            date(2026, 2, 4, 18, 45),
            date(2026, 2, 11, 19, 0)
        ]

        let schedule = PracticeReminderPlanner.schedule(from: dates, calendar: fixedCalendar, now: now)

        XCTAssertEqual(schedule?.hour, 19)
        XCTAssertEqual(schedule?.minute, 0)
    }

    func testDidPracticeReconoceElMismoDia() {
        let dates = [date(2026, 2, 24, 8, 0)]
        XCTAssertTrue(PracticeReminderPlanner.didPractice(
            on: date(2026, 2, 24, 23, 0), sessionDates: dates, calendar: fixedCalendar
        ))
        XCTAssertFalse(PracticeReminderPlanner.didPractice(
            on: date(2026, 2, 25, 8, 0), sessionDates: dates, calendar: fixedCalendar
        ))
    }
}
