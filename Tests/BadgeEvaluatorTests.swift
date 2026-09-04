import XCTest
import SwiftData
@testable import GuitarPracticeLab

/// El evaluador de insignias toca `ModelContext` (fetch + insert), así que a diferencia de la
/// mayoría de los tests deterministas de este target, estos necesitan un `ModelContainer` real en
/// memoria. Cubre lo más fácil de romper: que un criterio simple efectivamente otorgue la insignia,
/// y que evaluar dos veces no la duplique.
final class BadgeEvaluatorTests: XCTestCase {
    private func makeContext() -> ModelContext {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
        return ModelContext(container)
    }

    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    func testEscaleraDeLogrosTieneTodosLosRangosYDivisiones() {
        XCTAssertEqual(BadgeRank.all.count, 31)
        XCTAssertEqual(BadgeRank.all.first?.label, "Hierro IV")
        XCTAssertEqual(BadgeRank.all[3].label, "Hierro I")
        XCTAssertEqual(BadgeRank.all[4].label, "Bronce IV")
        XCTAssertEqual(BadgeRank.all[27].label, "Diamante I")
        XCTAssertEqual(BadgeRank.all[28].label, "Maestro")
        XCTAssertEqual(BadgeRank.all[29].label, "Gran Maestro")
        XCTAssertEqual(BadgeRank.all.last?.label, "Challenger")
    }

    func testChallengerSoloSeAlcanzaAlCompletarElLogro() {
        XCTAssertEqual(BadgeRank.forProgress(current: 0, target: 100).label, "Hierro IV")
        XCTAssertEqual(BadgeRank.forProgress(current: 50, target: 100).label, "Oro I")
        XCTAssertEqual(BadgeRank.forProgress(current: 99, target: 100).label, "Gran Maestro")
        XCTAssertEqual(BadgeRank.forProgress(current: 100, target: 100), .challenger)
        XCTAssertEqual(BadgeRank.forProgress(current: 150, target: 100), .challenger)
        XCTAssertEqual(BadgeRank.nextMilestone(current: 0, target: 100)?.rank.label, "Hierro III")
        XCTAssertEqual(BadgeRank.nextMilestone(current: 0, target: 100)?.required, 4)
        XCTAssertEqual(BadgeRank.nextMilestone(current: 99, target: 100)?.rank, .challenger)
        XCTAssertNil(BadgeRank.nextMilestone(current: 100, target: 100))
    }

    func testRachaDeSieteDiasOtorgaLaInsigniaDeConstancia() {
        let context = makeContext()
        for offset in 0..<7 {
            context.insert(PracticeSession(date: calendar.date(byAdding: .day, value: -offset, to: now)!, durationMinutes: 20))
        }

        BadgeEvaluator.evaluate(context: context, now: now)

        let earned = (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []
        XCTAssertTrue(earned.contains { $0.id == "constancia-racha-7" })
    }

    func testEvaluarDosVecesNoDuplicaLaMismaInsignia() {
        let context = makeContext()
        for offset in 0..<7 {
            context.insert(PracticeSession(date: calendar.date(byAdding: .day, value: -offset, to: now)!, durationMinutes: 20))
        }

        BadgeEvaluator.evaluate(context: context, now: now)
        BadgeEvaluator.evaluate(context: context, now: now)

        let earned = (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []
        XCTAssertEqual(earned.filter { $0.id == "constancia-racha-7" }.count, 1)
    }

    func testDiezEjerciciosDominadosOtorganLaInsigniaDeBiblioteca() {
        let context = makeContext()
        for index in 0..<10 {
            context.insert(LibraryExercise(
                collectionName: "Test",
                bookTitle: "Libro \(index)",
                technique: "Bending",
                status: .mastered
            ))
        }

        BadgeEvaluator.evaluate(context: context, now: now)

        let earned = (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []
        XCTAssertTrue(earned.contains { $0.id == "biblioteca-ejercicios-10" })
    }

    func testSinDatosNoOtorgaNingunaInsignia() {
        let context = makeContext()

        BadgeEvaluator.evaluate(context: context, now: now)

        let earned = (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []
        XCTAssertTrue(earned.isEmpty)
    }
}
