import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Continuation presentation")
struct ContinuationPresentationTests {
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
        #expect(model.runTitle(for: plan.id) == "继续未完成")
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
        #expect(model.runTitle(for: plan.id) == "继续其他任务")
        #expect(model.continuation(for: plan.id).pendingItems.map(\.step.task) == [.award])
        #expect(model.continuation(for: plan.id).fightRecoveryItems.map(\.step) == [step])
    }
}
