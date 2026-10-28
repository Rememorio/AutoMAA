import AppKit
import Darwin
import Foundation

public enum RuntimeError: LocalizedError {
    case alreadyRunning
    case cancelled
    case invalidAddress(String)
    case portOccupied(String)
    case portOccupiedByClient(address: String, client: String)
    case clientAlreadyRunning(String)
    case clientOwnershipLost(String)
    case portProbeFailed(String)
    case launchUnconfirmed(String)
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
        case let .portOccupied(value):
            "MaaTools 端口 \(value) 已被未知程序占用。为避免连接错误客户端，请关闭相关游戏和 MAA 后重新运行"
        case let .portOccupiedByClient(address, client):
            "客户端「\(client)」仍在运行并占用 MaaTools 端口 \(address)。为避免连接错误客户端，请关闭该客户端及其他 MAA 后重新运行"
        case let .clientAlreadyRunning(client):
            "客户端「\(client)」已在本轮运行前打开，AutoMAA 不会接管或关闭它。请先结束其他 MAA 任务并手动关闭该客户端，再运行方案"
        case let .clientOwnershipLost(client):
            "无法确认客户端「\(client)」及其 MaaTools 端口仍属于本轮启动的实例，流程已停止；请手动检查客户端和其他 MAA"
        case let .portProbeFailed(address):
            "无法确认 MaaTools 端口 \(address) 的状态，流程已停止；请检查连接地址和本机检测权限后重试"
        case let .launchUnconfirmed(client):
            "未能确认客户端「\(client)」的启动实例，流程已停止；若客户端稍后打开，请手动关闭后重试"
        case let .appNotFound(path): "找不到游戏：\(path)"
        case let .bundleIdentifierMissing(client): "客户端「\(client)」缺少 Bundle Identifier"
        case let .launchFailed(message): "游戏启动失败：\(message)"
        case let .connectionTimeout(address): "等待 MaaTools \(address) 超时"
        case let .accountSelectorMissing(account): "账号「\(account)」尚未填写唯一账号片段"
        case let .accountSwitchFailed(account): "账号「\(account)」准备失败"
        case let .taskFailed(task): "任务「\(task)」执行失败"
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

enum StartupCommandOutcome: Equatable {
    case ready
    case coreInitializationFailed
    case connectionLost
    case accountNavigationFailed
    case needsIntervention(StartupFailureDiagnosis)
    case failed
}

enum StartupFailureClassifier {
    static func isMAACoreInitializationFailure(_ output: String) -> Bool {
        containsAny(output.lowercased(), [
            "maacore returned an error", "json parse failed", "load resource failed",
            "infrastconfig load failed", "核心初始化失败", "资源加载失败",
        ])
    }

    static func isGameOffline(_ output: String) -> Bool {
        containsAny(output.lowercased(), [
            "gameoffline", "game offline", "auto reconnect disabled", "游戏连接已离线",
        ])
    }

    static func isScreenshotConnectionFailure(_ output: String) -> Bool {
        containsAny(output.lowercased(), ["screencapfailed", "screencap failed"])
    }

    static func commandOutcome(result: CommandResult, output: String) -> StartupCommandOutcome {
        if isMAACoreInitializationFailure(output) {
            return .coreInitializationFailed
        }
        if result.stopReason == .startupScreenshotFailure || isGameOffline(output)
            || (result.exitCode != 0 && isScreenshotConnectionFailure(output)) {
            return .connectionLost
        }
        guard !result.cancelled else { return .failed }
        if result.exitCode == 0, !result.timedOut {
            return .ready
        }
        if result.startupWaitingForUpdate {
            return .needsIntervention(gameDataUpdateDiagnosis)
        }
        let intervention = explicitIntervention(output: output, hasAccountSelector: true)
        if let diagnosis = intervention, diagnosis.scope == .client {
            return .needsIntervention(diagnosis)
        }
        if result.timedOut {
            return .connectionLost
        }
        if result.startupNavigationFailed, intervention == nil {
            return .accountNavigationFailed
        }
        return .failed
    }

    static let gameDataUpdateDiagnosis = StartupFailureDiagnosis(
        scope: .client,
        guidance: "游戏可能仍在下载或解压更新数据，请手动等待更新完成并进入一次主界面，再继续未完成任务"
    )

    static func diagnose(output: String, hasAccountSelector: Bool) -> StartupFailureDiagnosis {
        if let diagnosis = explicitIntervention(output: output, hasAccountSelector: hasAccountSelector) {
            return diagnosis
        }
        let value = output.lowercased()
        if isGameOffline(value) {
            return .init(
                scope: .client,
                guidance: "游戏连接已离线，重启客户端后仍未恢复；请先检查网络和代理是否可用，再手动进入游戏主界面；若仍无法登录，请检查维护、登录、更新或异常弹窗"
            )
        }
        if containsAny(value, [
            "network", "timeout", "timed out", "connection", "lookup address", "dns",
            "screencapfailed", "screencap failed",
            "网络", "执行超时", "连接超时", "无法连接",
        ]) {
            return .init(
                scope: .client,
                guidance: "网络或 MaaTools 连接异常，自动重试仍未恢复；请手动检查游戏和网络"
            )
        }
        return .init(
            scope: .client,
            guidance: "游戏可能停在强制更新、登录、公告或异常弹窗页面，请手动进入一次主界面"
        )
    }

