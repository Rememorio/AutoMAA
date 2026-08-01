import Foundation

public enum ClientKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case official
    case bilibili
    case txwy
    case yoStarEN
    case yoStarJP
    case yoStarKR

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .official: "中国大陆 · 官服"
        case .bilibili: "中国大陆 · B 服"
        case .txwy: "繁中服"
        case .yoStarEN: "国际服"
        case .yoStarJP: "日服"
        case .yoStarKR: "韩服"
        }
    }

    public var maaClientType: String {
        switch self {
        case .official: "Official"
        case .bilibili: "Bilibili"
        case .txwy: "Txwy"
        case .yoStarEN: "YoStarEN"
        case .yoStarJP: "YoStarJP"
        case .yoStarKR: "YoStarKR"
        }
    }

    public var maaTaskClientType: String {
        self == .txwy ? "txwy" : maaClientType
    }

    public var resourceName: String? {
        switch self {
        case .official, .bilibili: nil
        case .txwy: "txwy"
        case .yoStarEN: "YoStarEN"
        case .yoStarJP: "YoStarJP"
        case .yoStarKR: "YoStarKR"
        }
    }

    public var serverCode: String {
        switch self {
        case .official, .bilibili, .txwy: "CN"
        case .yoStarEN: "US"
        case .yoStarJP: "JP"
        case .yoStarKR: "KR"
        }
    }

    public var defaultBundleIdentifier: String {
        switch self {
        case .official: "com.hypergryph.arknights"
        case .bilibili, .txwy, .yoStarEN, .yoStarKR: ""
        case .yoStarJP: "com.YoStarJP.Arknights"
        }
    }

    public var symbol: String {
        switch self {
        case .official, .bilibili: "c.circle.fill"
        case .txwy: "t.circle.fill"
        case .yoStarEN: "e.circle.fill"
        case .yoStarJP: "j.circle.fill"
        case .yoStarKR: "k.circle.fill"
        }
    }
}

public enum TaskKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case fight
    case recruit
    case infrast
    case award

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fight: "理智作战"
        case .recruit: "公开招募"
        case .infrast: "基建收菜"
        case .award: "领取奖励"
        }
    }

    public var symbol: String {
        switch self {
        case .fight: "bolt.fill"
        case .recruit: "person.crop.rectangle.stack.fill"
        case .infrast: "building.2.fill"
        case .award: "gift.fill"
        }
    }
}

public enum FightStagePreset: String, CaseIterable, Identifiable, Sendable {
    case currentOrLast = ""
    case oneSeven = "1-7"
    case lmd = "CE-6"
    case redCertificate = "AP-5"
    case skillSummary = "CA-5"
    case battleRecord = "LS-6"
    case annihilation = "Annihilation"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentOrLast: "当前/上次"
        case .oneSeven: "1-7"
        case .lmd: "龙门币-6/5"
        case .redCertificate: "红票-5"
        case .skillSummary: "技能-5"
        case .battleRecord: "经验-6/5"
        case .annihilation: "剿灭模式"
        }
    }
}

public enum DroneUsage: String, Codable, CaseIterable, Identifiable, Sendable {
    case notUse = "_NotUse"
    case money = "Money"
    case combatRecord = "CombatRecord"
    case pureGold = "PureGold"
    case syntheticJade = "SyntheticJade"
    case originStone = "OriginStone"
    case chip = "Chip"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notUse: "不使用"
        case .money: "贸易站 · 龙门币"
        case .combatRecord: "制造站 · 作战记录"
        case .pureGold: "制造站 · 赤金"
        case .syntheticJade: "贸易站 · 合成玉"
        case .originStone: "制造站 · 源石碎片"
        case .chip: "制造站 · 芯片"
        }
    }
}

public enum TaskSettingsMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case maaDefault
    case custom

    public var id: String { rawValue }
}

public struct FightConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var settingsMode = TaskSettingsMode.custom
    public var stage = ""
    public var medicine: Int?
    public var expiringMedicine: Int?
    public var stone: Int?
    public var times: Int?
    public var series: Int?
    public var drGrandet = false

    public init() {}

    public var usesCustomSettings: Bool {
        get { settingsMode == .custom }
        set { settingsMode = newValue ? .custom : .maaDefault }
    }
}

public struct RecruitConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var settingsMode = TaskSettingsMode.custom
    public var refresh = true
    public var times = 4
    public var expedite = false
    public var autoConfirm3 = true
    public var autoConfirm4 = true
    public var autoConfirm5 = false
    public var autoConfirm6 = false
    public var preserveRobot = true

    public init() {}

    public var usesCustomSettings: Bool {
        get { settingsMode == .custom }
        set { settingsMode = newValue ? .custom : .maaDefault }
    }
}

public struct InfrastConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var settingsMode = TaskSettingsMode.custom
    public var collectManufacturing = true
    public var collectTrading = true
    public var collectReception = false
    public var drones = DroneUsage.money

    public init() {}

    public var usesCustomSettings: Bool {
        get { settingsMode == .custom }
        set { settingsMode = newValue ? .custom : .maaDefault }
    }
}

