import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Command failure diagnostics")
struct CommandDiagnosticsTests {
    @Test("navigation evidence does not override explicit manual intervention",
          arguments: ["account not found", "maintenance", "captcha", "update required", "load resource failed", "resource download"])
    @MainActor
    func navigationDoesNotBypassIntervention(output: String) async throws {
        let fixture = try DiagnosticFixture()
        defer { fixture.remove() }
        let failure = DiagnosticCommands.Reply(
            result: .init(exitCode: 1, standardOutput: "", standardError: output, timedOut: false),
            log: settingsNavigationFailureLog())
        let commands = DiagnosticCommands(startups: [failure, failure])
        let report = await fixture.run(commands)
        #expect(!report.isSuccess)
        #expect(report.unexecutedSteps == 1)
        #expect(!fixture.runtime.entries.contains { $0.message.contains("正在重启") })
        #expect(await commands.taskCount == 0)
        #expect(ExecutionStateStore(directories: fixture.directories).loadForToday().completedSteps.isEmpty)
    }

    @Test("navigation recovery shares the account restart budget with later task timeouts")
    @MainActor
    func navigationSharesRestartBudget() async throws {
        let fixture = try DiagnosticFixture()
        defer { fixture.remove() }
        let failure = DiagnosticCommands.Reply(
            result: .init(exitCode: 1, standardOutput: "", standardError: "StartUp Error", timedOut: false),
            log: settingsNavigationFailureLog())
        let timeout = DiagnosticCommands.Reply(result: .init(exitCode: 15, standardOutput: "", standardError: "", timedOut: true))
        let commands = DiagnosticCommands(startups: [failure, .init()], tasks: [timeout, timeout])
        let report = await fixture.run(commands)
        #expect(!report.isSuccess)
        #expect(await commands.startupCount == 2)
        #expect(fixture.runtime.entries.count { $0.message.contains("正在重启") } == 1)
        #expect(ExecutionStateStore(directories: fixture.directories).loadForToday().completedSteps.isEmpty)
    }

    @Test("navigation failure cannot restart a cancelled workflow")
    @MainActor
    func cancelledNavigationDoesNotRestart() async throws {
        let fixture = try DiagnosticFixture()
        defer { fixture.remove() }
        let failure = DiagnosticCommands.Reply(
            result: .init(exitCode: 15, standardOutput: "", standardError: "", timedOut: false, cancelled: true),
            log: settingsNavigationFailureLog())
        let commands = DiagnosticCommands(startups: [failure])
        let report = await fixture.run(commands)
        #expect(report.cancelled)
        #expect(await commands.startupCount == 1)
        #expect(await commands.taskCount == 0)
        #expect(!fixture.runtime.entries.contains { $0.message.contains("正在重启") })
        #expect(!fixture.runtime.running)
        #expect(!ProcessLock.isHeld(at: fixture.directories.lock))
    }

    @Test("navigation recovery stops when the client cannot release its connection")
    @MainActor
    func navigationRequiresClosedClient() async throws {
        let fixture = try DiagnosticFixture(accountCount: 2)
        defer { fixture.remove() }
        fixture.runtime.closes = false
        let failure = DiagnosticCommands.Reply(
            result: .init(exitCode: 1, standardOutput: "", standardError: "StartUp Error", timedOut: false),
            log: settingsNavigationFailureLog())
        let commands = DiagnosticCommands(startups: [failure])
        let report = await fixture.run(commands)
        #expect(!report.isSuccess)
        #expect(await commands.startupCount == 1)
        #expect(await commands.taskCount == 0)
        #expect(ExecutionStateStore(directories: fixture.directories).loadForToday().completedSteps.isEmpty)
        #expect(!ProcessLock.isHeld(at: fixture.directories.lock))
    }

