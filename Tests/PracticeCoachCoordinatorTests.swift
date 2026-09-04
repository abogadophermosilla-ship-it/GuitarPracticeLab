import XCTest
import SwiftData
@testable import GuitarPracticeLab

final class PracticeCoachCoordinatorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 18))!
    }

    private func task(
        id: UUID = UUID(),
        sourceID: UUID? = nil,
        title: String = "Picking alternado",
        minutes: Int = 15,
        targetBPM: Int = 80,
        priority: Int = 1
    ) -> PracticeCoachTaskSnapshot {
        PracticeCoachTaskSnapshot(
            id: id,
            title: title,
            categoryRaw: PracticeCategory.technique.rawValue,
            plannedMinutes: minutes,
            sourceTitle: "Método",
            exerciseTitle: title,
            targetBPM: targetBPM,
            priority: priority,
            isCompleted: false,
            scheduledDate: now,
            sourceKindRaw: TaskSourceKind.library.rawValue,
            sourceID: sourceID,
            instructions: "Tres repeticiones limpias"
        )
    }

    private func session(
        id: UUID = UUID(),
        sourceID: UUID? = nil,
        title: String = "Picking alternado",
        daysAgo: Int = 0,
        endBPM: Int = 80,
        result: PracticeResult = .learning,
        repetitions: Int = 2,
        tension: Int = 1
    ) -> PracticeCoachSessionSnapshot {
        PracticeCoachSessionSnapshot(
            id: id,
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
            durationMinutes: 10,
            categoryRaw: PracticeCategory.technique.rawValue,
            sourceKindRaw: TaskSourceKind.library.rawValue,
            sourceID: sourceID,
            sourceTitle: "Método",
            exerciseTitle: title,
            startBPM: max(0, endBPM - 10),
            endBPM: endBPM,
            resultRaw: result.rawValue,
            correctRepetitions: repetitions,
            tensionRating: tension,
            practiceContextRaw: PracticeApplicationContext.metronome.rawValue,
            wasColdCheck: false
        )
    }

    private func snapshot(
        task: PracticeCoachTaskSnapshot,
        sessions: [PracticeCoachSessionSnapshot] = [],
        budget: Int = 45,
        practicedToday: Int = 0
    ) -> PracticeCoachSnapshot {
        PracticeCoachSnapshot(
            evaluatedAt: now,
            dailyBudgetMinutes: budget,
            practicedTodayMinutes: practicedToday,
            plannedTaskIDs: [task.id],
            sessions: sessions.sorted { $0.date > $1.date },
            tasks: [task],
            songs: [],
            skills: [],
            latestTeacherInstruction: nil
        )
    }

    func testSnapshotAndDecisionAreReproducible() {
        let sourceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let taskID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let value = snapshot(task: task(id: taskID, sourceID: sourceID))

        let first = PracticeCoachDecisionEngine.decide(snapshot: value, trigger: .manualRefresh)
        let second = PracticeCoachDecisionEngine.decide(snapshot: value, trigger: .manualRefresh)

        XCTAssertEqual(value.fingerprint, value.fingerprint)
        XCTAssertEqual(first, second)
    }

    func testIrrelevantSessionMaintainsPreviousPriorityButRelevantSuccessAdjustsIt() {
        let sourceID = UUID()
        let planned = task(sourceID: sourceID)
        let base = snapshot(task: planned)
        let previous = PracticeCoachDecisionEngine.decide(snapshot: base, trigger: .appLaunch)

        let unrelated = session(sourceID: UUID(), title: "Acordes abiertos")
        let maintained = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot(task: planned, sessions: [unrelated]),
            previous: previous,
            trigger: .sessionCompleted
        )
        XCTAssertEqual(maintained.taskID, previous.taskID)
        XCTAssertEqual(maintained.priority, .maintainPlan)

        let relevant = session(
            sourceID: sourceID,
            result: .targetTempo,
            repetitions: 4,
            tension: 1
        )
        let adjusted = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot(task: planned, sessions: [relevant]),
            previous: previous,
            trigger: .sessionCompleted
        )
        XCTAssertEqual(adjusted.priority, .progression)
        XCTAssertEqual(adjusted.targetBPM, 85)
    }

    func testHighTensionBlocksBPMIncrease() {
        let sourceID = UUID()
        let planned = task(sourceID: sourceID, targetBPM: 100)
        let tense = session(
            sourceID: sourceID,
            endBPM: 100,
            result: .targetTempo,
            repetitions: 5,
            tension: 4
        )

        let decision = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot(task: planned, sessions: [tense]),
            trigger: .sessionCompleted
        )

        XCTAssertEqual(decision.priority, .safety)
        XCTAssertLessThanOrEqual(decision.targetBPM, 100)
        XCTAssertNotEqual(decision.change.proposedTargetBPM, 105)
    }

    func testStagnationRequiresThreeComparableSessions() {
        let sourceID = UUID()
        let planned = task(sourceID: sourceID)
        let two = [
            session(sourceID: sourceID, daysAgo: 4, endBPM: 80),
            session(sourceID: sourceID, daysAgo: 2, endBPM: 81)
        ]
        let withoutEnoughEvidence = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot(task: planned, sessions: two),
            trigger: .manualRefresh
        )
        XCTAssertNotEqual(withoutEnoughEvidence.priority, .stagnation)

        let three = two + [session(sourceID: sourceID, daysAgo: 0, endBPM: 80)]
        let stagnant = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot(task: planned, sessions: three),
            trigger: .manualRefresh
        )
        XCTAssertEqual(stagnant.priority, .stagnation)
        XCTAssertTrue(stagnant.change.requiresConfirmation)
    }

    func testDeterministicCoachIsUsefulWithoutAIAndRespectsRemainingBudget() {
        let planned = task(minutes: 15)
        let decision = PracticeCoachDecisionEngine.decide(
            snapshot: snapshot(task: planned, budget: 10, practicedToday: 8),
            trigger: .appLaunch
        )

        XCTAssertFalse(decision.nextAction.isEmpty)
        XCTAssertFalse(decision.reason.isEmpty)
        XCTAssertEqual(decision.suggestedMinutes, 2)
    }

    @MainActor
    func testRepeatedReevaluationDoesNotDuplicateTasksOrState() throws {
        let schema = Schema(versionedSchema: SchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        context.insert(PracticeTask(title: "Economía de púa", category: .technique, plannedMinutes: 15))

        let first = try PracticeCoachCoordinator.reevaluate(
            trigger: .manualRefresh,
            in: context,
            dailyBudgetMinutes: 45,
            now: now,
            calendar: calendar
        )
        let second = try PracticeCoachCoordinator.reevaluate(
            trigger: .manualRefresh,
            in: context,
            dailyBudgetMinutes: 45,
            now: now.addingTimeInterval(60),
            calendar: calendar
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PracticeTask>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PracticeCoachStateRecord>()), 1)
    }

    @MainActor
    func testApprovalRequiredChangeIsNotAppliedAutomatically() throws {
        let schema = Schema(versionedSchema: SchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let sourceID = UUID()
        let planned = PracticeTask(
            title: "Picking alternado",
            category: .technique,
            plannedMinutes: 15,
            sourceTitle: "Método",
            exerciseTitle: "Picking alternado",
            targetBPM: 80,
            sourceKind: .library,
            sourceID: sourceID
        )
        context.insert(planned)
        context.insert(PracticeSession(
            date: now,
            durationMinutes: 10,
            category: .technique,
            sourceTitle: "Método",
            exerciseTitle: "Picking alternado",
            endBPM: 80,
            result: .targetTempo,
            sourceKind: .library,
            sourceID: sourceID,
            correctRepetitions: 4,
            tensionRating: 1,
            practiceContext: .metronome
        ))

        let decision = try PracticeCoachCoordinator.reevaluate(
            trigger: .sessionCompleted,
            in: context,
            dailyBudgetMinutes: 45,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(decision.change.requiresConfirmation)
        XCTAssertEqual(planned.targetBPM, 80)

        _ = try PracticeCoachCoordinator.approveCurrentChange(in: context)
        XCTAssertEqual(planned.targetBPM, 85)
    }

    @MainActor
    func testMinimalCompletionFlowSchedulesOnceAndRefreshesTodayCoach() throws {
        let schema = Schema(versionedSchema: SchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let exercise = LibraryExercise(
            collectionName: "Técnica",
            bookTitle: "Método",
            technique: "Picking alternado",
            targetBPM: 80,
            status: .learning
        )
        let completed = PracticeTask(
            title: "Picking alternado",
            category: .technique,
            plannedMinutes: 15,
            sourceTitle: exercise.bookTitle,
            exerciseTitle: exercise.displayName,
            targetBPM: 80,
            priority: 0,
            sourceKind: .library,
            sourceID: exercise.id
        )
        context.insert(exercise)
        context.insert(completed)

        let next = try XCTUnwrap(RecurringPracticeService.completeTask(
            completed,
            completedAt: now,
            outcome: PracticeOutcome(
                result: .learning,
                endBPM: 75,
                correctRepetitions: 2,
                tensionRating: 1,
                context: .metronome,
                wasColdCheck: false
            ),
            in: context,
            calendar: calendar
        ))
        context.insert(PracticeSession(
            date: now,
            durationMinutes: 15,
            category: .technique,
            sourceTitle: exercise.bookTitle,
            exerciseTitle: exercise.displayName,
            endBPM: 75,
            result: .learning,
            sourceKind: .library,
            sourceID: exercise.id,
            correctRepetitions: 2,
            tensionRating: 1,
            practiceContext: .metronome
        ))

        let decision = try PracticeCoachCoordinator.reevaluate(
            trigger: .sessionCompleted,
            in: context,
            dailyBudgetMinutes: 45,
            now: now,
            calendar: calendar
        )
        _ = try PracticeCoachCoordinator.reevaluate(
            trigger: .manualRefresh,
            in: context,
            dailyBudgetMinutes: 45,
            now: now,
            calendar: calendar
        )

        let pending = try context.fetch(FetchDescriptor<PracticeTask>()).filter { !$0.isCompleted }
        XCTAssertEqual(pending.map(\.id), [next.id])
        XCTAssertEqual(decision.taskID, next.id)
        XCTAssertEqual(decision.priority, .spacedReview)
        XCTAssertEqual(decision.suggestedMinutes, 0)
        XCTAssertEqual(
            calendar.startOfDay(for: next.scheduledDate),
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PracticeCoachStateRecord>()), 1)
    }
}
