import Foundation
import Testing
@testable import AutoMAAKit

@Suite("LaunchAgent system responses")
struct LaunchAgentTimeoutTests {
    @Test("an interrupted install keeps the label discoverable and does not mark the schedule current")
    func interruptedInstall() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = LaunchAgentManager(directories: AppDirectories(root: root),
                                        launchAgentsDirectory: root.appending(path: "LaunchAgents")) { arguments in
            .init(exitCode: 0, standardOutput: "", standardError: "", timedOut: arguments.first == "bootstrap")
        }
        var plan = AutomationPlan.lightRoutine
        plan.schedule.enabled = true
        let runner = URL(filePath: "/usr/bin/true")
        await #expect(throws: LaunchAgentError.systemTimeout("注册")) {
            try await manager.install(runnerURL: runner, plan: plan)
        }
        #expect(manager.installedPlanIDs.contains(plan.id))
        #expect(!manager.isCurrent(runnerURL: runner, plan: plan))
        try await manager.uninstall(planID: plan.id)
        #expect(!manager.isInstalled(planID: plan.id))
    }

    @Test("an unconfirmed unload preserves its plist until the service is known to be absent",
          arguments: ["unloadTimeout", "queryTimeout", "missing", "unknown"])
    func unloadRecovery(scenario: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "LaunchAgents")
        let directories = AppDirectories(root: root)
        let fixture = LaunchAgentManager(directories: directories, launchAgentsDirectory: directory, systemIntegrationEnabled: false)
        let plan = AutomationPlan.lightRoutine
        try await fixture.install(runnerURL: URL(filePath: "/usr/bin/true"), plan: plan)
        let label = fixture.label(planID: plan.id)
        let manager = LaunchAgentManager(directories: directories, launchAgentsDirectory: directory) { arguments in
            if arguments.first == "bootout" {
                return .init(exitCode: 1, standardOutput: "", standardError: "bootout", timedOut: scenario == "unloadTimeout")
            }
            let message = scenario == "missing" ? "Could not find service \"\(label)\" in domain for user gui" : "query failed"
            return .init(exitCode: 113, standardOutput: "", standardError: message, timedOut: scenario == "queryTimeout")
        }
        if scenario == "missing" {
            try await manager.uninstall(planID: plan.id)
            #expect(!manager.isInstalled(planID: plan.id))
        } else {
            await #expect(throws: (any Error).self) { try await manager.uninstall(planID: plan.id) }
            #expect(manager.isInstalled(planID: plan.id))
        }
    }
}
