import XCTest
@testable import GuitarPracticeLab

final class SkillAudioAssessmentTests: XCTestCase {
    func testMonthlyReviewUsesCalendarMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let last = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15)))
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 14)))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 15)))

        XCTAssertFalse(SkillAudioAssessmentSchedule.isMonthlyReviewDue(
            hasCompletedInitial: true,
            lastCompletedAt: last,
            now: before,
            calendar: calendar
        ))
        XCTAssertTrue(SkillAudioAssessmentSchedule.isMonthlyReviewDue(
            hasCompletedInitial: true,
            lastCompletedAt: last,
            now: due,
            calendar: calendar
        ))
    }

    func testStablePulseScoresHighAndIncludesMeasuredValues() throws {
        let challenge = SkillAudioChallenge(
            skillID: UUID(),
            skillName: "Ritmo, subdivisión y groove",
            title: "Corcheas",
            instructions: "",
            targetBPM: 60,
            attacksPerBeat: 2,
            duration: 12,
            metricProfile: .pulse
        )
        let metrics = SkillAudioAssessmentMetrics(
            duration: 12,
            attackCount: 20,
            meanAttackInterval: 0.5,
            attackIntervalVariation: 0.02,
            activeRatio: 0.30,
            pitchedRatio: 0.70,
            pitchRangeSemitones: 1
        )

        let score = try XCTUnwrap(SkillAudioAssessmentScorer.score(metrics: metrics, challenge: challenge))
        XCTAssertGreaterThan(score.score, 0.85)
        XCTAssertTrue(score.summary.contains("20 ataques"))
        XCTAssertTrue(score.summary.contains("100%"))
    }

    func testSilentRecordingDoesNotProduceEvidence() {
        let challenge = SkillAudioChallenge(
            skillID: UUID(), skillName: "Ritmo", title: "Pulso", instructions: "",
            targetBPM: 60, attacksPerBeat: 1, duration: 12, metricProfile: .pulse
        )
        let metrics = SkillAudioAssessmentMetrics(
            duration: 12, attackCount: 0, meanAttackInterval: nil,
            attackIntervalVariation: nil, activeRatio: 0, pitchedRatio: 0, pitchRangeSemitones: nil
        )
        XCTAssertNil(SkillAudioAssessmentScorer.score(metrics: metrics, challenge: challenge))
    }
}
