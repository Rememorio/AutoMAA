import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Startup task ownership")
struct StartupTaskTests {
    @Test("account preparation selects the server without enabling Core lifecycle operations",
          arguments: ClientKind.allCases)
    func parameters(kind: ClientKind) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let account = AccountConfiguration(name: "测试账号", accountSelector: "  fixture-selector  ")
        let client = ClientConfiguration(name: "测试客户端", kind: kind, appPath: root.appending(path: "Test.app").path,
            address: "127.0.0.1:61388", profileName: "startup-test", bundleIdentifier: "dev.automaa.tests.startup",
            accounts: [account])
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [.lightRoutine, .completeRoutine])
        try MAAConfigurationWriter(directories: directories).prepare(config)
        let name = "\(client.id.uuidString.lowercased())-\(account.id.uuidString.lowercased())-startup"
        let data = try Data(contentsOf: directories.maaConfig.appending(path: "tasks/\(name).json"))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["client_type"] as? String == kind.maaClientType)
        let tasks = try #require(payload["tasks"] as? [[String: Any]])
        #expect(tasks.count == 1)
        #expect(tasks.first?["type"] as? String == "StartUp")
        let params = try #require(tasks.first?["params"] as? [String: Any])
        #expect(params["start_game_enabled"] as? Bool == false)
        #expect(params["client_type"] as? String == kind.maaTaskClientType)
        #expect(params["account_name"] as? String == (kind.supportsAccountSwitching ? "fixture-selector" : nil))
        #expect(params.count == (kind.supportsAccountSwitching ? 3 : 2))
        let manifest = try JSONDecoder().decode([String].self, from: Data(contentsOf: directories.generatedManifest))
        #expect(manifest.filter { $0.hasSuffix("-startup.json") } == ["tasks/\(name).json"])
    }

    @Test("startup cleanup preserves handwritten tasks even when the manifest is lost",
          arguments: [false, true])
    func cleanup(missingManifest: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-cleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let client = ClientConfiguration(name: "测试客户端", kind: .official, appPath: root.appending(path: "Test.app").path,
            address: "127.0.0.1:61388", profileName: "startup-test", bundleIdentifier: "dev.automaa.tests.startup",
            accounts: [AccountConfiguration(name: "测试账号")])
        var config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [.lightRoutine])
        let writer = MAAConfigurationWriter(directories: directories)
        try writer.prepare(config)
        let taskDirectory = directories.maaConfig.appending(path: "tasks")
        let before = try FileManager.default.contentsOfDirectory(atPath: taskDirectory.path)
        #expect(before.contains { $0.hasSuffix("-startup.json") })
        let manual = taskDirectory.appending(path: "my-startup.json")
        try Data("handwritten".utf8).write(to: manual)
        if missingManifest { try FileManager.default.removeItem(at: directories.generatedManifest) }
        config.clients = []
        try writer.prepare(config)
        #expect(try FileManager.default.contentsOfDirectory(atPath: taskDirectory.path) == ["my-startup.json"])
        #expect(try String(contentsOf: manual, encoding: .utf8) == "handwritten")
    }
}

func isStartupTask(arguments: [String], environment: [String: String]) throws -> Bool {
    guard arguments.first == "run", arguments.count > 1, let config = environment["MAA_CONFIG_DIR"] else { return false }
    let url = URL(filePath: config).appending(path: "tasks/\(arguments[1]).json")
    let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    return (payload?["tasks"] as? [[String: Any]])?.first?["type"] as? String == "StartUp"
}
