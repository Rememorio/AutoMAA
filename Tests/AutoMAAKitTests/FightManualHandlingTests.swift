import Foundation
import XCTest
@testable import AutoMAAKit

final class FightManualHandlingTests: XCTestCase {
    func testHandlingPreservesEvidenceWithoutSuccessAndIsScopedToTheDayAndStep() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fight-handling-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExecutionStateStore(directories: AppDirectories(root: root))
        let step = WorkflowStep(planID: UUID(), clientID: UUID(), accountID: UUID(), task: .fight)
        let other = WorkflowStep(planID: UUID(), clientID: step.clientID, accountID: step.accountID, task: .fight)
        let result = FightResult(status: .unconfirmed, stage: "PA-8", times: 2, reason: .interruptedBattle, kind: .regular)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(result, for: step.key)
        state.record(result, for: other.key)
        try store.save(state)
        let handled = try store.handleRegularWithoutRetry(step, expected: result)
        XCTAssertEqual(handled.fightProgress?[step.key]?.regular, result)
        XCTAssertNotNil(handled.fightProgress?[step.key]?.regularManuallyHandledAt)
        XCTAssertEqual(handled.fightResults?[step.key]?.status, .manuallyHandled)
        XCTAssertFalse(handled.completedSteps.contains(step.key))
        XCTAssertFalse(handled.needsFightConfirmation(step.key))
        XCTAssertTrue(handled.needsFightConfirmation(other.key))
        let persisted = try store.loadForExecution()
        XCTAssertEqual(persisted.fightResults, handled.fightResults)
        XCTAssertEqual(persisted.fightProgress?[step.key]?.regular, result)
        XCTAssertEqual(try XCTUnwrap(persisted.fightProgress?[step.key]?.regularManuallyHandledAt).timeIntervalSince1970,
                       try XCTUnwrap(handled.fightProgress?[step.key]?.regularManuallyHandledAt).timeIntervalSince1970, accuracy: 1)
        XCTAssertThrowsError(try store.handleRegularWithoutRetry(step, expected: result))
        var expired = handled
        expired.dateKey = "2000-01-01"
        try store.save(expired)
        XCTAssertThrowsError(try store.handleRegularWithoutRetry(step, expected: result))
        XCTAssertTrue(try store.loadForExecution().fightResults?.isEmpty ?? true)
    }

    func testHandlingRejectsRunningWorkflowStaleResultsAndAnnihilation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fight-handling-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root), store = ExecutionStateStore(directories: directories)
        let step = WorkflowStep(planID: UUID(), clientID: UUID(), accountID: UUID(), task: .fight)
        let result = FightResult(status: .unconfirmed, stage: "PA-8", reason: .missingEvidence)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(result, for: step.key)
        try store.save(state)
        let persisted = try store.loadForExecution()
        let lock = try ProcessLock(url: directories.lock)
        try withExtendedLifetime(lock) {
            XCTAssertThrowsError(try store.handleRegularWithoutRetry(step, expected: result))
            XCTAssertEqual(try store.loadForExecution(), persisted)
        }
        XCTAssertFalse(state.canHandleRegularWithoutRetry(step.key, expected: .init(status: .unconfirmed, stage: "CE-6")))
        for result in [FightResult(status: .completed, stage: "PA-8"),
                       .init(status: .unconfirmed, stage: "Annihilation"),
                       .init(status: .unconfirmed, kind: .annihilation)] {
            state.record(result, for: step.key)
            XCTAssertThrowsError(try state.handleRegularWithoutRetry(step, expected: result, at: Date()))
        }
    }

    func testManualHandlingSummaryDoesNotCountAutomaticSuccess() {
        var report = WorkflowReport(totalSteps: 2)
        report.manuallyHandledSteps = 1
        XCTAssertEqual(report.runSummary?.completedSteps, 1)
        XCTAssertEqual(report.runSummary?.manuallyHandledSteps, 1)
        XCTAssertTrue(report.runSummary?.completionDescription.contains("已人工处理") == true)
    }

    func testSharedWeeklyCompletionRestoresHandledRegularAfterAnInterruptedPreparation() throws {
        let now = Date(), account = AccountConfiguration(name: "Test")
        let client = ClientConfiguration(name: "Test", kind: .yoStarJP, appPath: "/test/Fake.app",
            address: "127.0.0.1:65495", profileName: "manual-weekly", bundleIdentifier: "dev.automaa.tests.manual-weekly",
            accounts: [account])
        var plan = AutomationPlan.lightRoutine
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = false
        plan.fight.weeklyAnnihilation.enabled = true
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        let original = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(original, for: step.key)
        try state.handleRegularWithoutRetry(step, expected: original, at: now)
        state.prepareWeeklyAnnihilation(plan: plan, clients: [client], weekly: .init(), at: now)
        XCTAssertNil(state.fightResults?[step.key])
        var weekly = WeeklyAnnihilationState()
        weekly.record(.init(status: .unnecessary, reason: .confirmedWeeklyLimit), client: client, accountID: account.id,
            weekStart: GameWeek(client: client.kind, at: now).start, at: now)
        state.prepareWeeklyAnnihilation(plan: plan, clients: [client], weekly: weekly, at: now)
        let continuation = PlanContinuation(configuration: .init(clients: [client], plans: [plan]),
            planID: plan.id, state: state, history: [], weeklyAnnihilation: weekly, now: now)
        XCTAssertEqual(continuation.pending, 0)
        XCTAssertEqual(continuation.unconfirmed, 0)
        XCTAssertEqual(continuation.manuallyHandled, 1)
        XCTAssertEqual(continuation.completionTitle, "今日已处理")
        XCTAssertEqual(state.fightProgress?[step.key]?.regular, original)
        XCTAssertFalse(state.completedSteps.contains(step.key))
    }
}
