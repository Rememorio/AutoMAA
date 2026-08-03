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
}
