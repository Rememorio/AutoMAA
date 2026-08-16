import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("MAA maintenance")
struct MAAMaintenanceTests {
    @Test("enabled automatic maintenance updates the stable channel while idle")
    @MainActor
    func enabledMaintenanceUpdatesWhileIdle() async throws {
        let fixture = try makeFixture(lastAttempt: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        fixture.model.prepareApplication()
        try await waitUntil {
            FileManager.default.fileExists(atPath: fixture.arguments.path)
                && !fixture.model.isWorkflowRunning
        }

        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8)
        let state = MAAMaintenanceStore(directories: fixture.model.directories).load()
        #expect(arguments == "update\nstable\n--test-time\n10\n--batch\n")
        #expect(state.lastCoreUpdateAttempt != nil)
        #expect(fixture.model.activityEntries.contains {
            $0.phase == .completed && $0.message == "MAA 核心与基础资源已更新"
        })
    }

    @Test("recent automatic maintenance is not repeated")
    @MainActor
    func recentMaintenanceIsNotRepeated() async throws {
        let fixture = try makeFixture(lastAttempt: Date())
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        fixture.model.prepareApplication()
        try await Task.sleep(for: .milliseconds(150))

        #expect(!FileManager.default.fileExists(atPath: fixture.arguments.path))
        #expect(!fixture.model.isWorkflowRunning)
    }

    @Test("automatic maintenance yields to an upcoming scheduled plan")
    @MainActor
    func maintenanceYieldsToUpcomingSchedule() async throws {
        let fixture = try makeFixture(lastAttempt: nil, scheduledRunAfter: 30 * 60)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        fixture.model.prepareApplication()
        try await Task.sleep(for: .milliseconds(150))

        #expect(!FileManager.default.fileExists(atPath: fixture.arguments.path))
        #expect(!fixture.model.isWorkflowRunning)
    }

    @MainActor
    private func makeFixture(
        lastAttempt: Date?,
        scheduledRunAfter interval: TimeInterval? = nil
    ) throws -> (root: URL, model: AppModel, arguments: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-maa-maintenance-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directories = AppDirectories(root: root)
        let cli = root.appending(path: "maa-cli")
        let arguments = directories.maaConfig.appending(path: "update-arguments.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("""
        #!/bin/sh
        if [ "$1" = "version" ]; then
          printf '%s\\n' 'maa-cli v0.7.5' 'MaaCore v9.9.9'
        elif [ "$1" = "update" ]; then
          printf '%s\\n' "$@" > "$MAA_CONFIG_DIR/update-arguments.txt"
        fi
        """.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        var configuration = AppConfiguration.defaults
        configuration.cliPath = cli.path
        configuration.maaUpdates.automaticallyUpdatesCoreAndResources = true
        if let interval {
            let runDate = Date().addingTimeInterval(interval)
            let components = Calendar.current.dateComponents([.hour, .minute], from: runDate)
            configuration.plans[0].schedule = .init(
                enabled: true,
                hour: components.hour ?? 0,
                minute: components.minute ?? 0
            )
        }
        try ConfigurationStore(directories: directories).save(configuration)
        try MAAMaintenanceStore(directories: directories).save(.init(
            lastCoreUpdateAttempt: lastAttempt
        ))
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false
        )
        return (root, model, arguments)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待 MAA 自动维护完成超时")
    }
}
