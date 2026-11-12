import Foundation
import Testing
@testable import AutoMAAKit

struct GameDayContinuationTests {
    private let evening = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!
    private let afterMidnight = ISO8601DateFormatter().date(from: "2026-11-08T16:05:00Z")!
    private let japanReset = ISO8601DateFormatter().date(from: "2026-11-08T19:00:00Z")!
    private let chinaReset = ISO8601DateFormatter().date(from: "2026-11-08T20:00:00Z")!

    @Test("a round survives local midnight and its remaining work expires by server")
    func resumesOnlyBeforeEachServerReset() throws {
        let china = client(.official, port: 65481)
        let japan = client(.yoStarJP, port: 65482)
        let clients = [china, japan]
        var plan = AutomationPlan.lightRoutine
        plan.fight.enabled = false
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        let done = WorkflowStep(planID: plan.id, clientID: china.id, accountID: china.accounts[0].id, task: .award)
        let configuration = AppConfiguration(clients: clients, plans: [plan])
        let legacy = ExecutionState(dateKey: ExecutionStateStore.dateKey(for: evening),
                                    completedSteps: [done.key], updatedAt: evening)
        let state = try JSONDecoder().decode(ExecutionState.self, from: JSONEncoder().encode(legacy))
        #expect(state.gameDayStarts == nil)
        var rebased = state.forGameDays(of: clients, at: afterMidnight)
        let round = rebased.startRound(for: plan.id, at: evening)
        rebased.completedSteps = [done.key]
        func progress(at date: Date) -> PlanContinuation {
            PlanContinuation(configuration: configuration, planID: plan.id, state: rebased, history: [],
                             now: date, roundID: round.id)
        }
        #expect(progress(at: afterMidnight).pendingItems.map(\.step.clientID) == [japan.id])
        #expect(progress(at: afterMidnight).resolved == 1)
        #expect(progress(at: japanReset).hasExpiredScope)
        #expect(progress(at: japanReset).pending == 0)
        #expect(progress(at: chinaReset).pending == 0)
        rebased = rebased.forGameDays(of: clients, at: chinaReset)
        rebased.startRound(for: plan.id, at: chinaReset)
        let next = PlanContinuation(configuration: configuration, planID: plan.id, state: rebased, history: [], now: chinaReset)
        #expect(next.pendingItems.map(\.step.clientID) == [china.id, japan.id])
    }

    @Test("an unresolved regular battle retains its exact target after the server resets")
    func pendingFightSurvivesRefresh() {
        let japan = client(.yoStarJP, port: 65482)
        let step = WorkflowStep(planID: UUID(), clientID: japan.id, accountID: japan.accounts[0].id, task: .fight)
        var state = ExecutionState().forGameDays(of: [japan], at: evening)
        let interrupted = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular)
        var progress = FightProgress(regularStage: "1-7")
        progress.regular = interrupted
        state.fightProgress = [step.key: progress]
        state.record(interrupted, for: step.key, at: evening)
        let nextDay = state.forGameDays(of: [japan], at: japanReset)
        #expect(nextDay.needsFightConfirmation(step.key))
        #expect(nextDay.fightProgress?[step.key]?.pendingStage == "1-7")
        #expect(!nextDay.isResolved(step.key))
    }

    private func client(_ kind: ClientKind, port: Int) -> ClientConfiguration {
        ClientConfiguration(name: "测试客户端", kind: kind, appPath: "/test/Fake.app", address: "127.0.0.1:\(port)",
                            profileName: "test-\(port)", bundleIdentifier: "dev.automaa.tests.game-day.\(port)",
                            accounts: [AccountConfiguration(name: "测试账号")])
    }
}
