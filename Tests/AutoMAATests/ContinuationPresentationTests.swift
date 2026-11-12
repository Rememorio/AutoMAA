import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Continuation presentation")
struct ContinuationPresentationTests {
    @Test("a historical record offers one live follow-up only while related work remains")
    func historicalPendingLink() {
        let planID = UUID()
        let roundID = UUID()
        let run = ActivitySession(id: "partial", runID: UUID(), entries: [
            LogEntry(level: .warning, message: "部分完成", phase: .completed, planID: planID,
                     runSummary: .init(completedSteps: 10, failedSteps: 0, unexecutedSteps: 5, totalSteps: 15), roundID: roundID)
        ])
        var progress = PlanContinuation(configuration: .defaults, planID: planID, state: .init(), history: [])
        progress.hasStarted = true
        progress.roundID = roundID
        progress.pending = 5
        #expect(ActivityPendingLink(session: run, progress: progress) == .available("剩余 5 项"))
        progress.pending = 0
        #expect(ActivityPendingLink(session: run, progress: progress) == nil)
        progress.hasExpiredScope = true
        #expect(ActivityPendingLink(session: run, progress: progress) == .expired)
    }

    @Test("today summaries distinguish runnable work from review, blocked and empty states")
    func summaryGuidanceRespectsScope() {
        var progress = PlanContinuation(configuration: .defaults, planID: UUID(),
            state: .init(dateKey: "2000-01-01"), history: [])
        let empty = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(empty.title == "暂无可执行任务")
        #expect(!empty.needsAttention)
        #expect(empty.guidance == nil)

        progress.pending = 15
        let fresh = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(fresh.title == "今日尚未运行")
        #expect(fresh.guidance == nil)

        progress.hasStarted = true
        progress.pending = 5
        progress.resolved = 10
        progress.roundsToday = 2
        let partial = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(partial.title == "部分完成")
        #expect(partial.scope == "已处理 10/15 项")
        #expect(partial.rounds == "今日已运行 2 轮")
        #expect(partial.remaining == "剩余 5 项")
        #expect(partial.needsAttention)
        #expect(partial.guidance?.contains("从待办继续本轮") == true)
        #expect(partial.guidance?.contains("开启新一轮") == true)

        progress.pending = 4
        progress.unconfirmed = 1
        let review = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(review.scope == partial.scope)
        #expect(review.remaining == "剩余 4 项")
        #expect(review.review == "1 项待核实")
        #expect(review.guidance?.contains("待核实作战会保留") == true)
        for state in [PlanRunState.configurationIncomplete, .anotherPlanRunning, .maintenanceRunning, .running] {
            #expect(PlanRoundSummaryPresentation(progress: progress, runState: state).guidance == nil)
        }
        progress.pending = 0
        let onlyReview = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(onlyReview.title == "结果待核实")
        #expect(onlyReview.remaining == nil)
        #expect(onlyReview.guidance == nil)
    }

    @Test("today summaries retain manual handling instead of describing it as automatic completion")
    func summaryManualHandling() {
        var progress = PlanContinuation(configuration: .defaults, planID: UUID(),
            state: .init(dateKey: "2000-01-01"), history: [])
        progress.hasStarted = true
        progress.resolved = 1
        progress.manuallyHandled = 1
        progress.pending = 1
        #expect(PlanRoundSummaryPresentation(progress: progress, runState: .ready).title == "部分处理")
        progress.pending = 0
        let handled = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(handled.title == "本轮已处理")
        #expect(!handled.needsAttention)
        #expect(handled.guidance == nil)
    }

    @Test("continuation lists the exact remaining scope independently of history")
    @MainActor
    func weeklyOnlyContinuation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "continuation-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(directories: directories, launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                             managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false,
                             allowsAutomaticMAAMaintenance: false)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: root.appending(path: "Fake.app").path,
                                         address: "127.0.0.1:65491", profileName: "continuation-test",
                                         bundleIdentifier: "dev.automaa.tests.continuation", accounts: [account])
        var plan = AutomationPlan.lightRoutine
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.fight.weeklyAnnihilation.enabled = true
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        let round = state.startRound(for: plan.id, at: Date())
        var progress = FightProgress(regularStage: "1-7")
        progress.annihilation = .init(status: .unnecessary, reason: .insufficientSanity)
        progress.regular = .init(status: .completed, stage: "1-7", times: 3)
        state.fightProgress = [step.key: progress]
        state.record(progress.regular!, for: step.key)
        state.completedSteps.insert(WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .award).key)
        try ExecutionStateStore(directories: directories).save(state)
        var weekly = WeeklyAnnihilationState()
        weekly.record(progress.annihilation!, client: client, accountID: account.id,
                      weekStart: GameWeek(client: client.kind, at: Date()).start)
        try WeeklyAnnihilationStore(directories: directories).save(weekly)
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        model.reloadActivityHistory()
        #expect(model.runTitle(for: plan.id) == "运行一轮")
        #expect(model.runTitle(for: plan.id, request: .resume(roundID: round.id)) == "继续未完成")
        #expect(model.continuation(for: plan.id).pending == 1)
        #expect(model.continuation(for: plan.id).unconfirmed == 0)
        let pending = try #require(model.continuation(for: plan.id).pendingItems.first)
        #expect(pending.step == step)
        #expect(pending.targets == [.weeklyAnnihilation])
        #expect(pending.detail?.contains("理智不足") == true)
        #expect(model.continuation(for: plan.id).fightRecoveryItems.isEmpty)

        state.completedSteps.remove(WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .award).key)
        try ExecutionStateStore(directories: directories).save(state)
        model.reloadActivityHistory()
        #expect(model.continuation(for: plan.id).pendingItems.map(\.step.task) == [.fight, .award])

        state.record(.init(status: .unconfirmed, reason: .interruptedBattle), for: step.key)
        state.fightProgress?[step.key]?.regular = .init(status: .unconfirmed, reason: .interruptedBattle)
        try ExecutionStateStore(directories: directories).save(state)
        model.reloadActivityHistory()
        #expect(model.runTitle(for: plan.id, request: .resume(roundID: round.id)) == "继续其他任务")
        #expect(model.continuation(for: plan.id).pendingItems.map(\.step.task) == [.award])
        #expect(model.continuation(for: plan.id).fightRecoveryItems.map(\.step) == [step])
    }
}