    @Test("settings navigation failure restarts once and preserves completed account checkpoints",
          arguments: [false, true])
    @MainActor
    func settingsNavigationRecovery(failsAgain: Bool) async throws {
        let fixture = try DiagnosticFixture(accountCount: 2)
        defer { fixture.remove() }
        let failure = DiagnosticCommands.Reply(
            result: .init(exitCode: 1, standardOutput: "", standardError: "StartUp Error", timedOut: false),
            log: settingsNavigationFailureLog())
        let commands = DiagnosticCommands(startups: [.init(), failure, failsAgain ? failure : .init()])
        let report = await fixture.run(commands)
        #expect(report.isSuccess == !failsAgain)
        #expect(report.unexecutedSteps == (failsAgain ? 1 : 0))
        #expect(await commands.startupCount == 3)
        #expect(await commands.taskCount == (failsAgain ? 1 : 2))
        #expect(fixture.runtime.entries.count { $0.message.contains("设置页返回账号选择页失败，正在重启") } == 1)
        #expect(ExecutionStateStore(directories: fixture.directories).loadForToday().completedSteps.count == (failsAgain ? 1 : 2))
        #expect(!fixture.runtime.running)
        #expect(!ProcessLock.isHeld(at: fixture.directories.lock))
        #expect(await commands.roots.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
        if failsAgain {
            #expect(report.attentionMessages.contains { $0.contains("设置页返回账号选择页失败") })
            let continuation = DiagnosticCommands()
            let resumed = await fixture.run(continuation)
            #expect(resumed.isSuccess)
            #expect(await continuation.startupCount == 1)
            #expect(await continuation.taskCount == 1)
        }
    }

    @Test("a silent task timeout retains core evidence before retry and cleanup")
    @MainActor
    func silentTimeoutKeepsEvidence() async throws {
        let fixture = try DiagnosticFixture()
        defer { fixture.remove() }
        let commands = DiagnosticCommands(tasks: [
            .init(result: .init(exitCode: 15, standardOutput: "", standardError: "", timedOut: true),
                  log: callback("SubTaskStart", task: "MallEnter")),
            .init(log: callback("SubTaskCompleted", task: "MallFinished")),
        ])
        let report = await fixture.run(commands)

        #expect(report.isSuccess)
        let details = fixture.runtime.entries.compactMap(\.details).joined(separator: "\n")
        #expect(details.contains("最后观察到开始：Mall / MallEnter"))
        let log = try fixture.diagnostics()
        #expect(log.contains("信用与购物 · 第 1 次"))
        #expect(log.contains("MallEnter"))
        #expect(!log.contains("MallFinished"))
        let roots = await commands.roots
        #expect(roots.count == 4)
        #expect(Set(roots).count == roots.count)
        #expect(roots.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
        #expect(!fixture.runtime.running)
        #expect(!ProcessLock.isHeld(at: fixture.directories.lock))
    }

    @Test("all non-fight tasks retain failed attempts without trusting success callbacks",
          arguments: [TaskKind.recruit, .infrast, .mall, .award])
    @MainActor
    func failureCallbacksDoNotChangeOutcome(task: TaskKind) async throws {
        let fixture = try DiagnosticFixture(task: task)
        defer { fixture.remove() }
        let failure = CommandResult(exitCode: 1, standardOutput: "", standardError: "", timedOut: false)
        let commands = DiagnosticCommands(tasks: [
            .init(result: failure, log: callback("SubTaskStart", task: "FirstAttempt")),
            .init(result: failure, log: callback("TaskChainCompleted", task: "SecondAttempt")),
        ])
        let report = await fixture.run(commands)
        #expect(!report.isSuccess)
        #expect(ExecutionStateStore(directories: fixture.directories).loadForToday().completedSteps.isEmpty)
        let details = fixture.runtime.entries.compactMap(\.details)
        #expect(details.contains { $0.contains("FirstAttempt") && !$0.contains("SecondAttempt") })
        #expect(details.contains { $0.contains("SecondAttempt") && !$0.contains("FirstAttempt") })
        let log = try fixture.diagnostics()
        #expect(log.contains("\(task.title) · 第 1 次 · 核心诊断"))
        #expect(log.contains("\(task.title) · 第 2 次 · 核心诊断"))
    }

