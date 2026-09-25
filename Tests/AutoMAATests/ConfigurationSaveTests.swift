import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Configuration saving")
struct ConfigurationSaveTests {
    @Test("save failures remain visible until a successful retry persists the edits")
    @MainActor
    func retryFailedSave() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: root.appending(path: "LaunchAgents"),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            allowsAutomaticMAAMaintenance: false
        )
        model.configuration.plans[0].name = "保存测试"
        try FileManager.default.removeItem(at: directories.configuration)
        try FileManager.default.createDirectory(at: directories.configuration, withIntermediateDirectories: false)
        #expect(!model.saveNow(showConfirmation: false))
        #expect(model.configurationSaveError != nil)
        model.bannerMessage = nil
        #expect(model.configurationSaveError != nil)
        #expect(model.configuration.plans[0].name == "保存测试")

        try FileManager.default.removeItem(at: directories.configuration)
        #expect(model.saveNow(showConfirmation: false))
        #expect(model.configurationSaveError == nil)
        #expect(try ConfigurationStore(directories: directories).load().plans[0].name == "保存测试")
    }
}
