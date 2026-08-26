import Foundation

public enum MAAUpdateChannel: String, Sendable {
    case stable
    case beta
}

struct MAAResourceCompatibilityIssue: Equatable {
    let details: String
    let candidateWasNotActivated: Bool

    var guidance: String {
        let state = candidateWasNotActivated
            ? "下载的候选组件没有启用，当前安装保持不变"
            : "AutoMAA 未启动游戏"
        return "MaaCore 无法完整加载 MAA 资源。请先在“全局设置 → MAA”更新稳定版核心与基础资源；若稳定通道尚未包含修复，可手动确认更新 Beta，或等待修复进入稳定通道。\(state)"
    }
}

enum MAAComponentUpdate {
    case resources
    case core(MAAUpdateChannel)

    var includesCore: Bool {
        switch self {
        case .resources: false
        case .core: true
        }
    }

    var arguments: [String] {
        switch self {
        case .resources:
            ["hot-update", "--batch"]
        case let .core(channel):
            ["update", channel.rawValue, "--test-time", "10", "--batch"]
        }
    }

    var timeout: TimeInterval {
        includesCore ? 3_600 : 180
    }
}

struct MAAInstallationPaths {
    let data: URL
    let cache: URL
    let library: URL
    let resource: URL
    let hotUpdate: URL
}

struct MAAUpdateStaging {
    let data: URL
    let cache: URL
    let state: URL

    var library: URL { data.appending(path: "lib", directoryHint: .isDirectory) }
    var resource: URL { data.appending(path: "resource", directoryHint: .isDirectory) }
    var hotUpdate: URL { data.appending(path: "MaaResource", directoryHint: .isDirectory) }

    func remove() {
        try? FileManager.default.removeItem(at: data)
        try? FileManager.default.removeItem(at: cache)
        try? FileManager.default.removeItem(at: state)
    }
}

struct FileReplacement {
    let source: URL
    let target: URL
}

enum FileReplacementTransaction {
    private struct AppliedReplacement {
        let target: URL
        let backup: URL?
    }

    static func commit(_ replacements: [FileReplacement]) throws {
        let manager = FileManager.default
        var applied: [AppliedReplacement] = []
        do {
            for replacement in replacements {
                guard manager.fileExists(atPath: replacement.source.path) else { continue }
                try manager.createDirectory(
                    at: replacement.target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let backup: URL?
                if manager.fileExists(atPath: replacement.target.path) {
                    let candidate = replacement.target.deletingLastPathComponent().appending(
                        path: ".automaa-backup-\(replacement.target.lastPathComponent)-\(UUID().uuidString)"
                    )
                    try manager.moveItem(at: replacement.target, to: candidate)
                    backup = candidate
                } else {
                    backup = nil
                }
                do {
                    try manager.moveItem(at: replacement.source, to: replacement.target)
                    applied.append(.init(target: replacement.target, backup: backup))
                } catch {
                    if let backup {
                        try? manager.moveItem(at: backup, to: replacement.target)
                    }
                    throw error
                }
            }
        } catch {
            for replacement in applied.reversed() {
                try? manager.removeItem(at: replacement.target)
                if let backup = replacement.backup {
                    try? manager.moveItem(at: backup, to: replacement.target)
                }
            }
            throw error
        }
        for replacement in applied {
            if let backup = replacement.backup {
                try? manager.removeItem(at: backup)
            }
        }
    }
}

public struct MAAMaintenanceState: Codable, Equatable, Sendable {
    public var lastCoreUpdateAttempt: Date?

    public init(lastCoreUpdateAttempt: Date? = nil) {
        self.lastCoreUpdateAttempt = lastCoreUpdateAttempt
    }
}

public struct MAAMaintenanceStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func load() -> MAAMaintenanceState {
        guard let data = try? Data(contentsOf: directories.maaMaintenanceState),
              let state = try? Self.decoder.decode(MAAMaintenanceState.self, from: data)
        else { return .init() }
        return state
    }

    public func save(_ state: MAAMaintenanceState) throws {
        try directories.prepare()
        let data = try Self.encoder.encode(state)
        try data.write(to: directories.maaMaintenanceState, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum AutomaticMAAUpdatePolicy {
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let scheduledRunSafetyWindow: TimeInterval = 90 * 60

    public static func nextAttemptDate(
        lastAttempt: Date?,
        now: Date = Date()
    ) -> Date {
        lastAttempt?.addingTimeInterval(checkInterval) ?? now
    }

    public static func canStart(
        enabled: Bool,
        lastAttempt: Date?,
        nextScheduledRun: Date?,
        now: Date = Date()
    ) -> Bool {
        guard enabled, nextAttemptDate(lastAttempt: lastAttempt, now: now) <= now else { return false }
        guard let nextScheduledRun else { return true }
        return nextScheduledRun.timeIntervalSince(now) >= scheduledRunSafetyWindow
    }
}

enum MAAMaintenanceFailureClassifier {
    static func isTransientNetworkFailure(_ result: CommandResult) -> Bool {
        guard result.exitCode != 0, !result.cancelled else { return false }
        let output = result.combinedOutput.lowercased()
        return [
            "couldn't connect",
            "could not connect",
            "failed to connect",
            "connection timed out",
            "operation timed out",
            "network is unreachable",
            "could not resolve host",
            "couldn't resolve host",
            "temporary failure in name resolution",
            "connection reset",
            "connection was reset",
            "connection refused",
            "remote end hung up unexpectedly",
            "tls handshake timeout",
            "unexpected disconnect",
            "early eof",
        ].contains { output.contains($0) }
    }
}