    @Test("startup diagnostics stay separate from failure classification and redact before storage")
    @MainActor
    func startupEvidenceDoesNotChangeRecovery() async throws {
        let fixture = try DiagnosticFixture()
        defer { fixture.remove() }
        let failure = CommandResult(exitCode: 0, standardOutput: "", standardError: "ScreencapFailed",
                                    timedOut: false, stopReason: .startupScreenshotFailure)
        let log = callback("SubTaskStart", task: "fixture-private-selector")
            + "[ERR] account not found: fixture-private-selector diagnostic@example.invalid 15500001111\n"
        let commands = DiagnosticCommands(startups: [.init(result: failure, log: log), .init(result: failure, log: log)])
        let report = await fixture.run(commands)
        #expect(!report.isSuccess)
        #expect(report.unexecutedSteps == 1)
        #expect(!fixture.runtime.entries.contains { $0.message.contains("唯一匹配片段") })
        #expect(fixture.runtime.entries.count { $0.message.contains("连续截图失败，已提前结束") } == 1)
        let saved = try fixture.diagnostics()
            + fixture.runtime.entries.compactMap(\.details).joined(separator: "\n")
        for secret in ["fixture-private-selector", "diagnostic@example.invalid", "15500001111"] {
            #expect(!saved.contains(secret))
        }
        #expect(saved.contains("最后观察到开始"))
        #expect(saved.contains("账号准备 · 第 2 次 · 核心诊断"))
        #expect(await commands.roots.count == 2)
    }

    @Test("unreadable core logs do not obstruct cancellation, checkpoint safety or client cleanup",
          arguments: [false, true])
    @MainActor
    func captureFailureStillCleansUp(duringStartup: Bool) async throws {
        let fixture = try DiagnosticFixture()
        defer { fixture.remove() }
        let reply = DiagnosticCommands.Reply(unreadableLog: true, waitsForCancellation: true)
        let commands = DiagnosticCommands(startups: duringStartup ? [reply] : [], tasks: duringStartup ? [] : [reply])
        let task = Task { await fixture.run(commands) }
        defer { task.cancel() }
        for _ in 0..<500 {
            if await commands.waiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await commands.waiting)
        task.cancel()
        let report = await task.value
        #expect(report.cancelled)
        #expect(!fixture.runtime.running)
        #expect(!ProcessLock.isHeld(at: fixture.directories.lock))
        #expect(ExecutionStateStore(directories: fixture.directories).loadForToday().completedSteps.isEmpty)
        let log = try fixture.diagnostics()
        #expect(log.contains("核心日志读取失败"))
        #expect(log.contains("· cancelled"))
        #expect(await commands.roots.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    @Test("missing or malformed logs report uncertainty instead of inventing progress")
    func missingAndMalformedEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-diagnostic-empty-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = MAACommandDiagnostics.read(from: root, sensitiveValues: [])
        #expect(missing.lastStarted == nil)
        #expect(missing.summary.contains("没有可读取的核心日志"))
        try writeLog("Assistant::append_callback | SubTaskStart {broken}\n" + callback("SubTaskStart", task: "Partial").dropLast(), root: root)
        let malformed = MAACommandDiagnostics.read(from: root, sensitiveValues: [])
        #expect(malformed.lastStarted == nil)
        #expect(malformed.summary.contains("无法解析"))
        #expect(malformed.summary.contains("末尾不完整"))
    }

