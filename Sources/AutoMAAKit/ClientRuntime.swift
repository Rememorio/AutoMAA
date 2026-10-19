import AppKit
import Darwin
import Foundation

enum PortState: Equatable, Sendable {
    case closed
    case listening(Set<Int32>)

    var isOpen: Bool { self != .closed }
}

public struct PortProbe: Sendable {
    private let commandRunner: any CommandRunning

    public init() { commandRunner = CommandRunner() }
    init(commandRunner: any CommandRunning) { self.commandRunner = commandRunner }

    func inspect(_ value: String, observeCancellation: Bool = true) async throws -> PortState {
        let address = try PortAddress(value)
        guard Self.isLocalHost(address.host) else { throw RuntimeError.portProbeFailed(value) }
        do {
            guard try await connectionIsOpen(address, value: value, observeCancellation: observeCancellation) else { return .closed }
            let owners = try await commandRunner.run(executable: "/usr/sbin/lsof",
                arguments: ["-nP", "-a", "-iTCP:\(address.port)", "-sTCP:LISTEN", "-Fp"],
                environment: ["LC_ALL": "C"], timeout: 3, observeCancellation: observeCancellation, startupScreenshotPolicy: nil)
            if owners.cancelled { throw RuntimeError.cancelled }
            guard !owners.timedOut, owners.standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  owners.exitCode == 0 || (owners.exitCode == 1 && owners.standardOutput.isEmpty) else {
                throw RuntimeError.portProbeFailed(value)
            }
            var pids: Set<Int32> = []
            for line in owners.standardOutput.split(whereSeparator: \.isNewline) {
                // lsof emits descriptor records even when only the PID field is selected.
                if line.first == "f", !pids.isEmpty { continue }
                guard line.first == "p", let pid = Int32(line.dropFirst()), pid > 0 else {
                    throw RuntimeError.portProbeFailed(value)
                }
                pids.insert(pid)
            }
            // The listener may exit between nc and lsof. Only a fresh refusal confirms release.
            if pids.isEmpty, try await connectionIsOpen(address, value: value, observeCancellation: observeCancellation) == false {
                return .closed
            }
            return .listening(pids)
        } catch let error as RuntimeError {
            throw error
        } catch {
            throw RuntimeError.portProbeFailed(value)
        }
    }

    private func connectionIsOpen(_ address: PortAddress, value: String, observeCancellation: Bool) async throws -> Bool {
        let result = try await commandRunner.run(executable: "/usr/bin/nc",
            arguments: ["-zv", "-G", "1", "-w", "1", address.host, address.port],
            environment: ["LC_ALL": "C"], timeout: 3, observeCancellation: observeCancellation, startupScreenshotPolicy: nil)
        if result.cancelled { throw RuntimeError.cancelled }
        guard !result.timedOut else { throw RuntimeError.portProbeFailed(value) }
        if result.exitCode == 0 { return true }
        let failures = result.standardError.split(whereSeparator: \.isNewline)
        guard result.exitCode == 1, !failures.isEmpty,
              failures.allSatisfy({ $0.contains("Connection refused") }) else {
            throw RuntimeError.portProbeFailed(value)
        }
        return false
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host.lowercased() == "localhost" { return true }
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var resolved: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &resolved) == 0, let resolved else { return false }
        defer { freeaddrinfo(resolved) }
        func numericHost(_ address: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        guard let address = resolved.pointee.ai_addr,
              let target = numericHost(address, length: resolved.pointee.ai_addrlen) else { return false }
        if target.hasPrefix("127.") || target == "::1" { return true }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return false }
        defer { freeifaddrs(interfaces) }
        var current = interfaces
        while let interface = current {
            if let address = interface.pointee.ifa_addr,
               numericHost(address, length: socklen_t(address.pointee.sa_len)) == target { return true }
            current = interface.pointee.ifa_next
        }
        return false
    }

    public func isOpen(_ value: String, observeCancellation: Bool = true) async -> Bool {
        // Unknown is treated as occupied; workflow decisions use the throwing inspection.
        (try? await inspect(value, observeCancellation: observeCancellation).isOpen) ?? true
    }

    public func wait(forOpen: Bool, address: String, timeout: TimeInterval,
                     observeCancellation: Bool = true) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        repeat {
            if try await inspect(address, observeCancellation: observeCancellation).isOpen == forOpen { return true }
            if observeCancellation {
                try await Task.sleep(for: .milliseconds(500))
            } else {
                await Task.detached { try? await Task.sleep(for: .milliseconds(500)) }.value
            }
        } while ContinuousClock.now < deadline
        return false
    }
}

