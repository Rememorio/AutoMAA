import Foundation

public enum FightStageStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case gameCurrentOrLast
    case rememberedRegular
    case fixed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gameCurrentOrLast: "游戏当前/上次"
        case .rememberedRegular: "上次成功的常规关卡"
        case .fixed: "固定关卡"
        }
    }

    public var detail: String {
        switch self {
        case .gameCurrentOrLast:
            "沿用 MAA 的当前/上次关卡；其他方案执行剿灭后，这里也可能继续进入剿灭。"
        case .rememberedRegular:
            "按账号使用 AutoMAA 记住的最近一次成功常规作战；剿灭和零次作战不会覆盖。"
        case .fixed:
            "始终使用下面指定的关卡。"
        }
    }
}

public enum FightStageResolution: Equatable, Sendable {
    case omitted
    case value(String)
    case unavailable
}

public struct FightStageMemoryEntry: Codable, Equatable, Sendable {
    public var clientID: UUID
    public var accountID: UUID
    public var stage: String
    public var updatedAt: Date

    public init(clientID: UUID, accountID: UUID, stage: String, updatedAt: Date = Date()) {
        self.clientID = clientID
        self.accountID = accountID
        self.stage = stage
        self.updatedAt = updatedAt
    }
}

public struct FightStageMemory: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public private(set) var entries: [FightStageMemoryEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        entries: [FightStageMemoryEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    public func stage(clientID: UUID, accountID: UUID) -> String? {
        entries.first {
            $0.clientID == clientID && $0.accountID == accountID
        }?.stage
    }

    public mutating func remember(
        _ stage: String,
        clientID: UUID,
        accountID: UUID,
        at date: Date = Date()
    ) {
        let entry = FightStageMemoryEntry(
            clientID: clientID,
            accountID: accountID,
            stage: stage,
            updatedAt: date
        )
        if let index = entries.firstIndex(where: {
            $0.clientID == clientID && $0.accountID == accountID
        }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort {
            if $0.clientID != $1.clientID {
                return $0.clientID.uuidString < $1.clientID.uuidString
            }
            return $0.accountID.uuidString < $1.accountID.uuidString
        }
    }

    @discardableResult
    public mutating func rememberSuccessful(
        stage: String,
        times: Int,
        clientID: UUID,
        accountID: UUID,
        at date: Date = Date()
    ) -> Bool {
        guard let stage = FightStagePolicy.regularStage(from: stage, times: times) else {
            return false
        }
        remember(stage, clientID: clientID, accountID: accountID, at: date)
        return true
    }
}

public enum FightStagePolicy {
    public static func resolve(
        _ configuration: FightConfiguration,
        memory: FightStageMemory,
        clientID: UUID,
        accountID: UUID
    ) -> FightStageResolution {
        guard configuration.usesCustomSettings else { return .omitted }
        switch configuration.stageStrategy {
        case .gameCurrentOrLast:
            return .value("")
        case .rememberedRegular:
            guard let stage = memory.stage(clientID: clientID, accountID: accountID) else {
                return .unavailable
            }
            return .value(stage)
        case .fixed:
            return .value(configuration.stage.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public static func regularStage(from stage: String, times: Int) -> String? {
        let value = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard times > 0,
              !value.isEmpty,
              value.count <= 128,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !isAnnihilation(value)
        else { return nil }
        return value
    }

    public static func isAnnihilation(_ stage: String) -> Bool {
        let value = stage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "annihilation" || value.hasSuffix("@annihilation")
    }
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
