import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Client ownership")
struct ClientOwnershipTests {
    @Test("an existing client blocks the whole workflow regardless of server or order",
          arguments: [false, true], [ClientKind.official, .yoStarJP])
    @MainActor
    func externalClient(reverse: Bool, occupiedKind: ClientKind) async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        if reverse { fixture.configuration.clients.reverse() }
        let occupied = try #require(fixture.configuration.clients.first { $0.kind == occupiedKind })
        fixture.runtime.running.insert(occupied.id)
        fixture.runtime.portOpen = true
        let report = await fixture.run()
        #expect(report.fatalError != nil)
        #expect(report.succeededSteps == 0)
        #expect(fixture.runtime.running == [occupied.id])
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.isEmpty)
        #expect(!fixture.runtime.events.contains { $0.phase == .switchingAccount || $0.phase == .closing })
    }

    @Test("a running client without a listener, an unknown listener, and failed inspection all block startup",
          arguments: [0, 1, 2])
    @MainActor
    func unavailableBeforeStartup(scenario: Int) async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        if scenario == 0 { fixture.runtime.running.insert(fixture.configuration.clients[0].id) }
        if scenario == 1 { fixture.runtime.portOpen = true; fixture.runtime.portOwner = 61_499 }
        if scenario == 2 { fixture.runtime.inspectionFails = true }
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 0)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.isEmpty)
    }

    @Test("preflight preserves checkpoints and avoids resource updates even when restarting the plan")
    @MainActor
    func preflightPrecedesMutations() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.configuration.plans[0].policy.hotUpdateBeforeRun = true
        let client = fixture.configuration.clients[0]
        let key = WorkflowStep(planID: fixture.configuration.plans[0].id,
            clientID: client.id, accountID: client.accounts[0].id, task: .award).key
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.completedSteps.insert(key)
        try ExecutionStateStore(directories: fixture.directories).save(state)
        let before = try Data(contentsOf: fixture.directories.executionState)
        fixture.runtime.running.insert(client.id)
        fixture.runtime.portOpen = true
        #expect(await fixture.run(resumeToday: false).fatalError != nil)
        #expect(try Data(contentsOf: fixture.directories.executionState) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.directories.generatedManifest.path))
        #expect(await fixture.commands.commands.isEmpty)
    }

    @Test("a client excluded from the plan still protects a shared port")
    @MainActor
    func excludedClient() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.configuration.plans[0].includesAllEnabledAccounts = false
        fixture.configuration.plans[0].accountIDs = [fixture.configuration.clients[0].accounts[0].id]
        fixture.configuration.clients[1].enabled = false
        fixture.runtime.running.insert(fixture.configuration.clients[1].id)
        fixture.runtime.portOpen = true
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 0)
        #expect(await fixture.commands.gameCommands.isEmpty)
    }

    @Test("a completed plan does not inspect or touch an externally running game")
    @MainActor
    func completedPlan() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        for client in fixture.configuration.clients {
            state.completedSteps.insert(WorkflowStep(planID: fixture.configuration.plans[0].id,
                clientID: client.id, accountID: client.accounts[0].id, task: .award).key)
        }
        try ExecutionStateStore(directories: fixture.directories).save(state)
        fixture.runtime.inspectionFails = true
        fixture.runtime.running.insert(fixture.configuration.clients[0].id)
        #expect(await fixture.run().isSuccess)
        #expect(fixture.runtime.inspections == 0)
        #expect(fixture.runtime.launches == 0)
    }

    @Test("an external launch after preflight is rejected before any game command")
    @MainActor
    func occupiedAfterPreflight() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.onEvent = { event in
            if event.phase == .launching {
                fixture.runtime.running.insert(fixture.configuration.clients[0].id)
                fixture.runtime.portOpen = true
            }
        }
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 0)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.isEmpty)
    }

    @Test("process replacement and foreign port owners prevent account preparation",
          arguments: [false, true])
    @MainActor
    func lostBeforeConnection(reusedPID: Bool) async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.onEvent = { event in
            if event.phase == .switchingAccount {
                if reusedPID {
                    fixture.runtime.instance = .init(pid: testGameInstance.pid, launchedAt: Date(timeIntervalSince1970: 2))
                } else { fixture.runtime.portOwner = 61_499 }
            }
        }
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 1)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.isEmpty)
    }

    @Test("foreign ownership at cleanup never sends closedown or starts the next client")
    @MainActor
    func lostBeforeCleanup() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.onEvent = { event in
            if event.phase == .closing { fixture.runtime.portOwner = 61_499 }
        }
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 1)
        #expect(fixture.runtime.terminations == 0)
        #expect(await !fixture.commands.gameCommands.contains("closedown"))
    }

    @Test("a new listener during shutdown stops the next client without closing the new owner")
    @MainActor
    func replacedAfterShutdown() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.replaceAfterShutdown = true
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 1)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.filter { $0 == "closedown" }.count == 1)
    }

    @Test("confirmed listener disappearance allows the next client in either server order", arguments: [false, true])
    @MainActor
    func listenerDisappearsDuringShutdown(reverse: Bool) async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        if reverse { fixture.configuration.clients.reverse() }
        fixture.runtime.shutdownProbe = PortProbe(commandRunner: ShutdownRaceCommands(outcome: .closed))
        #expect(await fixture.run().isSuccess)
        #expect(fixture.runtime.launches == 2)
        #expect(fixture.runtime.terminations == 0)
        #expect(fixture.runtime.running.isEmpty)
        #expect(await fixture.commands.gameCommands.filter { $0 == "closedown" }.count == 2)
    }

    @Test("shutdown confirmation never releases an unknown, replaced or uninspectable listener",
          arguments: [ShutdownRaceOutcome.unknown, .foreign, .probeFailure], [false, true])
    @MainActor
    func listenerCannotBeConfirmed(outcome: ShutdownRaceOutcome, reverse: Bool) async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        if reverse { fixture.configuration.clients.reverse() }
        fixture.runtime.shutdownProbe = PortProbe(commandRunner: ShutdownRaceCommands(outcome: outcome))
        let report = await fixture.run()
        #expect(report.fatalError != nil)
        #expect(report.succeededSteps == 1)
        #expect(fixture.runtime.launches == 1)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.filter { $0 == "closedown" }.count == 1)
        #expect(try ExecutionStateStore(directories: fixture.directories).loadForExecution().completedSteps.count == 1)
    }

    @Test("a released port never authorizes cleanup of a replaced process")
    @MainActor
    func replacedProcessAfterShutdown() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.replaceProcessAfterShutdown = true
        #expect(await fixture.run().fatalError != nil)
        #expect(fixture.runtime.launches == 1)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.filter { $0 == "closedown" }.count == 1)
    }

    @Test("cancellation before acquiring a client leaves external clients untouched")
    @MainActor
    func cancelledBeforeLaunch() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.cancelInspection = true
        fixture.runtime.running.insert(fixture.configuration.clients[0].id)
        #expect(await fixture.run().cancelled)
        #expect(fixture.runtime.launches == 0)
        #expect(fixture.runtime.terminations == 0)
        #expect(await fixture.commands.gameCommands.isEmpty)
    }

    @Test("cancellation during launch only cleans up the acquired instance")
    @MainActor
    func cancelledDuringLaunch() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        fixture.runtime.cancelLaunch = true
        let report = await fixture.run()
        #expect(report.cancelled)
        #expect(report.fatalError == nil)
        #expect(fixture.runtime.launches == 1)
        #expect(fixture.runtime.terminations == 1)
        #expect(fixture.runtime.running.isEmpty)
        #expect(await fixture.commands.gameCommands.isEmpty)
    }

    @Test("new instances still run and close serially in both server orders", arguments: [false, true])
    @MainActor
    func normalRun(reverse: Bool) async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        if reverse { fixture.configuration.clients.reverse() }
        #expect(await fixture.run().isSuccess)
        #expect(fixture.runtime.launches == 2)
        #expect(fixture.runtime.running.isEmpty)
        #expect(await fixture.commands.gameCommands.filter { $0 == "closedown" }.count == 2)
    }
}

