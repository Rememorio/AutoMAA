import AppKit
import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Application lifecycle")
struct ApplicationLifecycleTests {
    @Test("quitting distinguishes a cancellable workflow, update cleanup and an uncontrollable background run")
    func terminationActionsRespectCleanup() {
        let planID = UUID()
        #expect(action() == .terminate)
        #expect(action(running: true, cancellable: true, planID: planID) == .stopWorkflow)
        #expect(action(running: true, cancellable: true) == .cancelUpdate)
        #expect(action(running: true, cancelling: true, planID: planID) == .waitForCleanup)
        #expect(action(running: true, planID: planID) == .refuse)
        #expect(action(update: .checking) == .cancelUpdate)
        #expect(action(update: .restoring) == .cancelUpdate)
        #expect(action(update: .cancelling) == .waitForCleanup)
        #expect(action(update: .failed("test failure")) == .terminate)
    }

    @Test("the updater's authorized restart remains available while it holds the installation lock")
    func installationCanTerminate() throws {
        let release = try release()
        #expect(action(running: true, update: .installing(release)) == .terminate)
        #expect(action(update: .downloading(release)) == .cancelUpdate)
    }

    @Test("a quit request covers only the work and update that the user confirmed")
    func terminationDoesNotIncludeNewOperations() {
        let planID = UUID()
        let runID = UUID()
        let startedAt = Date()
        let workflow = ApplicationTerminationScope(workflow: .localPlan(planID, runID: runID), update: .none)
        #expect(workflow.contains(.init(workflow: .none, update: .none)))
        #expect(workflow.contains(.init(workflow: .localPlan(planID, runID: runID), update: .none)))
        #expect(!workflow.contains(.init(workflow: .localPlan(planID, runID: UUID()), update: .none)))
        #expect(!workflow.contains(.init(workflow: .maaUpdate(startedAt), update: .none)))

        let maintenance = ApplicationTerminationScope(workflow: .maaUpdate(startedAt), update: .none)
        #expect(!maintenance.contains(.init(workflow: .maaUpdate(startedAt.addingTimeInterval(1)), update: .none)))
        let update = ApplicationTerminationScope(workflow: .none, update: .running(startedAt))
        #expect(update.contains(.init(workflow: .none, update: .none)))
        #expect(!update.contains(.init(workflow: .none, update: .running(startedAt.addingTimeInterval(1)))))

        let identity = WorkflowRunIdentity(runID: runID, planID: planID, lockID: UUID())
        let external = ApplicationTerminationScope(workflow: .externalRun(identity), update: .none)
        #expect(external.contains(.init(workflow: .unidentified, update: .none)))
        #expect(!external.contains(.init(workflow: .externalRun(.init(runID: runID, planID: planID, lockID: UUID())), update: .none)))
    }

    @Test("ordinary termination flushes the latest configuration without terminating the test process")
    @MainActor
    func idleTerminationSavesPendingChanges() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let delegate = ApplicationDelegate()
        delegate.model = model
        model.configuration.plans[0].name = "退出前的新名称"

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(try ConfigurationStore(directories: model.directories).load() == model.configuration)
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @Test("a failed final save cancels termination and retains recoverable configuration")
    @MainActor
    func failedSaveCancelsTermination() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let delegate = ApplicationDelegate()
        delegate.model = model
        model.configuration.plans[0].name = "尚未保存的名称"
        try FileManager.default.removeItem(at: model.directories.configuration)
        try FileManager.default.createDirectory(at: model.directories.configuration, withIntermediateDirectories: false)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(model.configurationSaveError != nil)
        #expect(model.configuration.plans[0].name == "尚未保存的名称")
    }

    @Test("active application tracks external runs without a main window and resumes after activation")
    @MainActor
    func externalActivityMonitoringFollowsApplication() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let delegate = ApplicationDelegate()
        delegate.model = model
        let activated = Notification(name: NSApplication.didBecomeActiveNotification)
        let deactivated = Notification(name: NSApplication.didResignActiveNotification)
        defer { delegate.applicationDidResignActive(deactivated) }

        var lock: ProcessLock? = try ProcessLock(url: model.directories.lock)
        defer { withExtendedLifetime(lock) {} }
        #expect(!model.isExternalRunActive)
        delegate.applicationDidBecomeActive(activated)
        try await waitForExternalState(true, model: model)

        lock = nil
        try await waitForExternalState(false, model: model)
        delegate.applicationDidResignActive(deactivated)
        lock = try ProcessLock(url: model.directories.lock)
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(!model.isExternalRunActive)

        delegate.applicationDidBecomeActive(activated)
        try await waitForExternalState(true, model: model)
    }

    @MainActor
    private func waitForExternalState(_ active: Bool, model: AppModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isExternalRunActive != active, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.isExternalRunActive == active)
    }

    private func action(
        running: Bool = false,
        cancellable: Bool = false,
        cancelling: Bool = false,
        planID: UUID? = nil,
        update: ApplicationUpdateState = .idle
    ) -> ApplicationTerminationAction {
        ApplicationTerminationPolicy.action(
            isWorkflowRunning: running,
            canCancelRun: cancellable,
            isCancellingRun: cancelling,
            activePlanID: planID,
            applicationUpdateState: update
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "automaa-lifecycle-\(UUID())")
    }

    private func release() throws -> SoftwareUpdateRelease {
        let url = try #require(URL(string: "https://example.invalid/releases/v1.0.0"))
        let asset = SoftwareUpdateAsset(name: "test", size: 1, downloadURL: url)
        return SoftwareUpdateRelease(
            version: try #require(SoftwareVersion("1.0.0")), tagName: "v1.0.0",
            releaseNotes: "", pageURL: url, diskImage: asset, checksum: asset
        )
    }

    @MainActor
    private func makeModel(root: URL) -> AppModel {
        AppModel(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents"),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            allowsAutomaticMAAMaintenance: false,
            runnerExecutableURL: URL(filePath: "/usr/bin/true"),
            maaEnvironmentCheck: { _ in
                CommandResult(exitCode: 0, standardOutput: "test", standardError: "", timedOut: false)
            }
        )
    }
}
