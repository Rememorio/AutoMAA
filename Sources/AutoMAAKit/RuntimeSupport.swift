import AppKit
import Darwin
import Foundation

public enum RuntimeError: LocalizedError {
    case alreadyRunning
    case cancelled
    case invalidAddress(String)
    case portOccupied(String)
    case appNotFound(String)
    case bundleIdentifierMissing(String)
    case launchFailed(String)
    case connectionTimeout(String)
    case accountSelectorMissing(String)
    case accountSwitchFailed(String)
    case taskFailed(String)
    case portReleaseTimeout(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "已有一个 AutoMAA 流程正在运行"
        case .cancelled: "用户已停止流程"
        case let .invalidAddress(value): "连接地址无效：\(value)"
        case let .portOccupied(value): "端口 \(value) 已被其他程序占用"
        case let .appNotFound(path): "找不到游戏：\(path)"
        case let .bundleIdentifierMissing(client): "\(client) 缺少 Bundle Identifier"
        case let .launchFailed(message): "游戏启动失败：\(message)"
        case let .connectionTimeout(address): "等待 MaaTools \(address) 超时"
        case let .accountSelectorMissing(account): "\(account) 尚未填写唯一账号片段"
        case let .accountSwitchFailed(account): "切换到 \(account) 失败"
        case let .taskFailed(task): "\(task) 执行失败"
        case let .portReleaseTimeout(address): "客户端关闭后端口 \(address) 仍未释放"
        }
    }
}

enum InterventionScope: Equatable {
    case account
    case client
}

struct StartupFailureDiagnosis: Equatable {
    let scope: InterventionScope
    let guidance: String
}

enum StartupFailureClassifier {
    static func diagnose(output: String, hasAccountSelector: Bool) -> StartupFailureDiagnosis {
        let value = output.lowercased()
        if hasAccountSelector, containsAny(value, [
            "account not found", "account name", "no matching account", "match account",
            "找不到账号", "未找到账号", "账号匹配", "账号片段",
        ]) {
            return .init(
                scope: .account,
                guidance: "请检查该账号的唯一匹配片段和当前登录状态；其他账号仍会继续执行"
            )
        }
        if containsAny(value, [
            "update required", "please update", "outdated", "version mismatch", "client version",
            "版本过低", "版本不匹配", "强制更新", "需要更新", "游戏更新",
        ]) {
            return .init(
                scope: .client,
                guidance: "疑似游戏大版本更新或资源版本不匹配，请手动更新游戏包体并进入一次主界面；本次将跳过该客户端"
            )
        }
        if containsAny(value, ["maintenance", "server is closed", "维护中", "服务器维护", "停服维护"]) {
            return .init(
                scope: .client,
                guidance: "游戏可能正在维护，请稍后手动确认；本次将跳过该客户端"
            )
        }
        if containsAny(value, ["login", "sign in", "authentication", "登录", "重新认证", "用户协议"]) {
            return .init(
                scope: .client,
                guidance: "游戏可能停在登录、协议确认或身份验证页面，请手动处理后再运行；本次将跳过该客户端"
            )
        }
        if containsAny(value, [
            "network", "timeout", "timed out", "connection", "lookup address", "dns",
            "网络", "连接超时", "无法连接",
        ]) {
            return .init(
                scope: .client,
                guidance: "网络或 MaaTools 连接异常，自动重试仍未恢复；请手动检查游戏和网络，本次将跳过该客户端"
            )
        }
        return .init(
            scope: .client,
            guidance: "游戏可能停在强制更新、登录、公告或异常弹窗页面，请手动进入一次主界面；本次将跳过该客户端"
        )
    }

    private static func containsAny(_ value: String, _ patterns: [String]) -> Bool {
        patterns.contains { value.contains($0) }
    }
}

struct ManualInterventionError: LocalizedError {
    let scope: InterventionScope
    let reason: String
    let guidance: String

    var errorDescription: String? {
        "\(reason)。\(guidance)"
    }
}

public final class ProcessLock: @unchecked Sendable {
    private var descriptor: Int32 = -1

    public init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            descriptor = -1
            throw RuntimeError.alreadyRunning
        }
        let value = "\(getpid())\n"
        value.withCString { pointer in
            _ = ftruncate(descriptor, 0)
            _ = write(descriptor, pointer, strlen(pointer))
        }
    }

    deinit {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

public final class CaffeinateLease: @unchecked Sendable {
    private let process = Process()

    public init?() {
        process.executableURL = URL(filePath: "/usr/bin/caffeinate")
        process.arguments = ["-dimsu"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
    }

    deinit {
        if process.isRunning { process.terminate() }
    }
}

public struct PortAddress: Sendable, Equatable {
    public var host: String
    public var port: String

    public init(_ value: String) throws {
        guard let separator = value.lastIndex(of: ":") else {
            throw RuntimeError.invalidAddress(value)
        }
        host = String(value[..<separator])
        port = String(value[value.index(after: separator)...])
        if host.isEmpty || port.isEmpty || Int(port) == nil {
            throw RuntimeError.invalidAddress(value)
        }
    }
}

public struct PortProbe: Sendable {
    private let commandRunner = CommandRunner()

    public init() {}

    public func isOpen(_ value: String, observeCancellation: Bool = true) async -> Bool {
        guard let address = try? PortAddress(value),
              let result = try? await commandRunner.run(
                executable: "/usr/bin/nc",
                arguments: ["-z", "-G", "1", address.host, address.port],
                timeout: 2,
                observeCancellation: observeCancellation
              )
        else { return false }
        return result.exitCode == 0
    }

    public func wait(
        forOpen shouldBeOpen: Bool,
        address: String,
        timeout: TimeInterval,
        observeCancellation: Bool = true
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if observeCancellation, Task.isCancelled { return false }
            if await isOpen(address, observeCancellation: observeCancellation) == shouldBeOpen { return true }
            if observeCancellation {
                try? await Task.sleep(for: .milliseconds(500))
            } else {
                await Task.detached(priority: .utility) {
                    try? await Task.sleep(for: .milliseconds(500))
                }.value
            }
        }
        return await isOpen(address, observeCancellation: observeCancellation) == shouldBeOpen
    }
}

@MainActor
public struct GameProcessController {
    public init() {}

    public func isRunning(_ client: ClientConfiguration) -> Bool {
        !applications(for: client).isEmpty
    }

    @discardableResult
    public func terminate(_ client: ClientConfiguration, force: Bool) -> Bool {
        let applications = applications(for: client)
        guard !applications.isEmpty else { return true }
        return applications.allSatisfy { force ? $0.forceTerminate() : $0.terminate() }
    }

    private func applications(for client: ClientConfiguration) -> [NSRunningApplication] {
        let expected = URL(filePath: client.appPath).standardizedFileURL.resolvingSymlinksInPath().path
        return NSRunningApplication.runningApplications(withBundleIdentifier: client.bundleIdentifier).filter { application in
            guard let bundleURL = application.bundleURL else { return false }
            return bundleURL.standardizedFileURL.resolvingSymlinksInPath().path == expected
        }
    }
}