@MainActor
private final class OwnershipFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "automaa-ownership-tests-\(UUID())")
    let runtime = OwnershipRuntime()
    let commands: OwnershipCommands
    var configuration: AppConfiguration
    var directories: AppDirectories { AppDirectories(root: root) }

    init() throws {
        var clients: [ClientConfiguration] = []
        for (index, kind) in [ClientKind.official, .yoStarJP].enumerated() {
            let app = root.appending(path: "Client\(index).app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            clients.append(ClientConfiguration(name: "测试客户端 \(index)", kind: kind,
                appPath: app.path, address: "127.0.0.1:61487", profileName: "ownership-\(index)",
                bundleIdentifier: "dev.automaa.tests.ownership.\(index)",
                accounts: [AccountConfiguration(name: "测试账号")]))
        }
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        plan.fight.enabled = false
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = true
        configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: clients, plans: [plan])
        commands = OwnershipCommands(runtime: runtime)
    }

    func run(resumeToday: Bool = true) async -> WorkflowReport {
        let runner = WorkflowRunner(directories: directories, portProbe: runtime, gameController: runtime,
            shutdownPolicy: .init(maaGracePeriod: 0, systemGracePeriod: 0, forcedGracePeriod: 0),
            commandRunner: commands, eventSink: {
                self.runtime.events.append($0)
                self.runtime.onEvent?($0)
            })
        return await runner.run(configuration, planID: configuration.plans[0].id, resumeToday: resumeToday)
    }

    func remove() {
        runtime.onEvent = nil
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class OwnershipRuntime: PortProbing, GameProcessControlling {
    var running: Set<UUID> = []
    var portOpen = false
    var terminations = 0
    var launches = 0
    var inspections = 0
    var instance = testGameInstance
    var portOwner = testGameInstance.pid
    var inspectionFails = false
    var cancelInspection = false
    var cancelLaunch = false
    var replaceAfterShutdown = false
    var replaceProcessAfterShutdown = false
    var shutdownProbe: PortProbe?
    var onEvent: ((RunnerEvent) -> Void)?
    var events: [RunnerEvent] = []
    func inspect(_ value: String, observeCancellation: Bool) async throws -> PortState {
        inspections += 1
        if cancelInspection { throw RuntimeError.cancelled }
        if inspectionFails { throw RuntimeError.portProbeFailed(value) }
        if !portOpen, launches > 0, let probe = shutdownProbe {
            shutdownProbe = nil
            return try await probe.inspect(value, observeCancellation: observeCancellation)
        }
        return portOpen ? .listening([portOwner]) : .closed
    }
    func instances(for client: ClientConfiguration) -> [GameProcessIdentity] { running.contains(client.id) ? [instance] : [] }
    func launch(_ client: ClientConfiguration) async throws -> GameProcessIdentity {
        launches += 1
        running.insert(client.id)
        portOpen = true
        if cancelLaunch { withUnsafeCurrentTask { $0?.cancel() } }
        return instance
    }
    func isOpen(_ value: String, observeCancellation: Bool) async -> Bool { portOpen }
    func wait(forOpen: Bool, address: String, timeout: TimeInterval, observeCancellation: Bool) async -> Bool { portOpen == forOpen }
    func isRunning(_ client: ClientConfiguration) -> Bool { running.contains(client.id) }
    func terminate(_ client: ClientConfiguration, instance: GameProcessIdentity, force: Bool) -> Bool {
        guard self.instance == instance else { return false }
        terminations += 1
        running.remove(client.id)
        portOpen = false
        return true
    }
}

private actor OwnershipCommands: CommandRunning {
    let runtime: OwnershipRuntime
    private(set) var gameCommands: [String] = []
    private(set) var commands: [String] = []
    init(runtime: OwnershipRuntime) { self.runtime = runtime }
    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool, startupScreenshotPolicy: StartupScreenshotPolicy?) async throws -> CommandResult {
        let command = arguments.first ?? ""
        commands.append(command)
        if command == "run" || command == "closedown" {
            gameCommands.append(command)
            if command == "closedown" {
                await MainActor.run {
                    if runtime.replaceProcessAfterShutdown {
                        runtime.instance = .init(pid: testGameInstance.pid, launchedAt: Date(timeIntervalSince1970: 2))
                    } else { runtime.running.removeAll() }
                    runtime.portOpen = runtime.replaceAfterShutdown
                    if runtime.replaceAfterShutdown { runtime.portOwner = 61_499 }
                }
            }
        }
        return .init(exitCode: command == "dir" ? 1 : 0, standardOutput: "", standardError: "", timedOut: false)
    }
}

enum ShutdownRaceOutcome: Sendable { case closed, unknown, foreign, probeFailure }

private actor ShutdownRaceCommands: CommandRunning {
    let outcome: ShutdownRaceOutcome
    var connections = 0
    init(outcome: ShutdownRaceOutcome) { self.outcome = outcome }

    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool, startupScreenshotPolicy: StartupScreenshotPolicy?) async throws -> CommandResult {
        if executable == "/usr/sbin/lsof" {
            return .init(exitCode: outcome == .foreign ? 0 : 1,
                standardOutput: outcome == .foreign ? "p61499\n" : "", standardError: "", timedOut: false)
        }
        connections += 1
        if connections > 1, outcome == .probeFailure { throw RuntimeError.portProbeFailed("test") }
        let closed = connections > 1 && outcome == .closed
        return .init(exitCode: closed ? 1 : 0, standardOutput: "",
            standardError: closed ? "nc: Connection refused" : "", timedOut: false)
    }
}