    @Test("rotated logs preserve chronological observations with bounded, redacted UTF-8 output")
    func rotatedEvidenceIsBounded() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-diagnostic-bound-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeLog(callback("SubTaskStart", task: "OldStep"), root: root, name: "asst.bak.log")
        let line = callback("SubTaskCompleted", task: "已完成-fixture-private-selector")
        try writeLog(String(repeating: line, count: 2500) + callback("SubTaskStart", task: "LatestStep")
                     + "[ERR] latest error diagnostic@example.invalid\n", root: root)
        let evidence = MAACommandDiagnostics.read(from: root, sensitiveValues: ["fixture-private-selector"])
        #expect(evidence.lastStarted == "Mall / LatestStep")
        #expect(evidence.lastCompleted == "Mall / 已完成-[已隐藏]")
        #expect(evidence.lastError?.contains("latest error") == true)
        #expect(evidence.output.utf8.count <= MAACommandDiagnostics.outputLimit)
        #expect(!evidence.output.contains("fixture-private-selector"))
        #expect(!evidence.output.contains("diagnostic@example.invalid"))
        #expect(!evidence.output.contains("OldStep"))
        #expect(!evidence.output.contains("�"))
        #expect(evidence.summary.contains("较早步骤可能缺失"))
    }

    @Test("core evidence does not follow symbolic links outside the command directory")
    func linkedLogsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-diagnostic-link-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeLog(callback("SubTaskStart", task: "UnrelatedCommand"), root: root, name: "unrelated.log")
        try FileManager.default.createSymbolicLink(at: root.appending(path: "debug/asst.log"),
                                                  withDestinationURL: root.appending(path: "debug/unrelated.log"))
        let evidence = MAACommandDiagnostics.read(from: root, sensitiveValues: [])
        #expect(evidence.lastStarted == nil)
        #expect(!evidence.output.contains("UnrelatedCommand"))
        #expect(evidence.summary.contains("不是普通文件"))
    }

    @Test("the first offline observation survives subsequent transport and task-chain errors")
    func firstIssuePreservesFailureOrder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-diagnostic-order-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let log = callback("SubTaskCompleted", task: "StartUpBegin", chain: "StartUp")
            + callback("SubTaskStart", task: "OfflineConfirm", chain: "StartUp")
            + "[ERR] Cannot get screencap: Broken pipe\n"
            + "Assistant::append_callback | TaskChainError {\"taskchain\":\"StartUp\"}\n"
        try writeLog(log, root: root)
        let evidence = MAACommandDiagnostics.read(from: root, sensitiveValues: [])
        #expect(evidence.summary.contains("首次观察到异常：StartUp / OfflineConfirm"))
        #expect(evidence.lastError == "TaskChainError · StartUp")
        #expect(evidence.output.contains("Broken pipe"))
    }

    @Test("the first observed error stays bounded and redacted when recent output evicts it")
    func firstIssueSurvivesOutputEviction() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-diagnostic-first-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = "[ERR] initial fixture-private-selector diagnostic@example.invalid " + String(repeating: "错", count: 300)
        try writeLog(first + "\n", root: root, name: "asst.bak.log")
        try writeLog(String(repeating: callback("SubTaskCompleted", task: "LaterStep"), count: 1_000)
            + "[ERR] final failure\n", root: root)
        let evidence = MAACommandDiagnostics.read(from: root, sensitiveValues: ["fixture-private-selector"])
        #expect(evidence.summary.contains("首次观察到异常：[ERR] initial [已隐藏] [已隐藏邮箱]"))
        #expect(evidence.lastError == "[ERR] final failure")
        #expect(!evidence.summary.contains("fixture-private-selector"))
        #expect(!evidence.summary.contains("diagnostic@example.invalid"))
        #expect(!evidence.output.contains("initial"))
        #expect(evidence.output.utf8.count <= MAACommandDiagnostics.outputLimit)
        #expect(evidence.summary.count < 500)
    }

    private func writeLog(_ contents: String, root: URL, name: String = "asst.log") throws {
        try FileManager.default.createDirectory(at: root.appending(path: "debug"), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: root.appending(path: "debug/\(name)"))
    }

    private func callback(_ event: String, task: String, chain: String = "Mall") -> String {
        "Assistant::append_callback | \(event) {\"taskchain\":\"\(chain)\",\"taskid\":1,\"subtask\":\"ProcessTask\",\"details\":{\"task\":\"\(task)\"}}\n"
    }
}

