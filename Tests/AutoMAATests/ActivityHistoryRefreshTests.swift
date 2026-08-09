import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity history refresh")
struct ActivityHistoryRefreshTests {
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
}