@MainActor
protocol PortProbing {
    func inspect(_ value: String, observeCancellation: Bool) async throws -> PortState
    func wait(forOpen: Bool, address: String, timeout: TimeInterval, observeCancellation: Bool) async throws -> Bool
}

extension PortProbing {
    func inspect(_ value: String) async throws -> PortState { try await inspect(value, observeCancellation: true) }
    func wait(forOpen: Bool, address: String, timeout: TimeInterval) async throws -> Bool {
        try await wait(forOpen: forOpen, address: address, timeout: timeout, observeCancellation: true)
    }
}

extension PortProbe: PortProbing {}

struct GameProcessIdentity: Equatable, Sendable {
    let pid: Int32
    let launchedAt: Date?
}

@MainActor
protocol GameProcessControlling {
    func instances(for client: ClientConfiguration) -> [GameProcessIdentity]
    func launch(_ client: ClientConfiguration) async throws -> GameProcessIdentity
    func terminate(_ client: ClientConfiguration, instance: GameProcessIdentity, force: Bool) -> Bool
}

@MainActor
public struct GameProcessController {
    public init() {}

    public func isRunning(_ client: ClientConfiguration) -> Bool { !applications(for: client).isEmpty }

    func instances(for client: ClientConfiguration) -> [GameProcessIdentity] {
        applications(for: client).map(Self.identity)
    }

    func launch(_ client: ClientConfiguration) async throws -> GameProcessIdentity {
        guard !Task.isCancelled else { throw RuntimeError.cancelled }
        guard instances(for: client).isEmpty else { throw RuntimeError.clientAlreadyRunning(client.displayName) }
        let request = GameLaunchRequest(client: client)
        let instance = try await request.start()
        guard instance.launchedAt != nil, instances(for: client) == [instance] else {
            throw RuntimeError.launchUnconfirmed(client.displayName)
        }
        return instance
    }

    func terminate(_ client: ClientConfiguration, instance: GameProcessIdentity, force: Bool) -> Bool {
        guard let application = applications(for: client).first(where: { Self.identity($0) == instance }) else { return true }
        return force ? application.forceTerminate() : application.terminate()
    }

    private func applications(for client: ClientConfiguration) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: client.bundleIdentifier).filter { application in
            guard !application.isTerminated, let bundleURL = application.bundleURL else { return false }
            return Self.matchesApplication(client, bundleURL: bundleURL, executableURL: application.executableURL)
        }
    }

    fileprivate static func identity(_ application: NSRunningApplication) -> GameProcessIdentity {
        .init(pid: application.processIdentifier, launchedAt: application.launchDate)
    }

    static func matchesApplication(_ client: ClientConfiguration, bundleURL: URL, executableURL: URL?) -> Bool {
        let configured = URL(filePath: client.appPath, directoryHint: .isDirectory)
        if canonicalPath(configured) == canonicalPath(bundleURL) { return true }
        guard let expected = Bundle(url: configured)?.executableURL, let executableURL else { return false }
        return canonicalPath(expected) == canonicalPath(executableURL)
    }

    private static func canonicalPath(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
}

extension GameProcessController: GameProcessControlling {}

@MainActor
private final class GameLaunchRequest {
    let client: ClientConfiguration
    var continuation: CheckedContinuation<GameProcessIdentity, any Error>?
    var timer: Task<Void, Never>?

    init(client: ClientConfiguration) { self.client = client }

    func start() async throws -> GameProcessIdentity {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timer = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                finish(.failure(RuntimeError.launchUnconfirmed(client.displayName)))
            }
            let options = NSWorkspace.OpenConfiguration()
            options.createsNewApplicationInstance = true
            options.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: URL(filePath: client.appPath), configuration: options) { application, error in
                Task { @MainActor in
                    guard let application else {
                        self.finish(.failure(RuntimeError.launchFailed(error?.localizedDescription ?? "系统未返回启动结果")))
                        return
                    }
                    self.finish(.success(GameProcessController.identity(application)))
                }
            }
        }
    }

    private func finish(_ result: Result<GameProcessIdentity, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(with: result)
    }
}
