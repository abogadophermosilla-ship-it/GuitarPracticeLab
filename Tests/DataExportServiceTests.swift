import XCTest
@testable import GuitarPracticeLab

final class DataExportServiceTests: XCTestCase {

    private func session(
        date: Date,
        notes: String = "",
        exercise: String = "Cromatismo",
        minutes: Int = 30,
        rhythmicFigure: RhythmicFigure = .unspecified
    ) -> DataExportService.Archive.Session {
        .init(
            id: UUID(),
            date: date,
            durationMinutes: minutes,
            instrumentName: "Strat",
            category: "Técnica",
            sourceTitle: "Troy Nelson",
            exerciseTitle: exercise,
            startBPM: 80,
            endBPM: 96,
            difficulty: 3,
            result: "Aprendiendo",
            notes: notes,
            sourceKind: "Biblioteca",
            sourceID: nil,
            rhythmicFigure: rhythmicFigure.rawValue
        )
    }

    func testCSVIncluyeEncabezadoYUnaFilaPorSesion() {
        let csv = DataExportService.sessionsCSV(from: [
            session(date: Date(timeIntervalSince1970: 1_770_000_000)),
            session(date: Date(timeIntervalSince1970: 1_772_000_000))
        ])

        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Fecha,Minutos,Segundos exactos,Instrumento"))
        XCTAssertTrue(lines[0].contains("Esfuerzo percibido (1-5)"))
        XCTAssertTrue(lines[0].contains("Figura rítmica"))
        XCTAssertTrue(lines[0].contains("Pasadas completas"))
    }

    func testCSVExportaLaFiguraRitmicaElegida() {
        let csv = DataExportService.sessionsCSV(from: [
            session(date: Date(timeIntervalSince1970: 1_770_000_000), rhythmicFigure: .sixteenthNotes)
        ])

        XCTAssertTrue(csv.split(separator: "\n")[1].contains("Semicorcheas"))
    }

    func testCSVOrdenaPorFechaAscendente() {
        let vieja = Date(timeIntervalSince1970: 1_700_000_000)
        let nueva = Date(timeIntervalSince1970: 1_800_000_000)

        let csv = DataExportService.sessionsCSV(from: [
            session(date: nueva, exercise: "Segunda"),
            session(date: vieja, exercise: "Primera")
        ])

        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[1].contains("Primera"))
        XCTAssertTrue(lines[2].contains("Segunda"))
    }

    func testCSVEscapaComasComillasYSaltosDeLinea() {
        let csv = DataExportService.sessionsCSV(from: [
            session(
                date: Date(timeIntervalSince1970: 1_770_000_000),
                notes: "Subí el tempo, pero la \"púa\" se traba\nprobar mañana"
            )
        ])

        let fila = csv.split(separator: "\n")[1]
        // Las comillas internas se duplican y el campo entero queda entre comillas.
        XCTAssertTrue(fila.contains("\"\"púa\"\""))
        // El salto de línea se aplana: una sesión = una fila, siempre.
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }
}