public struct AwardConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var settingsMode = TaskSettingsMode.custom
    public var dailyWeekly = true
    public var mail = false
    public var freeRecruit = false
    public var orundum = false
    public var mining = false

    public init() {}

    public var usesCustomSettings: Bool {
        get { settingsMode == .custom }
        set { settingsMode = newValue ? .custom : .maaDefault }
    }
}

public struct AccountConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var accountSelector: String
    public var enabled: Bool
    public var stepOrder: [TaskKind]
    public var fight: FightConfiguration
    public var recruit: RecruitConfiguration
    public var infrast: InfrastConfiguration
    public var award: AwardConfiguration

    public init(
        id: UUID = UUID(),
        name: String,
        accountSelector: String = "",
        enabled: Bool = true,
        stepOrder: [TaskKind] = TaskKind.allCases,
        fight: FightConfiguration = .init(),
        recruit: RecruitConfiguration = .init(),
        infrast: InfrastConfiguration = .init(),
        award: AwardConfiguration = .init()
    ) {
        self.id = id
        self.name = name
        self.accountSelector = accountSelector
        self.enabled = enabled
        self.stepOrder = stepOrder
        self.fight = fight
        self.recruit = recruit
        self.infrast = infrast
        self.award = award
    }

    public func isEnabled(_ task: TaskKind) -> Bool {
        switch task {
        case .fight: fight.enabled
        case .recruit: recruit.enabled
        case .infrast: infrast.enabled
        case .award: award.enabled
        }
    }
}

public struct ClientConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ClientKind
    public var appPath: String
    public var address: String
    public var profileName: String
    public var bundleIdentifier: String
    public var enabled: Bool
    public var accounts: [AccountConfiguration]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ClientKind,
        appPath: String,
        address: String = "localhost:1717",
        profileName: String,
        bundleIdentifier: String? = nil,
        enabled: Bool = true,
        accounts: [AccountConfiguration]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.appPath = appPath
        self.address = address
        self.profileName = profileName
        self.bundleIdentifier = bundleIdentifier ?? kind.defaultBundleIdentifier
        self.enabled = enabled
        self.accounts = accounts
    }
}

public struct ScheduleConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var hour = 8
    public var minute = 0
    public var hotUpdateBeforeRun = true
    public var maxRetries = 1
    public var continueAfterStepFailure = true

    public init() {}
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var cliPath: String
    public var clients: [ClientConfiguration]
    public var schedule: ScheduleConfiguration

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        cliPath: String = "/opt/homebrew/bin/maa",
        clients: [ClientConfiguration],
        schedule: ScheduleConfiguration = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.cliPath = cliPath
        self.clients = clients
        self.schedule = schedule
    }

    public static var defaults: AppConfiguration {
        AppConfiguration(clients: [])
    }
}

public enum LogLevel: String, Codable, Sendable {
    case info
    case success
    case warning
    case error
}

public struct LogEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var level: LogLevel
    public var message: String
    public var clientID: UUID?
    public var accountID: UUID?
    public var task: TaskKind?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        clientID: UUID? = nil,
        accountID: UUID? = nil,
        task: TaskKind? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.clientID = clientID
        self.accountID = accountID
        self.task = task
    }
}

public enum RunnerPhase: String, Codable, Sendable {
    case idle
    case preparing
    case updating
    case launching
    case switchingAccount
    case runningTask
    case closing
    case attention
    case cancelled
    case completed
    case failed
}

public struct RunnerEvent: Sendable {
    public var phase: RunnerPhase
    public var message: String
    public var progress: Double
    public var log: LogEntry

    public init(phase: RunnerPhase, message: String, progress: Double, log: LogEntry) {
        self.phase = phase
        self.message = message
        self.progress = progress
        self.log = log
    }
}

public struct WorkflowReport: Sendable {
    public var succeededSteps: Int
    public var failedSteps: Int
    public var skippedSteps: Int
    public var attentionMessages: [String]
    public var cancelled: Bool
    public var fatalError: String?

    public init(
        succeededSteps: Int = 0,
        failedSteps: Int = 0,
        skippedSteps: Int = 0,
        attentionMessages: [String] = [],
        cancelled: Bool = false,
        fatalError: String? = nil
    ) {
        self.succeededSteps = succeededSteps
        self.failedSteps = failedSteps
        self.skippedSteps = skippedSteps
        self.attentionMessages = attentionMessages
        self.cancelled = cancelled
        self.fatalError = fatalError
    }

    public var isSuccess: Bool { !cancelled && fatalError == nil && failedSteps == 0 && attentionMessages.isEmpty }
}

public struct ExecutionState: Codable, Sendable {
    public var dateKey: String
    public var completedSteps: Set<String>
    public var updatedAt: Date

    public init(dateKey: String = "", completedSteps: Set<String> = [], updatedAt: Date = Date()) {
        self.dateKey = dateKey
        self.completedSteps = completedSteps
        self.updatedAt = updatedAt
    }
}
