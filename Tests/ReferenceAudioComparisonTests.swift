import XCTest
@testable import GuitarPracticeLab

final class ReferenceAudioComparisonTests: XCTestCase {
    func testSamePhraseAtDifferentTempoStillScoresHigh() throws {
        let performance = metadata(
            pitches: [60, 62, 64, 65, 67],
            starts: [0, 0.5, 1, 1.5, 2]
        )
        let reference = metadata(
            pitches: [60, 62, 64, 65, 67],
            starts: [0, 0.75, 1.5, 2.25, 3]
        )

        let result = try XCTUnwrap(ReferenceAudioEvidenceScorer.score(
            performanceMetadataJSON: performance,
            referenceMetadataJSON: reference
        ))
        XCTAssertGreaterThan(result.score, 0.95)
        XCTAssertTrue(result.summary.contains("coincidencia de notas 100%"))
        XCTAssertTrue(result.summary.contains("proporción rítmica 100%"))
    }

    func testDifferentPhraseLosesPitchScore() throws {
        let performance = metadata(pitches: [48, 49, 50, 51], starts: [0, 0.5, 1, 1.5])
        let reference = metadata(pitches: [72, 74, 76, 77], starts: [0, 0.5, 1, 1.5])

        let result = try XCTUnwrap(ReferenceAudioEvidenceScorer.score(
            performanceMetadataJSON: performance,
            referenceMetadataJSON: reference
        ))
        XCTAssertLessThan(result.score, 0.45)
    }

    private func metadata(pitches: [Int], starts: [Double]) -> String {
        let root: [String: Any] = ["notes": ["pitchSequence": pitches, "startTimes": starts]]
        let data = try! JSONSerialization.data(withJSONObject: root)
        return String(data: data, encoding: .utf8)!
    }
}
