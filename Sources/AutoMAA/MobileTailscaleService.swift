import AppKit
import AutoMAAKit
import Foundation
import Darwin

@MainActor
final class MobileTailscaleService {
    static let port = 43827
    private var process: Process?
    private var output: Pipe?
    private var generation = UUID()
    var isRunning: Bool { process?.isRunning == true }

    static func executable() -> String? {
        let bundles = ["io.tailscale.ipn.macos", "io.tailscale.ipn.macsys"]
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        let paths = bundles.map { $0.appending(path: "Contents/MacOS/Tailscale").path }
            + ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func start(localPort: UInt16) async throws -> String {
        let attempt = generation
        guard let executable = Self.executable() else { throw MobileAccessError("未找到 Tailscale。请先安装并登录，再重试连接。") }
        let status = try await command(executable, ["status", "--json"])
        guard status["BackendState"] as? String == "Running",
              let node = status["Self"] as? [String: Any], let dns = node["DNSName"] as? String else {
            throw MobileAccessError("请在 Tailscale 中登录并开启连接，然后重试")
        }
        let endpoint = "wss://\(dns.trimmingCharacters(in: CharacterSet(charactersIn: "."))):\(Self.port)/mobile"
        guard MobileProtocol.validEndpoint(endpoint) else { throw MobileAccessError("请在 Tailscale 管理页启用 MagicDNS 和 HTTPS") }
        let configuration = try await command(executable, ["serve", "status", "--json"])
        guard !Self.hasPort(configuration) else { throw MobileAccessError("Tailscale 端口 \(Self.port) 已被使用。请检查已有 Serve 配置后重试。") }
        try Task.checkCancellation()
        guard generation == attempt else { throw CancellationError() }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = ["serve", "--yes", "--https=\(Self.port)", "http://127.0.0.1:\(localPort)"]
        process.environment = ProcessInfo.processInfo.environment.merging(["TERM": "dumb", "SHLVL": "1"]) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        // Drain output without retaining CLI data or potential authorization URLs in logs.
        pipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        self.process = process
        output = pipe
        try process.run()
        for _ in 0..<20 {
            try await Task.sleep(for: .seconds(1))
            guard generation == attempt, process.isRunning else { throw MobileAccessError("Tailscale Serve 未启动。请在终端完成 tailscale serve 的 HTTPS 授权后重试。") }
            let active = try await command(executable, ["serve", "status", "--json"])
            if Self.hasProxy(active, target: "http://127.0.0.1:\(localPort)") { return endpoint }
        }
        throw MobileAccessError("连接设置超时。请在 Tailscale 管理页启用 HTTPS，确认网络正常后重试。")
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        generation = UUID()
        let running = process
        process = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? output?.fileHandleForReading.close()
        output = nil
        guard let running, running.isRunning else { return nil }
        let pid = running.processIdentifier
        let target = getpgid(pid) == pid && pid != getpgrp() ? -pid : pid
        kill(target, SIGTERM)
        return Task.detached {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while running.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if running.isRunning { kill(target, SIGKILL) }
            let killDeadline = ContinuousClock.now.advanced(by: .seconds(2))
            while running.isRunning, ContinuousClock.now < killDeadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func command(_ executable: String, _ arguments: [String]) async throws -> [String: Any] {
        let result = try await CommandRunner().run(executable: executable, arguments: arguments,
                                                  environment: ["TERM": "dumb", "SHLVL": "1"], timeout: 5)
        try Task.checkCancellation()
        guard result.exitCode == 0, !result.timedOut, !result.cancelled,
              let value = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any] else {
            throw MobileAccessError("无法读取 Tailscale 状态。请确认已登录、连接正常并更新到当前稳定版本。")
        }
        return value
    }
    private static func hasPort(_ value: [String: Any]) -> Bool {
        if let tcp = value["TCP"] as? [String: Any], tcp[String(port)] != nil { return true }
        return value.values.contains { ($0 as? [String: Any]).map(hasPort) == true }
    }
    private static func hasProxy(_ value: [String: Any], target: String) -> Bool {
        if value["Proxy"] as? String == target { return true }
        return value.values.contains { ($0 as? [String: Any]).map { hasProxy($0, target: target) } == true }
    }
}