private actor DiagnosticCommands: CommandRunning {
    struct Reply: Sendable {
        var result = CommandResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false)
        var log = ""
        var unreadableLog = false
        var waitsForCancellation = false
    }

    var startups: [Reply]
    var tasks: [Reply]
    private(set) var roots: [String] = []
    private(set) var waiting = false
    private(set) var startupCount = 0
    private(set) var taskCount = 0

    init(startups: [Reply] = [], tasks: [Reply] = []) {
        self.startups = startups
        self.tasks = tasks
    }

    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool, startupScreenshotPolicy: StartupScreenshotPolicy?) async throws -> CommandResult {
        if arguments.first == "dir" {
            return .init(exitCode: 1, standardOutput: "", standardError: "no test installation", timedOut: false)
        }
        let reply: Reply
        if try isStartupTask(arguments: arguments, environment: environment) {
            startupCount += 1
            reply = startups.isEmpty ? Reply() : startups.removeFirst()
        } else if arguments.first == "run" {
            taskCount += 1
            reply = tasks.isEmpty ? Reply() : tasks.removeFirst()
        } else {
            return Reply().result
        }
        if let path = environment["MAA_STATE_DIR"] {
            roots.append(path)
            let debug = URL(filePath: path).appending(path: "debug")
            try FileManager.default.createDirectory(at: debug, withIntermediateDirectories: true)
            let log = debug.appending(path: "asst.log")
            if reply.unreadableLog {
                try FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
            } else {
                try Data(reply.log.utf8).write(to: log)
            }
        }
        if reply.waitsForCancellation {
            waiting = true
            try await Task.sleep(for: .seconds(20))
        }
        return reply.result
    }
}

@MainActor
private final class DiagnosticFixture {
    let directories: AppDirectories
    let configuration: AppConfiguration
    let runtime = DiagnosticRuntime()

    init(task: TaskKind = .mall, accountCount: Int = 1) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-diagnostic-tests-\(UUID())")
        directories = AppDirectories(root: root)
        let app = root.appending(path: "Test.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let client = ClientConfiguration(name: "测试客户端", kind: .official, appPath: app.path,
            address: "127.0.0.1:61387", profileName: "diagnostic-test", bundleIdentifier: "dev.automaa.tests.diagnostics",
            accounts: (0..<accountCount).map {
                AccountConfiguration(name: "测试账号 \($0 + 1)", accountSelector: $0 == 0 ? "fixture-private-selector" : "fixture-selector-\($0)")
            })
        var plan = AutomationPlan.completeRoutine
        plan.policy.hotUpdateBeforeRun = false
        plan.policy.maxRetries = 1
        plan.fight.enabled = false
        plan.infrast.enabled = task == .infrast
        plan.recruit.enabled = task == .recruit
        plan.award.enabled = task == .award
        plan.mall.enabled = task == .mall
        configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
    }

    func run(_ commands: DiagnosticCommands) async -> WorkflowReport {
        let runner = WorkflowRunner(directories: directories, portProbe: runtime, gameController: runtime,
            shutdownPolicy: .init(maaGracePeriod: 0, systemGracePeriod: 0, forcedGracePeriod: 0),
            commandRunner: commands, eventSink: runtime.record)
        return await runner.run(configuration, planID: configuration.plans[0].id)
    }

    func diagnostics() throws -> String {
        let runID = try #require(runtime.entries.first?.runID)
        return try String(contentsOf: DiagnosticLogStore(directories: directories).url(for: runID), encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: directories.root) }
}

@MainActor
private final class DiagnosticRuntime: PortProbing, GameProcessControlling {
    var running = false
    var closes = true
    var entries: [LogEntry] = []

    func inspect(_ value: String, observeCancellation: Bool) async throws -> PortState {
        running ? .listening([testGameInstance.pid]) : .closed
    }
    func instances(for client: ClientConfiguration) -> [GameProcessIdentity] { running ? [testGameInstance] : [] }
    func launch(_ client: ClientConfiguration) async throws -> GameProcessIdentity {
        running = true
        return testGameInstance
    }

    func isOpen(_ value: String, observeCancellation: Bool) async -> Bool { running }
    func wait(forOpen: Bool, address: String, timeout: TimeInterval, observeCancellation: Bool) async -> Bool {
        if forOpen { running = true }
        return running == forOpen
    }
    func isRunning(_ client: ClientConfiguration) -> Bool { running }
    func terminate(_ client: ClientConfiguration, instance: GameProcessIdentity, force: Bool) -> Bool { running = !closes; return closes }
    func record(_ event: RunnerEvent) { entries.append(event.log) }
}
