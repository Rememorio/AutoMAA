import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Schedule management")
struct ScheduleManagementTests {
    @Test("rapid schedule edits converge on the latest saved state")
    @MainActor
    func scheduleChangesAreSerialized() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-schedule-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        let runnerURL = URL(filePath: "/usr/bin/true")
        let model = AppModel(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            runnerExecutableURL: runnerURL
        )
        model.configuration.cliPath = "/usr/bin/true"
        model.configuration.clients = [ClientConfiguration(
            name: "测试客户端",
            kind: .official,
            appPath: root.appending(path: "Test.app").path,
            address: "127.0.0.1:61235",
            profileName: "test-client",
            bundleIdentifier: "dev.automaa.tests.game",
            accounts: [AccountConfiguration(name: "测试账号", accountSelector: "test-selector")]
        )]

        let lightID = model.configuration.plans[0].id
        model.setPlanScheduleEnabled(lightID, true)
        try await waitForScheduleSynchronization(model)

        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false
        )
        #expect(model.isPlanScheduleCurrent(model.configuration.plans[0]))
        #expect(manager.installedTime(planID: lightID)?.hour == 9)

        model.setPlanScheduleTime(lightID, hour: 10, minute: 15)
        model.setPlanScheduleTime(lightID, hour: 10, minute: 16)
        model.setPlanScheduleTime(lightID, hour: 10, minute: 17)
        try await waitForScheduleSynchronization(model)
        #expect(manager.installedTime(planID: lightID)?.hour == 10)
        #expect(manager.installedTime(planID: lightID)?.minute == 17)
        #expect(model.isPlanScheduleCurrent(model.configuration.plans[0]))

        let completeID = model.configuration.plans[1].id
        model.setPlanScheduleTime(completeID, hour: 10, minute: 17)
        model.setPlanScheduleEnabled(completeID, true)
        #expect(model.configuration.plans[1].schedule.enabled == false)
        #expect(model.bannerMessage?.contains("定时时间相同") == true)

        model.setPlanScheduleEnabled(lightID, false)
        model.setPlanScheduleEnabled(lightID, true)
        model.setPlanScheduleEnabled(lightID, false)
        try await waitForScheduleSynchronization(model)
        #expect(manager.isInstalled(planID: lightID) == false)
        #expect(model.configuration.plans[0].schedule.enabled == false)
    }

    @MainActor
    private func waitForScheduleSynchronization(_ model: AppModel) async throws {
        for _ in 0..<150 {
            if !model.isSynchronizingSchedules { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Schedule synchronization did not finish")
    }
}
