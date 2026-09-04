import XCTest
@testable import GuitarPracticeLab

/// Mismo calendario fijo que `PracticeReminderPlannerTests`, para no depender de la zona horaria
/// ni de la configuración regional de la máquina que corre los tests.
private var fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 19, _ minute: Int = 0) -> Date {
    fixedCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

final class RecurringPracticeSchedulerTests: XCTestCase {

    private let completedAt = date(2026, 3, 1, 12, 0)

    func testNoRecurrenceSiNoIniciado() {
        XCTAssertEqual(
            RecurringPracticeScheduler.nextOccurrence(for: .notStarted, completedAt: completedAt, calendar: fixedCalendar),
            .stop
        )
    }

    func testNoRecurrenceSiDominado() {
        XCTAssertEqual(
            RecurringPracticeScheduler.nextOccurrence(for: .mastered, completedAt: completedAt, calendar: fixedCalendar),
            .stop
        )
    }

    func testRecurrenciaDiariaMientrasEnProgreso() {
        let tomorrow = date(2026, 3, 2, 12, 0)
        for status: ExerciseStatus in [.learning, .consolidating, .reducedTempo] {
            XCTAssertEqual(
                RecurringPracticeScheduler.nextOccurrence(for: status, completedAt: completedAt, calendar: fixedCalendar),
                .nextTask(scheduledDate: tomorrow)
            )
        }
    }

    func testRecurrenciaCada15DiasEnRevisionPeriodica() {
        let in15Days = date(2026, 3, 16, 12, 0)
        XCTAssertEqual(
            RecurringPracticeScheduler.nextOccurrence(for: .periodicReview, completedAt: completedAt, calendar: fixedCalendar),
            .nextTask(scheduledDate: in15Days)
        )
    }

    func testLogroDuranteLaSesionSeCompruebaEnTresDias() {
        let outcome = PracticeOutcome(
            result: .targetTempo,
            endBPM: 100,
            correctRepetitions: 3,
            tensionRating: 1,
            context: .fullPiece,
            wasColdCheck: false
        )

        XCTAssertEqual(
            RecurringPracticeScheduler.nextOccurrence(
                for: .learning,
                outcome: outcome,
                successfulReviews: 0,
                completedAt: completedAt,
                calendar: fixedCalendar
            ),
            .nextTask(scheduledDate: date(2026, 3, 4, 12, 0))
        )
    }

    func testRevisionesEnFrioAmplianElIntervalo() {
        let outcome = PracticeOutcome(
            result: .targetTempo,
            endBPM: 100,
            correctRepetitions: 4,
            tensionRating: 2,
            context: .fullPiece,
            wasColdCheck: true
        )

        XCTAssertEqual(
            RecurringPracticeScheduler.nextOccurrence(
                for: .consolidating,
                outcome: outcome,
                successfulReviews: 3,
                completedAt: completedAt,
                calendar: fixedCalendar
            ),
            .nextTask(scheduledDate: date(2026, 3, 16, 12, 0))
        )
    }

    func testTensionAltaImpideAmpliarLaRevision() {
        let outcome = PracticeOutcome(
            result: .targetTempo,
            endBPM: 100,
            correctRepetitions: 5,
            tensionRating: 4,
            context: .metronome,
            wasColdCheck: true
        )

        XCTAssertEqual(
            RecurringPracticeScheduler.nextOccurrence(
                for: .learning,
                outcome: outcome,
                successfulReviews: 4,
                completedAt: completedAt,
                calendar: fixedCalendar
            ),
            .nextTask(scheduledDate: date(2026, 3, 2, 12, 0))
        )
    }

    func testCromaticoCambiaDeCombinacionTodosLosDias() {
        let today = date(2026, 1, 1)
        let tomorrow = date(2026, 1, 2)

        XCTAssertNotEqual(
            ChromaticWarmupRotation.variation(for: today, calendar: fixedCalendar),
            ChromaticWarmupRotation.variation(for: tomorrow, calendar: fixedCalendar)
        )
    }

    func testCromaticoRecorreLas24PermutacionesSinRepetirPares() {
        let start = date(2026, 1, 1)
        let variations = (0..<12).map { offset in
            ChromaticWarmupRotation.variation(
                for: fixedCalendar.date(byAdding: .day, value: offset, to: start)!,
                calendar: fixedCalendar
            )
        }

        XCTAssertEqual(Set(variations.map(\.title)).count, 12)
        XCTAssertTrue(variations.allSatisfy { !$0.title.contains("y variaciones") })
        XCTAssertTrue(variations.allSatisfy { $0.instructions.contains("Un dedo por traste") })
    }

    func testCromaticoNoImponeUnaFiguraRitmica() {
        let variation = ChromaticWarmupRotation.variation(for: date(2026, 1, 1), calendar: fixedCalendar)

        XCTAssertEqual(variation.title, "Cromático 1-2-3-4 / 4-3-2-1")
        XCTAssertFalse(variation.instructions.hasPrefix("Figura rítmica:"))
        XCTAssertTrue(variation.instructions.contains("Elige la figura rítmica"))
    }

    func testCatalogoManualIncluyeFigurasSimplesIrregularesYPatrones() {
        let names = RhythmicFigure.allCases.map(\.displayName)

        XCTAssertTrue(names.contains("Redondas"))
        XCTAssertTrue(names.contains("Blancas"))
        XCTAssertTrue(names.contains("Negras con puntillo"))
        XCTAssertTrue(names.contains("Negras"))
        XCTAssertTrue(names.contains("Corcheas"))
        XCTAssertTrue(names.contains("Tresillos de corcheas"))
        XCTAssertTrue(names.contains("Semicorcheas"))
        XCTAssertTrue(names.contains("Quintillos"))
        XCTAssertTrue(names.contains("Seisillos / sextillos"))
        XCTAssertTrue(names.contains("Septillos"))
        XCTAssertTrue(names.contains("Fusas"))
        XCTAssertTrue(names.contains("Shuffle / swing"))
        XCTAssertTrue(names.contains("Galope"))
        XCTAssertTrue(names.contains("Galope invertido"))
    }
}
