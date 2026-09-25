import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

private actor ControlledEnvironmentCheck {
    private var pending: [Int: CheckedContinuation<CommandResult, any Error>] = [:]
    private var nextID = 0
    private(set) var returned: Set<Int> = []

    func check(_ path: String) async throws -> CommandResult {
        let id = nextID
        nextID += 1
        let result = try await withCheckedThrowingContinuation { pending[id] = $0 }
        returned.insert(id)
        return result
    }

    func isPending(_ id: Int) -> Bool { pending[id] != nil }

    func complete(_ id: Int, output: String) {
        pending.removeValue(forKey: id)?.resume(returning: .init(
            exitCode: 0, standardOutput: output, standardError: "", timedOut: false))
    }
}

@Suite("MAA environment feedback")
struct MAAEnvironmentTests {
    @Test("changing the CLI path invalidates its detected version")
    @MainActor
    func pathChangeInvalidatesVersion() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let checker = ControlledEnvironmentCheck()
        let model = makeModel(root: root, checker: checker)
        model.configuration.cliPath = "/usr/bin/true"
        model.refreshMAAStatus()
        try await waitUntil { await checker.isPending(0) }
        await checker.complete(0, output: "测试环境 A")
        try await waitUntil { !model.isCheckingMAAEnvironment }
        #expect(model.maaVersionSummary == "测试环境 A")

        model.configuration.cliPath = "/usr/bin/false"

        #expect(model.maaVersionSummary == "尚未检测")
        #expect(!model.isCheckingMAAEnvironment)
    }

    @Test("a superseded check cannot overwrite the active path or a newer result", arguments: [false, true])
    @MainActor
    func lateResultIsIgnored(returnToOriginalPath: Bool) async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let checker = ControlledEnvironmentCheck()
        let model = makeModel(root: root, checker: checker)
        model.configuration.cliPath = "/usr/bin/true"
        model.refreshMAAStatus(showResult: true)
        try await waitUntil { await checker.isPending(0) }

        model.configuration.cliPath = "/usr/bin/false"
        #expect(!model.isCheckingMAAEnvironment)
        #expect(model.maaVersionSummary == "尚未检测")
        if returnToOriginalPath { model.configuration.cliPath = "/usr/bin/true" }
        model.refreshMAAStatus()
        try await waitUntil { await checker.isPending(1) }
        await checker.complete(1, output: "当前环境")
        try await waitUntil { !model.isCheckingMAAEnvironment }
        #expect(model.maaVersionSummary == "当前环境")

        await checker.complete(0, output: "过期环境")
        try await waitUntil { await checker.returned.contains(0) }
        await Task.yield()
        #expect(model.maaVersionSummary == "当前环境")
        #expect(model.bannerMessage == nil)
        #expect(!model.isCheckingMAAEnvironment)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "automaa-environment-\(UUID())")
    }

    @MainActor
    private func makeModel(root: URL, checker: ControlledEnvironmentCheck) -> AppModel {
        AppModel(directories: AppDirectories(root: root),
                 launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                 managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false,
                 allowsAutomaticMAAMaintenance: false,
                 maaEnvironmentCheck: { try await checker.check($0) })
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待环境检测状态超时")
    }
}
