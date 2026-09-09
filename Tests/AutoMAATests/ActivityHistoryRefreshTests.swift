import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity history refresh")
struct ActivityHistoryRefreshTests {
    @Test("weekly recovery stays visible while other tasks run and confirmation never launches a workflow")
    @MainActor
    func weeklyRecoveryDoesNotDependOnRunCompletionOrHistory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-weekly-recovery-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(directories: directories, launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                             managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: root.appending(path: "Fake.app").path,
                                         address: "127.0.0.1:65491", profileName: "weekly-recovery",
                                         bundleIdentifier: "dev.automaa.tests.weekly-recovery", accounts: [account])
        var plan = AutomationPlan.lightRoutine
        plan.stepOrder = [.fight, .recruit]
        plan.fight.weeklyAnnihilation.enabled = true
        plan.fight.stageStrategy = .fixed
        plan.fight.stage = "1-7"
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        let now = Date()
        var weekly = WeeklyAnnihilationState()
        weekly.record(.init(status: .unconfirmed, reason: .navigationUnavailable), client: client, accountID: account.id,
                      weekStart: GameWeek(client: client.kind, at: now).start, at: now)
        let store = WeeklyAnnihilationStore(directories: directories)
        try store.save(weekly)
        weekly = try store.load()
        model.reloadActivityHistory()
        #expect(model.activityEntries.isEmpty)
        #expect(model.runTitle(for: plan.id) == "继续其他任务")
        #expect(model.continuation(for: plan.id).fightRecoveryItems.first?.canConfirmWeeklyCompletion == true)
        var lock: ProcessLock? = try ProcessLock(url: directories.lock)
        #expect(lock != nil)
        model.reloadActivityHistory()
        #expect(model.isWorkflowRunning)
        #expect(model.continuation(for: plan.id).fightRecoveryItems.map(\.step) == [step])
        model.confirmWeeklyAnnihilation(step)
        #expect(try store.load() == weekly)
        lock = nil
        model.reloadActivityHistory()
        model.confirmWeeklyAnnihilation(step)
        #expect(!model.isWorkflowRunning)
        #expect(model.activeRunID == nil)
        #expect(model.continuation(for: plan.id).fightRecoveryItems.isEmpty)
        #expect(model.continuation(for: plan.id).pending == 2)
        #expect(try store.load().status(for: plan.fight.weeklyAnnihilation, client: client, accountID: account.id) == .completed)
    }

    @Test("reloads activity written by the background runner")
    @MainActor
    func reloadsExternalHistory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-history-refresh-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false
        )
        let entry = LogEntry(
            level: .success,
            message: "定时方案已完成",
            runID: UUID(),
            phase: .completed,
            progress: 1,
            planID: model.configuration.plans[0].id
        )

        HistoryStore(directories: directories).append(entry)
        #expect(model.activityEntries.isEmpty)

        model.reloadActivityHistory()

        let loaded = try #require(model.activityEntries.first)
        #expect(model.activityEntries.count == 1)
        #expect(loaded.id == entry.id)
        #expect(loaded.runID == entry.runID)
        #expect(loaded.planID == entry.planID)
        #expect(loaded.phase == .completed)
        #expect(loaded.progress == 1)
        #expect(loaded.message == "定时方案已完成")
    }

    @Test("reflects a background runner while its process lock is held")
    @MainActor
    func reflectsBackgroundRunnerState() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-background-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false
        )
        let runID = UUID()
        let planID = model.configuration.plans[0].id
        let entry = LogEntry(
            level: .info,
            message: "正在执行定时方案",
            runID: runID,
            phase: .runningTask,
            progress: 0.5,
            planID: planID
        )
        var lock: ProcessLock? = try ProcessLock(url: directories.lock)
        #expect(lock != nil)
        HistoryStore(directories: directories).append(entry)

        model.reloadActivityHistory()

        #expect(model.isWorkflowRunning)
        #expect(model.isExternalRunActive)
        #expect(!model.canCancelRun)
        #expect(model.activeRunID == runID)
        #expect(model.activePlanID == planID)
        #expect(model.activePhase == .runningTask)
        #expect(model.activeStatusMessage == entry.message)
        #expect(model.activeProgress == 0.5)

        lock = nil
        model.reloadActivityHistory()

        #expect(!model.isWorkflowRunning)
        #expect(!model.isExternalRunActive)
    }

    @Test("does not present a previous session as the newly starting run")
    @MainActor
    func doesNotReusePreviousSessionForNewRun() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-background-start-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false
        )
        HistoryStore(directories: directories).append(LogEntry(
            timestamp: Date.now.addingTimeInterval(-60),
            level: .success,
            message: "上一次定时方案已完成",
            runID: UUID(),
            phase: .completed,
            progress: 1,
            planID: model.configuration.plans[0].id
        ))
        let lock = try ProcessLock(url: directories.lock)

        model.reloadActivityHistory()

        #expect(model.isExternalRunActive)
        #expect(model.activeRunID == nil)
        #expect(model.activePlanID == nil)
        #expect(model.activePhase == .preparing)
        #expect(model.activeStatusMessage == "定时任务正在启动")
        #expect(model.activeProgress == 0)
        withExtendedLifetime(lock) {}
    }
    @Test("recovery is derived from current state independently of history")
    @MainActor
    func recoveryUsesPersistedStateIndependentlyOfHistory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-recovery-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(directories: directories, launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                             managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: root.appending(path: "Fake.app").path,
                                         address: "127.0.0.1:65491", profileName: "recovery-test",
                                         bundleIdentifier: "dev.automaa.tests.recovery-ui", accounts: [account])
        var plan = AutomationPlan.lightRoutine
        plan.stepOrder = [.fight]
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        #expect(model.runTitle(for: plan.id) == "运行")
        let first = LogEntry(level: .info, message: "正在执行理智作战", phase: .runningTask,
                             planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        HistoryStore(directories: directories).append(first)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(FightResult(status: .unconfirmed), for: step.key)
        try ExecutionStateStore(directories: directories).save(state)
        model.reloadActivityHistory()
        #expect(model.runTitle(for: plan.id) == "结果待确认")
        #expect(model.continuation(for: plan.id).fightRecoveryItems.map(\.step) == [step])
        let last = LogEntry(level: .warning, message: "结果待确认", phase: .runningTask,
                            planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        HistoryStore(directories: directories).append(last)
        model.reloadActivityHistory()
        try HistoryStore(directories: directories).clear()
        model.reloadActivityHistory()
        #expect(model.continuation(for: plan.id).fightRecoveryItems.map(\.step) == [step])
        state.record(FightResult(status: .failed), for: step.key)
        try ExecutionStateStore(directories: directories).save(state)
        model.reloadActivityHistory()
        #expect(model.runTitle(for: plan.id) == "继续未完成")
        state.record(FightResult(status: .completed, times: 1), for: step.key)
        try ExecutionStateStore(directories: directories).save(state)
        model.reloadActivityHistory()
        #expect(model.runTitle(for: plan.id) == "今日已完成")
        #expect(model.continuation(for: plan.id).fightRecoveryItems.isEmpty)
    }

}
