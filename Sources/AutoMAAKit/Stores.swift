import Foundation

public enum ConfigurationStoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int?)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            if let version {
                "配置协议 schema v\(version) 与当前版本不兼容"
            } else {
                "配置文件缺少有效的 schema 版本"
            }
        }
    }
}

public struct ConfigurationRecovery: Sendable {
    public let configuration: AppConfiguration
    public let backupURL: URL
}

public struct AppDirectories: Sendable {
    public let root: URL
    public let maaConfig: URL
    public let logs: URL
    public let configuration: URL
    public let history: URL
    public let executionState: URL
    public let fightStageMemory: URL
    public let maaMaintenanceState: URL
    public let generatedManifest: URL
    public let lock: URL

    public init(root: URL? = nil) {
        let resolvedRoot = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/AutoMAA", directoryHint: .isDirectory)
        self.root = resolvedRoot
        maaConfig = resolvedRoot.appending(path: "MAA", directoryHint: .isDirectory)
        logs = resolvedRoot.appending(path: "Logs", directoryHint: .isDirectory)
        configuration = resolvedRoot.appending(path: "config.json")
        history = resolvedRoot.appending(path: "history.json")
        executionState = resolvedRoot.appending(path: "execution-state.json")
        fightStageMemory = resolvedRoot.appending(path: "fight-stage-memory.json")
        maaMaintenanceState = resolvedRoot.appending(path: "maa-maintenance.json")
        generatedManifest = resolvedRoot.appending(path: "generated-files.json")
        lock = resolvedRoot.appending(path: "runner.lock")
    }

    public func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: maaConfig, withIntermediateDirectories: true)
        try manager.createDirectory(at: maaConfig.appending(path: "profiles"), withIntermediateDirectories: true)
        try manager.createDirectory(at: maaConfig.appending(path: "tasks"), withIntermediateDirectories: true)
        try manager.createDirectory(at: logs, withIntermediateDirectories: true)
    }
}

public struct ConfigurationStore: Sendable {
    private struct VersionProbe: Decodable {
        let schemaVersion: Int?
    }

    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func load() throws -> AppConfiguration {
        try directories.prepare()
        guard FileManager.default.fileExists(atPath: directories.configuration.path) else {
            let configuration = AppConfiguration.defaults
            try save(configuration)
            return configuration
        }
        let data = try Data(contentsOf: directories.configuration)
        let version = try Self.decoder.decode(VersionProbe.self, from: data)
        guard version.schemaVersion == AppConfiguration.currentSchemaVersion else {
            throw ConfigurationStoreError.unsupportedSchema(version.schemaVersion)
        }
        return try Self.decoder.decode(AppConfiguration.self, from: data)
    }

    public func backupAndReset() throws -> ConfigurationRecovery {
        try directories.prepare()
        let data = try Data(contentsOf: directories.configuration)
        let version = try? Self.decoder.decode(VersionProbe.self, from: data).schemaVersion
        let versionLabel = version.map(String.init) ?? "unknown"
        let backupURL = uniqueBackupURL(versionLabel: versionLabel)
        try data.write(to: backupURL, options: .atomic)
        let configuration = AppConfiguration.defaults
        try save(configuration)
        return ConfigurationRecovery(
            configuration: configuration,
            backupURL: backupURL
        )
    }

    public func save(_ configuration: AppConfiguration) throws {
        try directories.prepare()
        let data = try Self.encoder.encode(configuration)
        try data.write(to: directories.configuration, options: .atomic)
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

    private func uniqueBackupURL(versionLabel: String) -> URL {
        let base = directories.root.appending(path: "config-schema-v\(versionLabel).backup.json")
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        return directories.root.appending(
            path: "config-schema-v\(versionLabel)-\(UUID().uuidString.lowercased()).backup.json"
        )
    }
}

public struct HistoryStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func load() -> [LogEntry] {
        guard let data = try? Data(contentsOf: directories.history),
              let logs = try? Self.decoder.decode([LogEntry].self, from: data)
        else { return [] }
        return logs
    }

