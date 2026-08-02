import Foundation
import Testing
import AutoMAAKit
@testable import AutoMAA

@Suite("Configuration naming")
struct ConfigurationNamingTests {
    @Test("new objects receive distinct editable names")
    @MainActor
    func generatedNamesAreDistinct() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-naming-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false
        )

        model.addClient()
        model.addClient()
        #expect(model.configuration.clients.map(\.name) == ["新客户端", "新客户端 2"])

        let clientID = try #require(model.configuration.clients.first?.id)
        model.addAccount(to: clientID)
        model.addAccount(to: clientID)
        #expect(model.configuration.clients[0].accounts.map(\.name) == ["新账号", "新账号 2"])

        model.addPlan(.lightRoutine)
        model.addPlan(.lightRoutine)
        #expect(Array(model.configuration.plans.map(\.name).suffix(2)) == ["轻量日常 2", "轻量日常 3"])
    }
}
