import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@MainActor
@Suite("Dashboard run controls")
struct DashboardRunControlsTests {
    @Test("the card stops the identified workflow and disables stopping during cleanup")
    func stopsWorkflowFromCard() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let lock = try ProcessLock(url: fixture.model.directories.lock)
        let identity = WorkflowRunIdentity(runID: UUID(), planID: fixture.model.configuration.plans[0].id, lockID: lock.identity)
        let control = WorkflowRunControl(directories: fixture.model.directories)
        try control.activate(identity)
        defer { control.finish(identity); withExtendedLifetime(lock) {} }
        fixture.model.reloadActivityHistory()
        let controls = WorkspaceRunControlState(model: fixture.model)
        #expect(!fixture.model.isMAAMaintenanceRunning)
        #expect(controls.canStop)
        controls.openOperation(in: fixture.model)
        #expect(fixture.model.activitySelection == .plan(identity.planID))
        controls.stopWorkflow(in: fixture.model)
        #expect(control.isStopRequested(for: identity))
        #expect(fixture.model.isCancellingRun)
        #expect(!WorkspaceRunControlState(model: fixture.model).canStop)
    }

    @Test("maintenance navigation selects its settings without stopping the update")
    func maintenanceOpensEnvironment() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        fixture.model.hotUpdate()
        let controls = WorkspaceRunControlState(model: fixture.model)
        #expect(fixture.model.isMAAMaintenanceRunning)
        controls.openOperation(in: fixture.model)
        #expect(fixture.model.settingsSection == .environment)
        #expect(fixture.model.selection == .overview)
        #expect(!fixture.model.isCancellingRun)
        controls.stopWorkflow(in: fixture.model)
        #expect(!fixture.model.isCancellingRun)
        fixture.model.cancelRun()
        #expect(fixture.model.maaUpdateActivity?.isCancelling == true)
        try await fixture.waitForCancellation()
    }

    @Test("an unidentified background run stays a workflow with an unavailable safe stop")
    func unidentifiedRunDoesNotBecomeMaintenance() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let lock = try ProcessLock(url: fixture.model.directories.lock)
        defer { withExtendedLifetime(lock) {} }
        fixture.model.reloadActivityHistory()
        let controls = WorkspaceRunControlState(model: fixture.model)
        #expect(!fixture.model.isMAAMaintenanceRunning)
        #expect(!controls.canStop)
        controls.stopWorkflow(in: fixture.model)
        #expect(!fixture.model.isCancellingRun)
        controls.openOperation(in: fixture.model)
        #expect(fixture.model.selection == .activity)
    }

    @Test("a stop action retained from an ended workflow cannot cancel newly started maintenance")
    func staleWorkflowStopPreservesMaintenance() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        var lock: ProcessLock? = try ProcessLock(url: fixture.model.directories.lock)
        let identity = WorkflowRunIdentity(runID: UUID(), planID: fixture.model.configuration.plans[0].id,
                                          lockID: try #require(lock).identity)
        let control = WorkflowRunControl(directories: fixture.model.directories)
        try control.activate(identity)
        fixture.model.reloadActivityHistory()
        let controls = WorkspaceRunControlState(model: fixture.model)
        #expect(controls.canStop)
        control.finish(identity)
        lock = nil
        fixture.model.reloadActivityHistory()
        fixture.model.hotUpdate()
        controls.stopWorkflow(in: fixture.model)
        #expect(fixture.model.isMAAMaintenanceRunning)
        #expect(!fixture.model.isCancellingRun)
        fixture.model.cancelRun()
        try await fixture.waitForCancellation()
    }

    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-dashboard-controls-\(UUID())")
        let model: AppModel

        init() {
            model = AppModel(directories: AppDirectories(root: root),
                launchAgentsDirectory: root.appending(path: "LaunchAgents"), managesSystemLaunchAgents: false,
                checksForUpdatesAutomatically: false, allowsAutomaticMAAMaintenance: false,
                runnerExecutableURL: URL(filePath: "/usr/bin/true"), resourceProbeExecutable: URL(filePath: "/usr/bin/true"))
            model.configuration.cliPath = "/usr/bin/true"
            model.selection = .overview
        }

        func waitForCancellation() async throws {
            // Callers cancel before yielding so no maintenance command is dispatched.
            for _ in 0..<500 where model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            #expect(!model.isWorkflowRunning)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
