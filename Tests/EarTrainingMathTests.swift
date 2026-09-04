import XCTest
@testable import GuitarPracticeLab

/// La síntesis del motor de audio no se puede probar (no es determinística fuera del hilo de audio
/// real), pero la conversión MIDI→Hz que la alimenta sí — un error de octava ahí haría sonar
/// cualquier intervalo o acorde mal, silenciosamente.
final class EarTrainingMathTests: XCTestCase {
    func testLaNota69EsLaCentralA440() {
        XCTAssertEqual(EarTrainingMath.frequency(forMidi: 69), 440, accuracy: 0.001)
    }

    func testUnaOctavaArribaDuplicaLaFrecuencia() {
        XCTAssertEqual(EarTrainingMath.frequency(forMidi: 81), 880, accuracy: 0.001)
    }

    func testUnaOctavaAbajoLaMitadDeLaFrecuencia() {
        XCTAssertEqual(EarTrainingMath.frequency(forMidi: 57), 220, accuracy: 0.001)
    }

    func testTodosLosIntervalosTienenSemitonosDistintosYEnRangoDeUnaOctava() {
        let semitones = Set(EarInterval.allCases.map(\.semitones))
        XCTAssertEqual(semitones.count, EarInterval.allCases.count)
        XCTAssertTrue(semitones.allSatisfy { (1...11).contains($0) })
    }

    func testLosDieciseisItemsFijosTienenIDsUnicos() {
        let ids = Set(EarTrainingItem.all.map(\.id))
        XCTAssertEqual(ids.count, EarTrainingItem.all.count)
        XCTAssertEqual(EarTrainingItem.all.count, 16)
    }
}