    private static func explicitIntervention(output: String, hasAccountSelector: Bool) -> StartupFailureDiagnosis? {
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
        if isMAACoreInitializationFailure(value) {
            return .init(
                scope: .client,
                guidance: "MaaCore 初始化或资源加载失败，请先在全局设置检测环境并选择“更新 MAA”；若稳定版仍不兼容，可手动选择 Beta，处理前不应反复运行客户端"
            )
        }
        if containsAny(value, [
            "update required", "please update", "outdated", "version mismatch", "client version",
            "版本过低", "版本不匹配", "强制更新", "需要更新", "游戏更新",
        ]) {
            return .init(
                scope: .client,
                guidance: "疑似游戏大版本更新或资源版本不匹配，请手动更新游戏包体并进入一次主界面"
            )
        }
        if containsAny(value, [
            "downloading resource", "resource download", "unpacking resource",
            "下载资源", "资源下载", "下载数据", "解压资源",
        ]) {
            return gameDataUpdateDiagnosis
        }
        if containsAny(value, ["maintenance", "server is closed", "维护中", "服务器维护", "停服维护"]) {
            return .init(
                scope: .client,
                guidance: "游戏可能正在维护，请稍后手动确认"
            )
        }
        if containsAny(value, ["login", "sign in", "authentication", "captcha", "verification",
                              "登录", "重新认证", "用户协议", "验证码", "身份验证"]) {
            return .init(
                scope: .client,
                guidance: "游戏可能停在登录、协议确认或身份验证页面，请手动处理后再运行"
            )
        }
        return nil
    }

    private static func containsAny(_ value: String, _ patterns: [String]) -> Bool {
        patterns.contains { value.contains($0) }
    }
}

struct ManualInterventionError: LocalizedError {
    let scope: InterventionScope
    let reason: String
    let guidance: String
    let details: String?

    init(scope: InterventionScope, reason: String, guidance: String, details: String? = nil) {
        self.scope = scope
        self.reason = reason
        self.guidance = guidance
        self.details = details
    }

    var errorDescription: String? {
        "\(reason)。\(guidance)"
    }
}

public final class ProcessLock: @unchecked Sendable {
    public let identity = UUID()
    private var descriptor: Int32 = -1

    public static func currentIdentity(at url: URL) -> UUID? {
        guard isHeld(at: url), let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = value.split(separator: "\n")
        return lines.count == 2 ? UUID(uuidString: String(lines[1])) : nil
    }

    public static func isHeld(at url: URL) -> Bool {
        let descriptor = Darwin.open(url.path, O_RDWR)
        guard descriptor >= 0 else { return errno != ENOENT }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return true }
        _ = flock(descriptor, LOCK_UN)
        return false
    }

    public init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            descriptor = -1
            throw RuntimeError.alreadyRunning
        }
        let value = "\(getpid())\n\(identity.uuidString)\n"
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(of: ":") else {
            throw RuntimeError.invalidAddress(value)
        }
        var parsedHost = String(trimmed[..<separator])
        let parsedPort = String(trimmed[trimmed.index(after: separator)...])
        if parsedHost.hasPrefix("["), parsedHost.hasSuffix("]") {
            parsedHost.removeFirst()
            parsedHost.removeLast()
        }
        guard !parsedHost.isEmpty,
              !parsedHost.contains(where: \.isWhitespace),
              let portNumber = Int(parsedPort),
              (1...65_535).contains(portNumber)
        else {
            throw RuntimeError.invalidAddress(value)
        }
        host = parsedHost
        port = String(portNumber)
    }
}

public enum SensitiveDataRedactor {
    public static func redact(_ value: String, sensitiveValues: [String] = []) -> String {
        var result = value
        let secrets = Set(sensitiveValues.compactMap { rawValue -> String? in
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 3 ? trimmed : nil
        }).sorted { $0.count > $1.count }
        for secret in secrets {
            result = result.replacingOccurrences(
                of: secret,
                with: "[已隐藏]",
                options: [.caseInsensitive, .literal]
            )
        }
        result = replacingMatches(
            in: result,
            pattern: #"(?<![\p{L}\p{N}._-])/(?:Users|home)/[^/\s]+"#,
            replacement: "[用户目录]"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?<![\p{L}\p{N}._%+-])[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[A-Za-z]{2,}(?![\p{L}\p{N}])"#,
            replacement: "[已隐藏邮箱]"
        )
        return replacingMatches(
            in: result,
            pattern: #"(?<!\d)\d{7,}(?!\d)"#,
            replacement: "[已隐藏号码]"
        )
    }

    private static func replacingMatches(in value: String, pattern: String, replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
