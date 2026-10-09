import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Client shutdown diagnostics")
struct ClientShutdownDiagnosticsTests {
    @Test("shutdown reports each attempted method and the observed process and port state",
          arguments: ShutdownTestMode.allCases, [false, true])
    @MainActor
    func stages(mode: ShutdownTestMode, maaTimedOut: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-shutdown-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let app = root.appending(path: "Test.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let client = ClientConfiguration(name: "测试客户端", kind: .official, appPath: app.path,
            address: "127.0.0.1:61390", profileName: "shutdown-test", bundleIdentifier: "dev.automaa.tests.shutdown",
            accounts: [AccountConfiguration(name: "测试账号")])
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        plan.fight.enabled = false
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let runtime = ShutdownTestRuntime(mode: mode)
        let runner = WorkflowRunner(directories: directories, portProbe: runtime, gameController: runtime,
            shutdownPolicy: .init(maaGracePeriod: 0, systemGracePeriod: 0, forcedGracePeriod: 0),
            commandRunner: ShutdownTestCommands(runtime: runtime, timeoutMAA: maaTimedOut), eventSink: { runtime.entries.append($0.log) })
        let report = await runner.run(config, planID: plan.id)
        let closing = runtime.entries.filter { $0.phase == .closing }
        let details = closing.compactMap(\.details).joined(separator: "\n")
        #expect(details.contains("退出方式：MAA 退出请求"))
        #expect(details.contains(maaTimedOut ? "请求结果：退出码 15 · 命令超时" : "请求结果：退出码 0"))
        #expect(details.contains("耗时："))
        #expect(details.contains("进程："))
        #expect(details.contains("MaaTools 端口："))
        #expect(details.contains("退出方式：macOS 常规退出") == (mode != .maa))
        #expect(details.contains("退出方式：macOS 强制清理") == (mode != .maa && mode != .normal))
        let expected = Array(["退出方式：MAA 退出请求", "退出方式：macOS 常规退出", "退出方式：macOS 强制清理"]
            .prefix(mode == .maa ? 1 : mode == .normal ? 2 : 3))
        let actual = closing.filter { $0.level == .info }.compactMap { $0.details?.components(separatedBy: "\n").first }
        #expect(Array(actual.prefix(expected.count)) == expected)
        if mode == .processStuck || mode == .portStuck {
            #expect(report.fatalError != nil)
            #expect(!closing.contains { $0.level == .success })
            #expect(details.contains(mode == .processStuck ? "进程：仍在运行" : "MaaTools 端口：仍开放"))
        } else {
            #expect(report.isSuccess)
            #expect(closing.last?.details?.contains("进程：已退出 · MaaTools 端口：已释放") == true)
            #expect(!closing.contains { $0.level == .warning })
        }
        if mode == .forced { #expect(details.contains("请求结果：未被系统接受")) }
        #expect(!ProcessLock.isHeld(at: directories.lock))
    }
}

enum ShutdownTestMode: CaseIterable, Sendable { case maa, normal, forced, processStuck, portStuck }

@MainActor
private final class ShutdownTestRuntime: PortProbing, GameProcessControlling {
    let mode: ShutdownTestMode
    var running = true
    var portOpen = true
    var entries: [LogEntry] = []

    init(mode: ShutdownTestMode) { self.mode = mode }
    func isOpen(_ value: String, observeCancellation: Bool) async -> Bool { portOpen }
    func wait(forOpen: Bool, address: String, timeout: TimeInterval, observeCancellation: Bool) async -> Bool {
        portOpen == forOpen
    }
    func isRunning(_ client: ClientConfiguration) -> Bool { running }
    func terminate(_ client: ClientConfiguration, force: Bool) -> Bool {
        if force || mode == .normal {
            running = mode == .processStuck
            portOpen = mode == .portStuck
        }
        return force || mode == .normal
    }
    func maaShutdown() {
        if mode == .maa { running = false; portOpen = false }
    }
}

private struct ShutdownTestCommands: CommandRunning {
    let runtime: ShutdownTestRuntime
    let timeoutMAA: Bool

    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool, startupScreenshotPolicy: StartupScreenshotPolicy?) async throws -> CommandResult {
        if arguments.first == "closedown" {
            await runtime.maaShutdown()
            return .init(exitCode: timeoutMAA ? 15 : 0, standardOutput: "", standardError: "", timedOut: timeoutMAA)
        }
        return .init(exitCode: arguments.first == "dir" ? 1 : 0, standardOutput: "", standardError: "", timedOut: false)
    }
}
