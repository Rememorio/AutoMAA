import Foundation

public enum MAAUpdateChannel: String, Sendable {
    case stable
    case beta
}

struct MAASemanticVersion: Comparable, CustomStringConvertible, Sendable {
    private enum Identifier: Comparable, Sendable {
        case numeric(Int)
        case text(String)

        static func < (lhs: Identifier, rhs: Identifier) -> Bool {
            switch (lhs, rhs) {
            case let (.numeric(lhs), .numeric(rhs)): lhs < rhs
            case (.numeric, .text): true
            case (.text, .numeric): false
            case let (.text(lhs), .text(rhs)): lhs < rhs
            }
        }
    }

    let major: Int
    let minor: Int
    let patch: Int
    private let prerelease: [Identifier]
    let description: String

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }
        normalized = String(normalized.split(separator: "+", maxSplits: 1)[0])
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Int(core[0]),
              let minor = Int(core[1]),
              let patch = Int(core[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }

        let prerelease: [Identifier]
        if parts.count == 2 {
            let values = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else { return nil }
            prerelease = values.map { value in
                if let number = Int(value) { return .numeric(number) }
                return .text(String(value))
            }
        } else {
            prerelease = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        description = normalized
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    static func < (lhs: MAASemanticVersion, rhs: MAASemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            if lhs.prerelease[index] != rhs.prerelease[index] {
                return lhs.prerelease[index] < rhs.prerelease[index]
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

enum MAACoreReleaseManifestError: LocalizedError {
    case invalidEndpoint(String)
    case invalidResponse
    case httpStatus(Int)
    case oversized
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(value): "稳定版清单地址无效：\(value)"
        case .invalidResponse: "稳定版清单没有返回有效的 HTTP 响应"
        case let .httpStatus(status): "稳定版清单请求返回 HTTP \(status)"
        case .oversized: "稳定版清单大小异常"
        case let .invalidVersion(value): "稳定版清单包含无效版本号：\(value)"
        }
    }
}

protocol MAACoreReleaseManifestFetching: Sendable {
    func version(at url: URL) async throws -> MAASemanticVersion
}

struct MAACoreReleaseManifestClient: MAACoreReleaseManifestFetching {
    private struct Manifest: Decodable {
        let version: String
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func version(at url: URL) async throws -> MAASemanticVersion {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: UpdatePolicy.checkTimeout)
        request.setValue("AutoMAA", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MAACoreReleaseManifestError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MAACoreReleaseManifestError.httpStatus(response.statusCode)
        }
        guard data.count <= 2 * 1_024 * 1_024 else {
            throw MAACoreReleaseManifestError.oversized
        }
        let value = try JSONDecoder().decode(Manifest.self, from: data).version
        guard let version = MAASemanticVersion(value) else {
            throw MAACoreReleaseManifestError.invalidVersion(value)
        }
        return version
    }
}

enum MAACoreVersionParser {
    static func parseCLIOutput(_ output: String) -> MAASemanticVersion? {
        for line in output.split(whereSeparator: \Character.isNewline) {
            guard line.localizedCaseInsensitiveContains("MaaCore") else { continue }
            for token in line.split(whereSeparator: \Character.isWhitespace).reversed() {
                if let version = MAASemanticVersion(String(token)) {
                    return version
                }
            }
        }
        return nil
    }
}

enum MAACoreReleaseManifestEndpoint {
    private struct CLIConfiguration: Decodable {
        struct Core: Decodable {
            let apiURL: String?

            enum CodingKeys: String, CodingKey {
                case apiURL = "api_url"
            }
        }

        let core: Core?
        let maaCore: Core?

        enum CodingKeys: String, CodingKey {
            case core
            case maaCore = "maa_core"
        }
    }

    private static let defaultBaseURL = "https://api.maa.plus/MaaAssistantArknights/api/version"

    static func url(channel: MAAUpdateChannel, configurationData: Data?) throws -> URL {
        let config = try configurationData.map {
            try JSONDecoder().decode(CLIConfiguration.self, from: $0)
        }
        let configured = config?.core?.apiURL ?? config?.maaCore?.apiURL
        let baseURL: String
        if let configured, !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = configured
        } else {
            baseURL = defaultBaseURL
        }
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(normalized)/\(channel.rawValue).json"),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            throw MAACoreReleaseManifestError.invalidEndpoint(baseURL)
        }
        return url
    }
}

struct MAAResourceCompatibilityIssue: Equatable {
    let details: String
    let candidateWasNotActivated: Bool

    var guidance: String {
        let state = candidateWasNotActivated
            ? "下载的候选组件没有启用，当前安装保持不变"
            : "AutoMAA 未启动游戏"
        return "MaaCore 无法完整加载 MAA 资源。请先在“全局设置 → MAA 更新”选择“更新 MAA”；若稳定版尚未包含修复，可手动确认更新 Beta，或等待修复进入稳定通道。\(state)"
    }
}

public enum MAAComponentUpdate: Equatable, Sendable {
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

    public var timeout: TimeInterval {
        includesCore ? UpdatePolicy.packageTimeout : UpdatePolicy.resourceTimeout
    }

    public var title: String {
        switch self {
        case .resources: "识别数据"
        case .core(.stable): "MAA 稳定版"
        case .core(.beta): "MAA Beta"
        }
    }
}

struct MAAInstallationPaths: Sendable {
    let data: URL
    let cache: URL
    let library: URL
    let resource: URL
    let hotUpdate: URL
}

struct MAAUpdateStaging: Sendable {
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
    static func isTransientNetworkFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .secureConnectionFailed,
        ].contains(error.code)
    }

    static func isTransientNetworkFailure(_ result: CommandResult) -> Bool {
        guard !result.cancelled, !result.timedOut else { return false }
        let output = result.combinedOutput.lowercased()
        guard result.exitCode != 0 || output.contains("failed to update resource repository") else { return false }
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
            "peer disconnected",
            "connection lost",
        ].contains { output.contains($0) }
    }
}
