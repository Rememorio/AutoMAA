import Foundation
import Testing
@testable import AutoMAAKit

struct ExecutionRoundTests {
    private let morning = ISO8601DateFormatter().date(from: "2026-11-10T21:00:00Z")!
    private let evening = ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }

    @Test("a new round resets only its plan and preserves unresolved fights and manual decisions")
    func startsIndependentRound() throws {
        let planID = UUID(), otherPlanID = UUID(), clientID = UUID()
        func key(_ plan: UUID, _ task: TaskKind = .fight) -> String {
            WorkflowStep(planID: plan, clientID: clientID, accountID: UUID(), task: task).key
        }
        let completed = key(planID, .award), other = key(otherPlanID, .award)
        let unknown = key(planID), handled = key(planID), unnecessary = key(planID)
        var state = ExecutionState(completedSteps: [completed, other])
        let first = state.startRound(for: planID, at: morning, calendar: calendar)
        state.completedSteps = [completed, other]
        let result = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular)
        state.record(result, for: unknown, at: morning)
        var progress = FightProgress(regularStage: "1-7")
        progress.regular = result
        progress.regularManuallyHandledAt = morning
        state.fightProgress = [handled: progress]
        state.record(progress.handledRegularResult!, for: handled, at: morning)
        state.record(.init(status: .unnecessary, reason: .insufficientSanity), for: unnecessary, at: morning)

        let second = state.startRound(for: planID, at: evening, calendar: calendar)
        #expect(first.id != second.id)
        #expect(second.number == 2)
        #expect(state.currentRound(for: planID) == second)
        #expect(state.completedSteps == [other])
        #expect(state.needsFightConfirmation(unknown))
        #expect(state.fightProgress?[handled]?.isRegularManuallyHandled == true)
        #expect(state.fightResults?[unnecessary] == nil)
        let decoded = try JSONDecoder().decode(ExecutionState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    @Test("round counts reset at local midnight without changing another plan")
    func countsRoundsPerPlanAndDate() {
        let plan = UUID(), other = UUID()
        var state = ExecutionState()
        let unchanged = state.startRound(for: other, at: morning, calendar: calendar)
        #expect(state.startRound(for: plan, at: morning, calendar: calendar).number == 1)
        #expect(state.startRound(for: plan, at: evening, calendar: calendar).number == 2)
        #expect(state.startRound(for: plan, at: evening.addingTimeInterval(86400), calendar: calendar).number == 1)
        #expect(state.currentRound(for: other) == unchanged)
    }

    @Test("a new round retains uncertain phases without inheriting successful phases")
    func preservesOnlyProtectedPhases() {
        let plan = UUID(), client = UUID()
        let regular = WorkflowStep(planID: plan, clientID: client, accountID: UUID(), task: .fight)
        let weekly = WorkflowStep(planID: plan, clientID: client, accountID: UUID(), task: .fight)
        let unknown = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular)
        let complete = FightResult(status: .completed, stage: "1-7", times: 1, kind: .regular)
        var first = FightProgress(regularStage: "1-7")
        first.regular = unknown
        first.annihilation = complete
        var second = FightProgress(regularStage: "1-7")
        second.regular = complete
        second.annihilation = .init(status: .unconfirmed, stage: "Annihilation", reason: .interruptedBattle, kind: .annihilation)
        var state = ExecutionState()
        state.fightProgress = [regular.key: first, weekly.key: second]
        state.record(unknown, for: regular.key, at: morning)
        state.record(second.annihilation!, for: weekly.key, at: morning)
        state.startRound(for: plan, at: morning, calendar: calendar)
        #expect(state.needsFightConfirmation(regular.key))
        #expect(state.needsFightConfirmation(weekly.key))
        #expect(!state.isResolved(regular.key))
        #expect(state.fightProgress?[regular.key]?.regular == unknown)
        #expect(state.fightProgress?[regular.key]?.annihilation == nil)
        #expect(state.fightProgress?[weekly.key]?.regular == nil)
        #expect(state.fightProgress?[weekly.key]?.annihilation?.status == .unconfirmed)
    }

    @Test("a superseded round cannot expose the current round's pending work")
    func rejectsArchivedRound() {
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .official, appPath: "/test/Fake.app",
                                         address: "127.0.0.1:65489", profileName: "round-test",
                                         bundleIdentifier: "dev.automaa.tests.round", accounts: [account])
        let plan = AutomationPlan.lightRoutine
        let configuration = AppConfiguration(clients: [client], plans: [plan])
        var state = ExecutionState().forGameDays(of: [client], at: morning)
        let first = state.startRound(for: plan.id, at: morning, calendar: calendar)
        let second = state.startRound(for: plan.id, at: evening, calendar: calendar)
        let archived = PlanContinuation(configuration: configuration, planID: plan.id, state: state, history: [],
                                        now: evening, calendar: calendar, roundID: first.id)
        #expect(archived.hasExpiredScope)
        #expect(!archived.hasPendingWork)
        #expect(archived.pendingItems.isEmpty)
        let current = PlanContinuation(configuration: configuration, planID: plan.id, state: state, history: [],
                                       now: evening, calendar: calendar, roundID: second.id)
        #expect(current.hasStarted)
        #expect(current.pending == plan.enabledTasks.count)
        #expect(current.roundsToday == 2)
    }
}
