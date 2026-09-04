import XCTest
@testable import GuitarPracticeLab

/// La repetición espaciada decide qué se repasa cada día; si la caja de Leitner se mueve mal, el
/// usuario repasa de más lo que ya sabe y de menos lo que falla. Vale la pena tenerlo cubierto.
final class TheoryFlashcardSchedulerTests: XCTestCase {

    private func progress() -> TheoryFlashcardProgress {
        TheoryFlashcardProgress(topicID: UUID(), questionIndex: 0)
    }

    func testAciertoSubeUnaCajaYAlejaLaProximaRevision() {
        let item = progress()
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        TheoryFlashcardScheduler.record(item, isCorrect: true, now: now)

        XCTAssertEqual(item.boxLevel, 2)
        XCTAssertEqual(item.correctCount, 1)
        let esperado = Calendar.current.date(byAdding: .day, value: 1, to: now)
        XCTAssertEqual(item.nextReviewDate, esperado)
    }

    func testFalloResetraALaCajaUnoAunqueVinieraDeLaCajaAlta() {
        let item = progress()
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        for _ in 0..<4 { TheoryFlashcardScheduler.record(item, isCorrect: true, now: now) }
        XCTAssertEqual(item.boxLevel, 5)

        TheoryFlashcardScheduler.record(item, isCorrect: false, now: now)

        XCTAssertEqual(item.boxLevel, 1)
        XCTAssertEqual(item.wrongCount, 1)
        // Caja 1 vence de inmediato: vuelve a ser prioridad máxima.
        XCTAssertEqual(item.nextReviewDate, now)
    }

    func testLaCajaNoPasaDeCinco() {
        let item = progress()
        for _ in 0..<10 { TheoryFlashcardScheduler.record(item, isCorrect: true) }

        XCTAssertEqual(item.boxLevel, 5)
    }

    func testTarjetasSinProgresoCuentanComoVencidas() {
        let topic = SkillTopic(
            name: "Intervalos",
            domain: .theory,
            level: .basic,
            assessmentQuestions: [
                AssessmentQuestion(question: "¿Cuántos semitonos tiene una tercera mayor?", options: [
                    AssessmentOption(text: "4", points: 1),
                    AssessmentOption(text: "3", points: 0)
                ])
            ]
        )

        let resultado = TheoryFlashcardScheduler.rankedCards(topics: [topic], progress: [])

        XCTAssertEqual(resultado.cards.count, 1)
        XCTAssertEqual(resultado.dueCount, 1)
    }

    func testCorrectIndexApuntaALaOpcionConPuntaje() {
        let topic = SkillTopic(
            name: "Armadura",
            domain: .theory,
            level: .basic,
            assessmentQuestions: [
                AssessmentQuestion(question: "¿Cuántos sostenidos tiene La mayor?", options: [
                    AssessmentOption(text: "Dos", points: 0),
                    AssessmentOption(text: "Tres", points: 1),
                    AssessmentOption(text: "Cuatro", points: 0)
                ])
            ]
        )

        let card = TheoryFlashcard(
            id: TheoryFlashcardProgress.makeID(topicID: topic.id, questionIndex: 0),
            topic: topic,
            questionIndex: 0
        )

        XCTAssertEqual(card.correctIndex, 1)
    }
}