    public func append(_ entry: LogEntry) {
        var logs = load()
        logs.append(entry)
        if logs.count > 1_000 {
            logs.removeFirst(logs.count - 1_000)
        }
        guard let data = try? Self.encoder.encode(logs) else { return }
        try? directories.prepare()
        try? data.write(to: directories.history, options: .atomic)
    }

    public func clear() throws {
        try directories.prepare()
        try Data("[]".utf8).write(to: directories.history, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public struct DiagnosticLogStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func begin(runID: UUID, keeping limit: Int = 30) {
        try? directories.prepare()
        prune(keeping: limit)
        let header = "AutoMAA diagnostic session \(runID.uuidString.lowercased())\n"
        try? Data(header.utf8).write(to: url(for: runID), options: .atomic)
    }

    public func append(
        _ result: CommandResult,
        command: String,
        runID: UUID,
        sensitiveValues: [String] = []
    ) {
        let command = SensitiveDataRedactor.redact(command, sensitiveValues: sensitiveValues)
        let output = SensitiveDataRedactor.redact(result.combinedOutput, sensitiveValues: sensitiveValues)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let body = output.isEmpty ? "(no output)" : output
        let record = "\n[\(timestamp)] \(command) · exit \(result.exitCode)\(result.timedOut ? " · timed out" : "")\n\(body)\n"
        let url = url(for: runID)
        guard let data = record.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {}
    }

    public func url(for runID: UUID) -> URL {
        directories.logs.appending(path: "maa-\(runID.uuidString.lowercased()).log")
    }

    private func prune(keeping limit: Int) {
        guard limit > 0,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: directories.logs,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else { return }
        let candidates = urls.filter {
            $0.lastPathComponent.hasPrefix("maa-") && $0.pathExtension == "log"
        }
        .sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for url in candidates.dropFirst(limit - 1) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

public struct ExecutionStateStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func loadForToday() -> ExecutionState {
        let today = Self.todayKey
        guard let data = try? Data(contentsOf: directories.executionState),
              var state = try? Self.decoder.decode(ExecutionState.self, from: data),
              state.dateKey == today
        else { return ExecutionState(dateKey: today) }
        state.updatedAt = Date()
        return state
    }

    public func save(_ state: ExecutionState) throws {
        try directories.prepare()
        let data = try Self.encoder.encode(state)
        try data.write(to: directories.executionState, options: .atomic)
    }

    public func reset() throws {
        try save(ExecutionState(dateKey: Self.todayKey))
    }

    public static var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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

public enum FightStageMemoryStoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidEntry

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "常规关卡记录 schema v\(version) 与当前版本不兼容"
        case .invalidEntry:
            "常规关卡记录包含无效或重复的账号数据"
        }
    }
}

public struct FightStageMemoryStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func load() throws -> FightStageMemory {
        guard FileManager.default.fileExists(atPath: directories.fightStageMemory.path) else {
            return FightStageMemory()
        }
        let data = try Data(contentsOf: directories.fightStageMemory)
        let memory = try Self.decoder.decode(FightStageMemory.self, from: data)
        try validate(memory)
        return memory
    }

    public func save(_ memory: FightStageMemory) throws {
        try validate(memory)
        try directories.prepare()
        let data = try Self.encoder.encode(memory)
        try data.write(to: directories.fightStageMemory, options: .atomic)
    }

    private func validate(_ memory: FightStageMemory) throws {
        guard memory.schemaVersion == FightStageMemory.currentSchemaVersion else {
            throw FightStageMemoryStoreError.unsupportedSchema(memory.schemaVersion)
        }
        var keys: Set<String> = []
        for entry in memory.entries {
            let key = "\(entry.clientID.uuidString.lowercased())-\(entry.accountID.uuidString.lowercased())"
            guard keys.insert(key).inserted,
                  FightStagePolicy.regularStage(from: entry.stage, times: 1) == entry.stage
            else {
                throw FightStageMemoryStoreError.invalidEntry
            }
        }
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
