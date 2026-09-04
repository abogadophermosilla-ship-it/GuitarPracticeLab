import XCTest
@testable import GuitarPracticeLab

/// Mismo motivo que `TheoryFlashcardSchedulerTests`: si la caja de Leitner se mueve mal, el
/// entrenamiento de oído repasa de más lo que ya se sabe y de menos lo que falla.
final class EarTrainingSchedulerTests: XCTestCase {
    private func progress(_ id: String = EarTrainingItem.interval(.major3).id) -> EarTrainingProgress {
        EarTrainingProgress(id: id)
    }

    func testAciertoSubeUnaCajaYAlejaLaProximaRevision() {
        let item = progress()
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        EarTrainingScheduler.record(item, isCorrect: true, now: now)

        XCTAssertEqual(item.boxLevel, 2)
        XCTAssertEqual(item.correctCount, 1)
        let esperado = Calendar.current.date(byAdding: .day, value: 1, to: now)
        XCTAssertEqual(item.nextReviewDate, esperado)
    }

    func testFalloResetraALaCajaUnoAunqueVinieraDeLaCajaAlta() {
        let item = progress()
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        for _ in 0..<4 { EarTrainingScheduler.record(item, isCorrect: true, now: now) }
        XCTAssertEqual(item.boxLevel, 5)

        EarTrainingScheduler.record(item, isCorrect: false, now: now)

        XCTAssertEqual(item.boxLevel, 1)
        XCTAssertEqual(item.wrongCount, 1)
        XCTAssertEqual(item.nextReviewDate, now)
    }

    func testLaCajaNoPasaDeCinco() {
        let item = progress()
        for _ in 0..<10 { EarTrainingScheduler.record(item, isCorrect: true) }

        XCTAssertEqual(item.boxLevel, 5)
    }

    func testLosDieciseisItemsSinProgresoCuentanComoVencidos() {
        let resultado = EarTrainingScheduler.rankedItems(progress: [])

        XCTAssertEqual(resultado.items.count, 16)
        XCTAssertEqual(resultado.dueCount, 16)
    }

    /// Da progreso "no vencido" a los 16 ítems y luego vence solo uno — sin esto, los ítems sin
    /// ningún progreso también cuentan como vencidos (a propósito, igual que en flashcards de
    /// teoría) y contaminan la comparación.
    func testUnItemVencidoQuedaAntesQueLosDemasNoVencidos() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let future = Calendar.current.date(byAdding: .day, value: 14, to: now)!

        let records = EarTrainingItem.all.map { item -> EarTrainingProgress in
            let record = EarTrainingProgress(id: item.id)
            record.boxLevel = 5
            record.nextReviewDate = future
            return record
        }
        let dueID = EarTrainingItem.interval(.minor2).id
        let dueIndex = records.firstIndex { $0.id == dueID }!
        records[dueIndex].boxLevel = 1
        records[dueIndex].nextReviewDate = now

        let resultado = EarTrainingScheduler.rankedItems(progress: records, now: now)

        XCTAssertEqual(resultado.items.first?.id, dueID)
        XCTAssertEqual(resultado.dueCount, 1)
    }
}
