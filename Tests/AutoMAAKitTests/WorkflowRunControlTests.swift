import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Workflow run control")
struct WorkflowRunControlTests {
    @Test("stale stop requests cannot stop a later run or a new lock owner")
    func staleRequestsAreIsolated() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-run-control-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let control = WorkflowRunControl(directories: directories)
        var lock: ProcessLock? = try ProcessLock(url: directories.lock)
        let first = WorkflowRunIdentity(runID: UUID(), planID: UUID(), lockID: try #require(lock).identity)
        try control.activate(first)
        try control.requestStop(for: first)
        #expect(control.isStopRequested(for: first))
        lock = nil
        lock = try ProcessLock(url: directories.lock)
        #expect(control.activeRun() == nil)
        #expect(throws: WorkflowRunControlError.self) { try control.requestStop(for: first) }

        let second = WorkflowRunIdentity(runID: UUID(), planID: first.planID, lockID: try #require(lock).identity)
        try control.activate(second)
        let delayedRequest = root.appending(path: "RunControl/stop-\(first.runID.uuidString.lowercased()).json")
        try JSONEncoder().encode(first).write(to: delayedRequest, options: .atomic)
        #expect(!control.isStopRequested(for: second))
        #expect(throws: WorkflowRunControlError.self) { try control.requestStop(for: first) }
        try control.requestStop(for: second)
        control.finish(first)
        #expect(control.activeRun() == second)
        #expect(control.isStopRequested(for: second))
        control.finish(second)
        #expect(control.activeRun() == nil)
        withExtendedLifetime(lock) {}
    }

    @Test("a disabled schedule is skipped by launchd but remains available to an explicit CLI run")
    func scheduledInvocationHonorsDisable() {
        var plan = AutomationPlan.lightRoutine
        plan.schedule.enabled = false
        #expect(!ScheduledWorkflowPolicy.mayRun(plan, environment: ["AUTOMAA_RUNNER_IDENTITY": "test"]))
        #expect(ScheduledWorkflowPolicy.mayRun(plan, environment: [:]))
        plan.schedule.enabled = true
        #expect(ScheduledWorkflowPolicy.mayRun(plan, environment: ["AUTOMAA_RUNNER_IDENTITY": "test"]))
    }

    @Test("a cooperative stop cancels the active command and closes the client before releasing the lock")
    @MainActor
    func cooperativeStopUsesWorkflowCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-run-stop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let app = root.appending(path: "Test.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let client = ClientConfiguration(name: "测试客户端", kind: .official, appPath: app.path,
            address: "127.0.0.1:61389", profileName: "stop-test", bundleIdentifier: "dev.automaa.tests.stop",
            accounts: [AccountConfiguration(name: "测试账号")])
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        plan.fight.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.recruit.enabled = false
        plan.award.enabled = true
        let configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let runtime = StopTestRuntime()
        let commands = StopTestCommands()
        let runner = WorkflowRunner(directories: directories, portProbe: runtime, gameController: runtime,
            shutdownPolicy: .init(maaGracePeriod: 0, systemGracePeriod: 0, forcedGracePeriod: 0),
            commandRunner: commands, eventSink: runtime.record)
        let task = Task { await runner.run(configuration, planID: plan.id) }
        defer { task.cancel() }
        for _ in 0..<500 {
            if await commands.didStartTask { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await commands.didStartTask)
        let control = WorkflowRunControl(directories: directories)
        let identity = try #require(control.activeRun())
        #expect(identity.planID == plan.id)
        try control.requestStop(for: identity)
        let report = await task.value
        #expect(report.cancelled)
        #expect(report.fatalError == nil)
        #expect(await commands.wasCancelled)
        #expect(runtime.terminationRequests > 0)
        #expect(!runtime.running)
        #expect(!runtime.portOpen)
        #expect(runtime.closedWhileLocked)
        #expect(!ProcessLock.isHeld(at: directories.lock))
        #expect(control.activeRun() == nil)
        #expect(ExecutionStateStore(directories: directories).loadForToday().completedSteps.isEmpty)
        #expect(runtime.lastPhase == .cancelled)
    }
}

private actor StopTestCommands: CommandRunning {
    private(set) var didStartTask = false
    private(set) var wasCancelled = false

    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool) async throws -> CommandResult {
        if arguments.first == "run" {
            didStartTask = true
            do { try await Task.sleep(for: .seconds(20)) }
            catch { wasCancelled = true; throw error }
        }
        return .init(exitCode: arguments.first == "dir" ? 1 : 0, standardOutput: "", standardError: "", timedOut: false)
    }
}

@MainActor
private final class StopTestRuntime: PortProbing, GameProcessControlling {
    var running = false
    var portOpen = false
    var terminationRequests = 0
    var closedWhileLocked = false
    var lastPhase: RunnerPhase?

    func isOpen(_ value: String, observeCancellation: Bool) async -> Bool { portOpen }

    func wait(forOpen shouldBeOpen: Bool, address: String, timeout: TimeInterval, observeCancellation: Bool) async -> Bool {
        if shouldBeOpen { running = true; portOpen = true }
        return portOpen == shouldBeOpen
    }

    func isRunning(_ client: ClientConfiguration) -> Bool { running }

    func terminate(_ client: ClientConfiguration, force: Bool) -> Bool {
        terminationRequests += 1
        running = false
        portOpen = false
        let root = URL(filePath: client.appPath).deletingLastPathComponent()
        closedWhileLocked = ProcessLock.isHeld(at: AppDirectories(root: root).lock)
        return true
    }

    func record(_ event: RunnerEvent) { lastPhase = event.phase }
}
