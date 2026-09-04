import XCTest
@testable import GuitarPracticeLab

final class RhythmTrainingTests: XCTestCase {
    func testSupportedSubdivisionsHaveExpectedEventsPerBeat() {
        XCTAssertEqual(RhythmTimingAnalyzer.eventsPerBeat(for: .quarterNotes), 1)
        XCTAssertEqual(RhythmTimingAnalyzer.eventsPerBeat(for: .eighthNotes), 2)
        XCTAssertEqual(RhythmTimingAnalyzer.eventsPerBeat(for: .eighthNoteTriplets), 3)
        XCTAssertEqual(RhythmTimingAnalyzer.eventsPerBeat(for: .sixteenthNotes), 4)
        XCTAssertEqual(RhythmTimingAnalyzer.eventsPerBeat(for: .sextuplets), 6)
    }

    func testTapKeepsEarlyOrLateDirectionAgainstNearestGridPoint() throws {
        let late = try XCTUnwrap(RhythmTimingAnalyzer.measurement(
            tapUptime: 101.025,
            startUptime: 100,
            bpm: 60,
            figure: .eighthNotes
        ))
        XCTAssertEqual(late.gridIndex, 2)
        XCTAssertEqual(late.offsetMilliseconds, 25, accuracy: 0.001)

        let early = try XCTUnwrap(RhythmTimingAnalyzer.measurement(
            tapUptime: 100.98,
            startUptime: 100,
            bpm: 60,
            figure: .eighthNotes
        ))
        XCTAssertEqual(early.gridIndex, 2)
        XCTAssertEqual(early.offsetMilliseconds, -20, accuracy: 0.001)
    }

    func testSummaryRewardsCloseConsistentTaps() throws {
        let taps = [10.0, -20, 30, -15].enumerated().map {
            RhythmTapMeasurement(gridIndex: $0.offset, offsetMilliseconds: $0.element)
        }
        let summary = try XCTUnwrap(RhythmTimingAnalyzer.summary(for: taps))
        XCTAssertEqual(summary.tapCount, 4)
        XCTAssertEqual(summary.closeTapRatio, 1)
        XCTAssertGreaterThan(summary.accuracy, 0.85)
    }
}
