import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Plan task status")
struct PlanTaskStatusTests {
    @Test("a task succeeds only after every participating account has a successful daily checkpoint")
    func successRequiresEveryTarget() {
        var fixture = Fixture()
        var state = fixture.completed(.recruit, accounts: [0])
        let entries = [fixture.entry(level: .success)]
        #expect(fixture.snapshot(state: state, entries: entries).status(for: .recruit) == .none)
        #expect(fixture.snapshot(entries: [fixture.entry(level: .success),
                                          fixture.entry(account: 1, level: .success)]).status(for: .recruit) == .none)
        state.completedSteps.insert(fixture.step(.recruit, account: 1).key)
        #expect(fixture.snapshot(state: state).status(for: .recruit) == .success)

        fixture.plan.includesAllEnabledAccounts = false
        fixture.plan.accountIDs = [fixture.clients[0].accounts[0].id]
        #expect(fixture.snapshot(state: fixture.completed(.recruit, accounts: [0])).status(for: .recruit) == .success)
        fixture.plan.recruit.enabled = false
        #expect(fixture.snapshot(state: state).status(for: .recruit) == .none)
    }

    @Test("disabled clients and accounts do not participate and an empty scope never vacuously succeeds")
    func targetScopeUsesEnabledParticipants() {
        var fixture = Fixture()
        let state = fixture.completed(.recruit, accounts: [0])
        fixture.clients[0].accounts[1].enabled = false
        #expect(fixture.snapshot(state: state).status(for: .recruit) == .success)
        fixture.clients[0].enabled = false
        #expect(fixture.snapshot(state: state).status(for: .recruit) == .none)
        fixture.clients = []
        #expect(fixture.snapshot(state: state).status(for: .recruit) == .none)
    }

    @Test("yesterday's checkpoints and foreign plan or account events do not fill today's task status")
    func statusesRespectDayAndIdentity() {
        let fixture = Fixture()
        var state = fixture.completed(.recruit)
        state.dateKey = ExecutionStateStore.dateKey(for: fixture.now.addingTimeInterval(-86_400), calendar: fixture.calendar)
        var foreignPlan = fixture.entry(level: .error)
        foreignPlan.planID = UUID()
        var foreignClient = fixture.entry(level: .error)
        foreignClient.clientID = UUID()
        var foreignAccount = fixture.entry(level: .error)
        foreignAccount.accountID = UUID()
        let yesterday = fixture.entry(level: .error, at: fixture.now.addingTimeInterval(-86_400))
        #expect(fixture.snapshot(state: state, entries: [foreignPlan, foreignClient, foreignAccount, yesterday])
            .status(for: .recruit) == .none)
        state = fixture.emptyState
        state.completedSteps.insert(WorkflowStep(planID: UUID(), clientID: fixture.clients[0].id,
            accountID: fixture.clients[0].accounts[0].id, task: .recruit).key)
        #expect(fixture.snapshot(state: state).status(for: .recruit) == .none)
    }

    @Test("only the current run's latest overall event can animate a task")
    func runningFollowsTheActualTask() {
        let fixture = Fixture()
        let recruit = fixture.entry()
        let active = fixture.active()
        #expect(fixture.snapshot(entries: [recruit], activeRun: active).status(for: .recruit) == .running)
        let next = fixture.entry(task: .infrast)
        let snapshot = fixture.snapshot(entries: [recruit, next], activeRun: active)
        #expect(snapshot.status(for: .recruit) == .none)
        #expect(snapshot.status(for: .infrast) == .running)
        let switching = fixture.entry(task: nil, phase: .switchingAccount)
        #expect(fixture.snapshot(entries: [recruit, switching], activeRun: fixture.active(phase: .switchingAccount))
            .status(for: .recruit) == .none)
        #expect(fixture.snapshot(entries: [recruit], activeRun: fixture.active(runID: UUID()))
            .status(for: .recruit) == .none)
        let foreign = PlanTaskStatusSnapshot.ActiveRun(planID: UUID(), runID: fixture.runID, phase: .runningTask)
        #expect(fixture.snapshot(entries: [recruit], activeRun: foreign).status(for: .recruit) == .none)
        let unidentified = PlanTaskStatusSnapshot.ActiveRun(planID: fixture.plan.id, runID: nil, phase: .runningTask)
        #expect(fixture.snapshot(entries: [recruit], activeRun: unidentified).status(for: .recruit) == .none)
    }

    @Test("an active task remains identifiable across midnight without reusing yesterday's idle status")
    func activeRunCanSpanMidnight() {
        let fixture = Fixture()
        let start = fixture.entry(at: fixture.now.addingTimeInterval(-86_400))
        #expect(fixture.snapshot(entries: [start], activeRun: fixture.active()).status(for: .recruit) == .running)
        #expect(fixture.snapshot(entries: [start]).status(for: .recruit) == .none)
    }

    @Test("checkpoint skips do not animate and a newer attempt replaces an earlier task failure")
    func resolvedAndRetriedTasksDoNotKeepStaleFeedback() {
        let fixture = Fixture()
        let start = fixture.entry()
        #expect(fixture.snapshot(state: fixture.completed(.recruit, accounts: [0]), entries: [start],
                                 activeRun: fixture.active()).status(for: .recruit) == .none)
        let failed = fixture.entry(level: .error)
        #expect(fixture.snapshot(entries: [failed]).status(for: .recruit) == .failure)
        #expect(fixture.snapshot(entries: [failed, start], activeRun: fixture.active()).status(for: .recruit) == .running)
        #expect(fixture.snapshot(entries: [failed, fixture.entry(level: .success)]).status(for: .recruit) == .none)
        #expect(fixture.snapshot(state: fixture.completed(.recruit), entries: [failed]).status(for: .recruit) == .success)
    }

    @Test("cancellation belongs to the unfinished task and preserves earlier successful tasks")
    func cancellationDoesNotBecomeCompletionOrAffectUnstartedTasks() {
        let fixture = Fixture()
        let state = fixture.completed(.recruit)
        let entries = [fixture.entry(level: .success), fixture.entry(account: 1, level: .success),
                       fixture.entry(task: .infrast), fixture.entry(task: nil, phase: .cancelled)]
        let snapshot = fixture.snapshot(state: state, entries: entries)
        #expect(snapshot.status(for: .recruit) == .success)
        #expect(snapshot.status(for: .infrast) == .cancelled)
        #expect(snapshot.status(for: .award) == .none)
        let cancelling = fixture.active(phase: .closing, isCancelling: true)
        #expect(fixture.snapshot(entries: [fixture.entry()], activeRun: cancelling).status(for: .recruit) == .cancelled)
        #expect(fixture.snapshot(entries: [fixture.entry(level: .success),
                                          fixture.entry(task: nil, phase: .cancelled)]).status(for: .recruit) == .none)
        #expect(fixture.snapshot(entries: [fixture.entry(), fixture.entry(task: nil, level: .success, phase: .cancelled)])
            .status(for: .recruit) == .cancelled)
    }

    @Test("later runs replace cancellation feedback and terminal task failures remain failures")
    func interruptionsRespectTheLatestAttempt() {
        let fixture = Fixture()
        let cancelled = [fixture.entry(), fixture.entry(task: nil, phase: .cancelled)]
        let later = fixture.entry(runID: UUID())
        #expect(fixture.snapshot(entries: cancelled + [later]).status(for: .recruit) == .none)
        #expect(fixture.snapshot(entries: [fixture.entry(), fixture.entry(task: nil, level: .error, phase: .failed)])
            .status(for: .recruit) == .failure)
        #expect(fixture.snapshot(entries: [fixture.entry(level: .error), fixture.entry(task: nil, phase: .cancelled)])
            .status(for: .recruit) == .failure)
        var state = fixture.emptyState
        state.record(.init(status: .failed), for: fixture.step(.fight).key, at: fixture.now)
        #expect(fixture.snapshot(state: state, entries: [fixture.entry(task: .fight, level: .error, runID: UUID()),
            fixture.entry(task: .fight),
            fixture.entry(task: nil, phase: .cancelled)]).status(for: .fight) == .cancelled)
    }

    @Test("fight confirmation, manual handling and unnecessary work never claim automatic success")
    func fightResultsRetainTheirMeaning() {
        let fixture = Fixture()
        var state = fixture.emptyState
        for result in [FightResult(status: .unconfirmed), .init(status: .manuallyHandled)] {
            state.record(result, for: fixture.step(.fight).key, at: fixture.now)
            #expect(fixture.snapshot(state: state).status(for: .fight) == .attention)
        }
        state.record(.init(status: .failed), for: fixture.step(.fight).key, at: fixture.now)
        #expect(fixture.snapshot(state: state).status(for: .fight) == .failure)
        for index in [0, 1] { state.record(.init(status: .unnecessary), for: fixture.step(.fight, account: index).key, at: fixture.now) }
        #expect(fixture.snapshot(state: state).status(for: .fight) == .none)
        state.record(.init(status: .unnecessary, reason: .navigationUnavailable), for: fixture.step(.fight).key, at: fixture.now)
        #expect(fixture.snapshot(state: state).status(for: .fight) == .attention)
        #expect(fixture.snapshot(state: fixture.completed(.fight)).status(for: .fight) == .success)
    }

    @Test("weekly annihilation invalidates an old completed fight checkpoint without resurrecting it from logs")
    func weeklyPendingWorkPreventsAGreenCheck() {
        var fixture = Fixture()
        fixture.plan.fight.weeklyAnnihilation.enabled = true
        let state = fixture.completed(.fight)
        let entries = [fixture.entry(task: .fight, level: .success,
                                    fightResult: .init(status: .completed)),
                       fixture.entry(task: .fight, account: 1, level: .success,
                                    fightResult: .init(status: .completed))]
        #expect(fixture.snapshot(state: state, entries: entries).status(for: .fight) == .none)
    }

    private struct Fixture {
        var plan = AutomationPlan.lightRoutine
        var clients: [ClientConfiguration]
        let runID = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!
        var calendar: Calendar {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            return value
        }
        var emptyState: ExecutionState {
            .init(dateKey: ExecutionStateStore.dateKey(for: now, calendar: calendar), updatedAt: now)
        }

        init() {
            let root = FileManager.default.temporaryDirectory.appending(path: "automaa-task-status-\(UUID())")
            clients = [.init(name: "演示客户端", kind: .official,
                appPath: root.appending(path: "Fixture.app").path, address: "127.0.0.1:61397",
                profileName: "task-status-fixture", bundleIdentifier: "dev.automaa.tests.task-status", accounts: [
                    .init(name: "演示账号 A", accountSelector: "TEST-A"),
                    .init(name: "演示账号 B", accountSelector: "TEST-B")
                ])]
        }

        func step(_ task: TaskKind, account: Int = 0) -> WorkflowStep {
            .init(planID: plan.id, clientID: clients[0].id, accountID: clients[0].accounts[account].id, task: task)
        }

        func completed(_ task: TaskKind, accounts: [Int] = [0, 1]) -> ExecutionState {
            var state = emptyState
            for index in accounts {
                if task == .fight { state.record(.init(status: .completed), for: step(task, account: index).key, at: now) }
                else { state.completedSteps.insert(step(task, account: index).key) }
            }
            return state
        }

        func active(phase: RunnerPhase = .runningTask, runID: UUID? = nil,
                    isCancelling: Bool = false) -> PlanTaskStatusSnapshot.ActiveRun {
            .init(planID: plan.id, runID: runID ?? self.runID, phase: phase, isCancelling: isCancelling)
        }

        func entry(task: TaskKind? = .recruit, account: Int = 0, level: LogLevel = .info,
                   phase: RunnerPhase = .runningTask, runID: UUID? = nil, at date: Date? = nil,
                   fightResult: FightResult? = nil) -> LogEntry {
            .init(timestamp: date ?? now, level: level, message: "演示任务事件", runID: runID ?? self.runID,
                  phase: phase, planID: plan.id, clientID: clients[0].id,
                  accountID: clients[0].accounts[account].id, task: task, fightResult: fightResult)
        }

        func snapshot(state: ExecutionState? = nil, entries: [LogEntry] = [],
                      activeRun: PlanTaskStatusSnapshot.ActiveRun? = nil) -> PlanTaskStatusSnapshot {
            .init(plan: plan, clients: clients, state: state ?? emptyState, entries: entries,
                  activeRun: activeRun, now: now, calendar: calendar)
        }
    }
}
