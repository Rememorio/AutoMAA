import Foundation
import XCTest
@testable import AutoMAAKit

final class FightManualHandlingTests: XCTestCase {
    func testReviewedRegularFightCannotBeHandledAfterRoundOrGameDayChanges() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fight-review-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExecutionStateStore(directories: AppDirectories(root: root))
        let client = testClient, plan = AutomationPlan.lightRoutine
        let configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: client.accounts[0].id, task: .fight)
        let today = Date(timeIntervalSince1970: 1_800_000_000), tomorrow = today.addingTimeInterval(86_400)
        var state = ExecutionState().forGameDays(of: [client], at: today)
        state.startRound(for: plan.id, at: today)
        state.record(.init(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular),
                     for: step.key, at: today)
        try store.save(state)
        func review(at date: Date) throws -> FightRecoveryItem {
            let snapshot = try store.loadForExecution()
            return try XCTUnwrap(PlanContinuation(configuration: configuration, planID: plan.id, state: snapshot,
                                                  history: [], now: date).fightRecoveryItems.first)
        }

        let first = try review(at: today)
        state.startRound(for: plan.id, at: today)
        try store.save(state)
        let second = try review(at: today)
        XCTAssertEqual(first.result, second.result)
        XCTAssertNotEqual(first, second)
        XCTAssertThrowsError(try store.handleRegularWithoutRetry(first, clients: [client], at: today))

        let nextDay = try review(at: tomorrow)
        XCTAssertNotEqual(second, nextDay)
        XCTAssertThrowsError(try store.handleRegularWithoutRetry(second, clients: [client], at: tomorrow))
        XCTAssertTrue(try store.loadForExecution().needsFightConfirmation(step.key))
        let handled = try store.handleRegularWithoutRetry(nextDay, clients: [client], at: tomorrow)
        XCTAssertTrue(handled.fightProgress?[step.key]?.isRegularManuallyHandled == true)
    }

    func testHandlingPreservesEvidenceWithoutSuccessAndIsScopedToTheDayAndStep() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fight-handling-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExecutionStateStore(directories: AppDirectories(root: root))
        let client = testClient
        let step = WorkflowStep(planID: UUID(), clientID: client.id, accountID: client.accounts[0].id, task: .fight)
        let other = WorkflowStep(planID: UUID(), clientID: step.clientID, accountID: step.accountID, task: .fight)
        let result = FightResult(status: .unconfirmed, stage: "PA-8", times: 2, reason: .interruptedBattle, kind: .regular)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(result, for: step.key)
        state.record(result, for: other.key)
        try store.save(state)
        let handled = try store.handleRegularWithoutRetry(step, expected: result, clients: [client])
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
        XCTAssertThrowsError(try store.handleRegularWithoutRetry(step, expected: result, clients: [client]))
        var nextRound = persisted
        nextRound.startRound(for: step.planID, at: Date())
        XCTAssertTrue(nextRound.fightProgress?[step.key]?.isRegularManuallyHandled == true)
        XCTAssertEqual(nextRound.fightProgress?[step.key]?.regular, result)
        XCTAssertFalse(nextRound.completedSteps.contains(step.key))
        XCTAssertFalse(nextRound.needsFightConfirmation(step.key))
        try store.save(nextRound)
        let tomorrow = Date().addingTimeInterval(86_400)
        let nextDay = try store.loadForExecution().forGameDays(of: [client], at: tomorrow)
        XCTAssertNil(nextDay.fightResults?[step.key])
        XCTAssertTrue(nextDay.needsFightConfirmation(other.key))
        XCTAssertThrowsError(try store.handleRegularWithoutRetry(step, expected: result, clients: [client], at: tomorrow))
    }

    func testHandlingRejectsRunningWorkflowStaleResultsAndAnnihilation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fight-handling-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root), store = ExecutionStateStore(directories: directories)
        let client = testClient
        let step = WorkflowStep(planID: UUID(), clientID: client.id, accountID: client.accounts[0].id, task: .fight)
        let result = FightResult(status: .unconfirmed, stage: "PA-8", reason: .missingEvidence)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(result, for: step.key)
        try store.save(state)
        let persisted = try store.loadForExecution()
        let lock = try ProcessLock(url: directories.lock)
        try withExtendedLifetime(lock) {
            XCTAssertThrowsError(try store.handleRegularWithoutRetry(step, expected: result, clients: [client]))
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

    private var testClient: ClientConfiguration {
        ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: "/test/Fake.app",
                            address: "127.0.0.1:65495", profileName: "manual-test",
                            bundleIdentifier: "dev.automaa.tests.manual", accounts: [AccountConfiguration(name: "测试账号")])
    }

    func testManualHandlingSummaryDoesNotCountAutomaticSuccess() {
        var report = WorkflowReport(totalSteps: 2)
        report.manuallyHandledSteps = 1
        XCTAssertEqual(report.runSummary?.completedSteps, 1)
        XCTAssertEqual(report.runSummary?.manuallyHandledSteps, 1)
        XCTAssertTrue(report.runSummary?.completionDescription.contains("已人工处理") == true)
    }

    func testStandaloneReviewIsNotARunAndRealRunsKeepTheirOriginalResults() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "fight-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(directories: .init(root: root))
        let plan = UUID(), run = UUID(), client = testClient
        let handled = WorkflowRunSummary(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0,
                                         totalSteps: 1, manuallyHandledSteps: 1)
        let original = LogEntry(level: .warning, message: "结果待核实", runID: UUID(), phase: .completed, planID: plan,
            runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1, unconfirmedSteps: 1))
        let legacy = LogEntry(level: .info, message: "已人工处理：今天不再重试本方案的常规作战；原始结果仍未确认",
            runID: UUID(), phase: .completed, planID: plan, clientID: client.id, accountID: client.accounts[0].id,
            task: .fight, runSummary: handled, fightResult: .init(status: .manuallyHandled))
        let realTask = LogEntry(level: .info, message: "今天已人工处理", runID: run, phase: .runningTask, planID: plan,
            clientID: client.id, accountID: client.accounts[0].id, task: .fight, fightResult: .init(status: .manuallyHandled))
        let terminal = LogEntry(level: .info, message: "本轮已处理", runID: run, phase: .completed, planID: plan, runSummary: handled)
        let maintenance = LogEntry(level: .info, message: "引擎更新", runID: UUID(), phase: .updating)
        let review = LogEntry(level: .info, message: "人工核实", manualFightDecision: true, planID: plan,
                              clientID: client.id, accountID: client.accounts[0].id, task: .fight, roundID: UUID())
        [original, legacy, realTask, terminal, maintenance, review].forEach(store.append)
        let sessions = ActivityHistory.sessions(from: store.load())
        XCTAssertEqual(Set(sessions.compactMap(\.runID)), Set([original.runID!, run, maintenance.runID!]))
        XCTAssertEqual(sessions.first { $0.runID == original.runID }?.runSummary, original.runSummary)
        XCTAssertEqual(sessions.first { $0.runID == run }?.entries.count, 2)
        _ = try store.clear(.maintenance)
        XCTAssertEqual(Set(store.load().filter(\.isManualFightDecision).map(\.id)), [legacy.id, review.id])
        XCTAssertTrue(try store.clear(.runs).isEmpty)
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
        XCTAssertEqual(continuation.completionTitle, "本轮已处理")
        XCTAssertEqual(state.fightProgress?[step.key]?.regular, original)
        XCTAssertFalse(state.completedSteps.contains(step.key))
    }
}
