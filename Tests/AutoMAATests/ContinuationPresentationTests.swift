@testable import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Continuation presentation")
struct ContinuationPresentationTests {
    @Test("the plan list shows the effective regular fight budget independently of selection and configured overrides")
    func regularFightListBudget() {
        var fight = FightConfiguration()
        #expect(fight.regularFightBudgetSummary == "自然理智")
        fight.stone = 0
        fight.medicine = 0
        fight.times = 4
        #expect(fight.regularFightBudgetSummary == "自然理智 · 每账号最多 4 次")
        fight.stone = 2
        fight.medicine = 5
        fight.medicineExpireDays = 2
        #expect(fight.regularFightBudgetSummary == "每账号源石最多 2 颗 · 理智药最多 5 瓶 · 使用 2 天内到期药 · 最多 4 次")
        fight.weeklyAnnihilation.enabled = true
        #expect(fight.regularFightBudgetSummary?.hasPrefix("常规 · 每账号源石最多 2 颗") == true)
        fight.usesCustomSettings = false
        #expect(fight.regularFightBudgetSummary == "常规 · 自然理智")
        fight.enabled = false
        #expect(fight.regularFightBudgetSummary == nil)
    }

    @Test("collapsed fight settings disclose configured resource limits and ignore inactive overrides")
    func collapsedFightSettings() {
        var fight = FightConfiguration()
        #expect(fight.advancedOptionsSummary == nil)
        fight.stone = 0
        fight.medicine = 3
        fight.medicineExpireDays = 2
        fight.fallbackStage = "1-7"
        #expect(fight.advancedOptionsSummary == "每账号源石最多 0 颗 · 理智药最多 3 瓶 · 使用 2 天内到期药 · 兜底 1-7")
        fight.usesCustomSettings = false
        #expect(fight.advancedOptionsSummary == nil)
        fight.usesCustomSettings = true
        #expect(fight.advancedOptionsSummary?.contains("源石最多 0 颗") == true)
    }

    @Test("pending accounts are scoped to a client and show each recoverable task once")
    func pendingAccounts() {
        let planID = UUID()
        let accountID = UUID()
        let fight = WorkflowStep(planID: planID, clientID: UUID(), accountID: accountID, task: .fight)
        let award = WorkflowStep(planID: planID, clientID: fight.clientID, accountID: accountID, task: .award)
        let other = WorkflowStep(planID: planID, clientID: UUID(), accountID: accountID, task: .fight)
        let pending = [other, fight, award].map {
            PendingWorkflowItem(step: $0, targets: [.task], reason: nil, lastFailure: nil)
        }
        let recovery = FightRecoveryItem(step: fight, result: .init(status: .failed),
                                         roundID: UUID(), clientKind: .yoStarJP, gameDayStart: Date(), weeklyAttempt: nil,
                                         canConfirmWeeklyCompletion: false, retryStage: "1-7", canHandleRegularWithoutRetry: false)
        let groups = PendingAccountWork.groups(items: pending, recovery: [recovery])
        #expect(groups.map(\.step) == [fight, other])
        #expect(groups.map { $0.tasks.map(\.step) } == [[award], [other]])
        #expect(groups.map { $0.recovery.map(\.step) } == [[fight], []])
    }

    @Test("today summaries distinguish runnable work from review, blocked and empty states")
    func summaryGuidanceRespectsScope() {
        var progress = PlanContinuation(configuration: .defaults, planID: UUID(),
            state: .init(dateKey: "2000-01-01"), history: [])
        let empty = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(empty.title == "暂无可执行任务")
        #expect(!empty.needsAttention)

        progress.pending = 15
        let fresh = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(fresh.title == "今日尚未运行")

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

        progress.pending = 4
        progress.unconfirmed = 1
        let review = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(review.scope == partial.scope)
        #expect(review.remaining == "剩余 4 项")
        #expect(review.review == "1 项待核实")
        progress.pending = 0
        let onlyReview = PlanRoundSummaryPresentation(progress: progress, runState: .ready)
        #expect(onlyReview.title == "结果待核实")
        #expect(onlyReview.remaining == nil)
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
    }

    @Test("confirming a regular fight keeps the diagnostic without adding a run")
    @MainActor
    func confirmingWithoutRetryPreservesHistory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "review-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(directories: directories, launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                             managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false,
                             allowsAutomaticMAAMaintenance: false)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: root.appending(path: "Fake.app").path,
                                         address: "127.0.0.1:65491", profileName: "review-history",
                                         bundleIdentifier: "dev.automaa.tests.review-history", accounts: [account])
        let plan = AutomationPlan.lightRoutine, now = Date()
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        let original = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular)
        var state = ExecutionState().forGameDays(of: [client], at: now)
        let round = state.startRound(for: plan.id, at: now)
        state.record(original, for: step.key, at: now)
        let stateStore = ExecutionStateStore(directories: directories)
        try stateStore.save(state)
        let run = LogEntry(level: .warning, message: "部分完成", runID: UUID(), phase: .completed, planID: plan.id,
                           runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                                             unconfirmedSteps: 1), roundID: round.id)
        HistoryStore(directories: directories).append(run)
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        model.reloadActivityHistory()
        let item = try #require(model.continuation(for: plan.id).fightRecoveryItems.first)
        model.handleRegularFightWithoutRetry(item)

        let logs = HistoryStore(directories: directories).load()
        let event = try #require(logs.first { $0.isManualFightDecision })
        #expect(event.roundID == round.id)
        #expect(event.runID == nil && event.phase == nil && event.runSummary == nil)
        #expect(event.fightResult?.status == .manuallyHandled)
        #expect(try stateStore.loadForExecution().fightProgress?[step.key]?.regular == original)
        let sessions = ActivityHistory.sessions(from: model.activityEntries)
        #expect(sessions.map(\.runID) == [run.runID])
        #expect(sessions.first?.runSummary == run.runSummary)
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
        #expect(model.runTitle(for: plan.id) == "运行新一轮")
        #expect(model.runTitle(for: plan.id, request: .resume(roundID: round.id)) == "继续本轮")
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
        #expect(model.runTitle(for: plan.id, request: .resume(roundID: round.id)) == "继续本轮")
        #expect(model.continuation(for: plan.id).pendingItems.map(\.step.task) == [.award])
        #expect(model.continuation(for: plan.id).fightRecoveryItems.map(\.step) == [step])
    }
}
