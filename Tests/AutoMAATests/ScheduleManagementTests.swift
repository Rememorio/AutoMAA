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
        let firstRuleID = model.configuration.plans[0].schedule.rules[0].id
        #expect(manager.installedSlots(planID: lightID) == Set(ScheduleWeekday.allCases.map {
            WeeklyScheduleSlot(weekday: $0, hour: 9, minute: 0)
        }))

        model.setPlanScheduleRuleTime(lightID, ruleID: firstRuleID, hour: 10, minute: 15)
        model.setPlanScheduleRuleTime(lightID, ruleID: firstRuleID, hour: 10, minute: 16)
        model.setPlanScheduleRuleTime(lightID, ruleID: firstRuleID, hour: 10, minute: 17)
        try await waitForScheduleSynchronization(model)
        #expect(manager.installedSlots(planID: lightID)?.contains(
            WeeklyScheduleSlot(weekday: .monday, hour: 10, minute: 17)
        ) == true)
        #expect(model.isPlanScheduleCurrent(model.configuration.plans[0]))

        model.togglePlanScheduleWeekday(lightID, ruleID: firstRuleID, weekday: .sunday)
        model.addPlanScheduleRule(lightID)
        let sundayRuleID = try #require(model.configuration.plans[0].schedule.rules.last?.id)
        model.setPlanScheduleRuleTime(lightID, ruleID: sundayRuleID, hour: 21, minute: 0)
        try await waitForScheduleSynchronization(model)
        #expect(manager.installedSlots(planID: lightID)?.contains(
            WeeklyScheduleSlot(weekday: .sunday, hour: 21, minute: 0)
        ) == true)
        #expect(PlanScheduleFormatter.summary(model.configuration.plans[0].schedule) == "周一至周六 10:17；周日 21:00")

        let completeID = model.configuration.plans[1].id
        let completeRuleID = model.configuration.plans[1].schedule.rules[0].id
        model.setPlanScheduleRuleTime(completeID, ruleID: completeRuleID, hour: 10, minute: 17)
        model.setPlanScheduleEnabled(completeID, true)
        #expect(model.configuration.plans[1].schedule.enabled == false)
        #expect(model.bannerMessage?.contains("周一定时运行冲突") == true)

        model.setPlanScheduleEnabled(lightID, false)
        model.setPlanScheduleEnabled(lightID, true)
        model.setPlanScheduleEnabled(lightID, false)
        try await waitForScheduleSynchronization(model)
        #expect(manager.isInstalled(planID: lightID) == false)
        #expect(model.configuration.plans[0].schedule.enabled == false)
    }

    @Test("schedule refresh waits for a running workflow to release its lock")
    @MainActor
    func scheduleRefreshWaitsForWorkflowLock() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-schedule-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var configuration = AppConfiguration.defaults
        configuration.plans[0].schedule.enabled = true
        try ConfigurationStore(directories: directories).save(configuration)
        var lock: ProcessLock? = try ProcessLock(url: directories.lock)
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: launchAgents,
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            runnerExecutableURL: URL(filePath: "/usr/bin/true")
        )
        let planID = configuration.plans[0].id

        model.prepareApplication()
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.isSynchronizingSchedules)
        #expect(!FileManager.default.fileExists(atPath: launchAgents.path))

        lock = nil
        try await waitForScheduleSynchronization(model)

        #expect(lock == nil)
        #expect(model.installedPlanIDs.contains(planID))
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
