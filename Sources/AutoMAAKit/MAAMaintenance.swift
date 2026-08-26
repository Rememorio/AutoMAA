import Foundation

public enum MAAUpdateChannel: String, Sendable {
    case stable
    case beta
}

struct MAACoreVersion: Comparable, CustomStringConvertible, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }

    static func parse(_ output: String) -> Self? {
        let pattern = #"MaaCore\s+v?(\d+)\.(\d+)\.(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ),
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let patchRange = Range(match.range(at: 3), in: output),
              let major = Int(output[majorRange]),
              let minor = Int(output[minorRange]),
              let patch = Int(output[patchRange])
        else { return nil }
        return .init(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct MAAResourceCompatibilityIssue: Equatable {
    let coreVersion: MAACoreVersion
    let requiredCoreVersion: MAACoreVersion

    var guidance: String {
        "MaaCore \(coreVersion) 与已安装的基建热更新资源不兼容；该资源需要 MaaCore \(requiredCoreVersion) 或更新版本。请在“全局设置 → MAA”手动选择“更新 Beta 核心与基础资源”，或等待兼容版本进入稳定通道。AutoMAA 未回退资源，也未启动游戏"
    }
}

enum MAAResourceCompatibility {
    private static let crossFacilityInfrastCoreVersion = MAACoreVersion(major: 6, minor: 17, patch: 0)

    static func issue(coreVersionOutput: String, infrastData: Data) -> MAAResourceCompatibilityIssue? {
        guard let coreVersion = MAACoreVersion.parse(coreVersionOutput),
              coreVersion < crossFacilityInfrastCoreVersion,
              let object = try? JSONSerialization.jsonObject(with: infrastData) as? [String: Any],
              object["Processing"] != nil || object["Training"] != nil
        else { return nil }
        return .init(
            coreVersion: coreVersion,
            requiredCoreVersion: crossFacilityInfrastCoreVersion
        )
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
