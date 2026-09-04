import XCTest
@testable import GuitarPracticeLab

/// El contador decide qué partes de la app se podan o se fusionan, así que tiene que contar bien:
/// un número inflado o perdido llevaría a sacar una sección que sí se usa.
final class SectionUsageTrackerTests: XCTestCase {

    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "SectionUsageTrackerTests-\(UUID().uuidString)"
        SectionUsageTracker.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        SectionUsageTracker.reset()
    }

    override func tearDownWithError() throws {
        SectionUsageTracker.reset()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        SectionUsageTracker.defaults = .standard
    }

    func testCountsAccumulatePerSection() {
        SectionUsageTracker.recordOpen("Hoy")
        SectionUsageTracker.recordOpen("Hoy")
        SectionUsageTracker.recordOpen("Repertorio")

        XCTAssertEqual(SectionUsageTracker.allCounts()["Hoy"], 2)
        XCTAssertEqual(SectionUsageTracker.allCounts()["Repertorio"], 1)
        XCTAssertEqual(SectionUsageTracker.totalOpens(), 3)
    }

    /// Las secciones nunca abiertas tienen que aparecer en 0 — son las que más importan al decidir.
    func testRankingIncludesNeverOpenedSections() {
        SectionUsageTracker.recordOpen("Hoy")

        let ranking = SectionUsageTracker.ranking(allSections: ["Hoy", "Mástil", "Academia"])

        XCTAssertEqual(ranking.first?.section, "Hoy")
        XCTAssertEqual(ranking.first?.count, 1)
        XCTAssertEqual(ranking.count, 3)
        XCTAssertTrue(ranking.dropFirst().allSatisfy { $0.count == 0 })
    }

    /// A igual conteo, orden alfabético estable: el ranking no debe bailar entre aperturas.
    func testRankingBreaksTiesAlphabetically() {
        let ranking = SectionUsageTracker.ranking(allSections: ["Progreso", "Academia", "Mástil"])
        XCTAssertEqual(ranking.map(\.section), ["Academia", "Mástil", "Progreso"])
    }

    func testMeasuringSinceIsSetOnFirstOpenAndKept() {
        XCTAssertNil(SectionUsageTracker.measuringSince())

        SectionUsageTracker.recordOpen("Hoy")
        let first = SectionUsageTracker.measuringSince()
        XCTAssertNotNil(first)

        SectionUsageTracker.recordOpen("Tareas")
        XCTAssertEqual(SectionUsageTracker.measuringSince(), first, "La fecha de inicio no se reinicia sola")
    }

    func testResetClearsCountsAndStartDate() {
        SectionUsageTracker.recordOpen("Hoy")
        SectionUsageTracker.reset()

        XCTAssertEqual(SectionUsageTracker.totalOpens(), 0)
        XCTAssertNil(SectionUsageTracker.measuringSince())
    }

    func testInitialOpenIsRecordedOnlyOncePerAppLaunch() {
        SectionUsageTracker.recordInitialOpenIfNeeded("Hoy")
        SectionUsageTracker.recordInitialOpenIfNeeded("Hoy")

        XCTAssertEqual(SectionUsageTracker.allCounts()["Hoy"], 1)
        XCTAssertEqual(SectionUsageTracker.totalOpens(), 1)
    }
}
