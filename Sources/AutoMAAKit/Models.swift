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
        case .official: "简中服 · 官服"
        case .bilibili: "简中服 · Bilibili"
        case .txwy: "繁中服"
        case .yoStarEN: "英文服"
        case .yoStarJP: "日文服"
        case .yoStarKR: "韩文服"
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
    case mall
    case award

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fight: "理智作战"
        case .recruit: "公开招募"
        case .infrast: "基建"
        case .mall: "信用与购物"
        case .award: "领取奖励"
        }
    }

    public var symbol: String {
        switch self {
        case .fight: "bolt.fill"
        case .recruit: "person.crop.rectangle.stack.fill"
        case .infrast: "building.2.fill"
        case .mall: "cart.fill"
        case .award: "gift.fill"
        }
    }
}

public enum FightStagePreset: String, CaseIterable, Identifiable, Sendable {
    case currentOrLast = ""
    case oneSeven = "1-7"
    case lmd = "CE-6"
    case battleRecord = "LS-6"
    case redCertificate = "AP-5"
    case skillSummary = "CA-5"
    case carbon = "SK-5"
    case annihilation = "Annihilation"
    case chernobog = "Chernobog@Annihilation"
    case lungmenOutskirts = "LungmenOutskirts@Annihilation"
    case lungmenDowntown = "LungmenDowntown@Annihilation"
    case obsidianFestival = "OF-1"
    case obsidianFestivalFarm = "OF-F3"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentOrLast: "当前/上次"
        case .oneSeven: "1-7"
        case .lmd: "龙门币-6/5"
        case .battleRecord: "作战记录-6/5"
        case .redCertificate: "红票-5"
        case .skillSummary: "技巧概要-5"
        case .carbon: "碳素-5"
        case .annihilation: "当期剿灭"
        case .chernobog: "切尔诺伯格"
        case .lungmenOutskirts: "龙门外环"
        case .lungmenDowntown: "龙门市区"
        case .obsidianFestival: "OF-1"
        case .obsidianFestivalFarm: "OF-F3"
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

public enum InfrastMode: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fullShift = 0
    case customSchedule = 10_000
    case collectOnly = 20_000

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .fullShift: "完整换班"
        case .customSchedule: "自定义排班"
        case .collectOnly: "仅收菜"
        }
    }

    public var detail: String {
        switch self {
        case .fullShift: "MAA 单设施最优解，会处理所选设施并进行完整换班。"
        case .customSchedule: "读取 MAA 基建排班文件，并执行其中指定的方案。"
        case .collectOnly: "一键轮换模式：保留收取产物、无人机与会客室逻辑，不进行常规换班。"
        }
    }
}

public enum RecruitExtraTagsMode: Int, Codable, CaseIterable, Identifiable, Sendable {
    case standard = 0
    case alwaysThree = 1
    case moreHighRarity = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .standard: "标准选择"
        case .alwaysThree: "总是选择三个标签"
        case .moreHighRarity: "尽量选择更多高星标签"
        }
    }
}

public enum InfrastFacility: String, Codable, CaseIterable, Identifiable, Sendable {
    case manufacturing = "Mfg"
    case trading = "Trade"
    case power = "Power"
    case control = "Control"
    case reception = "Reception"
    case office = "Office"
    case dorm = "Dorm"
    case processing = "Processing"
    case training = "Training"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manufacturing: "制造站"
        case .trading: "贸易站"
        case .power: "发电站"
        case .control: "控制中枢"
        case .reception: "会客室"
        case .office: "办公室"
        case .dorm: "宿舍"
        case .processing: "加工站"
        case .training: "训练室"
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
    public var medicineExpireDays: Int?
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
    public var firstTags: [String] = []
    public var extraTagsMode = RecruitExtraTagsMode.standard
    public var preserveTags = ["支援机械"]

    public init() {}

    public var usesCustomSettings: Bool {
        get { settingsMode == .custom }
        set { settingsMode = newValue ? .custom : .maaDefault }
    }
}

public struct InfrastConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var settingsMode = TaskSettingsMode.custom
    public var mode = InfrastMode.collectOnly
    public var facilities: [InfrastFacility] = [.manufacturing, .trading, .reception]
    public var drones = DroneUsage.money
    public var threshold = 0.3
    public var replenish = false
    public var dormNotStationed = false
    public var dormTrust = false
    public var receptionMessageBoard = true
    public var receptionClueExchange = true
    public var receptionSendClue = true
    public var continueTraining = true
    public var customSchedulePath = ""
    public var customSchedulePlanIndex = 0

    public init() {}

    public static var fullShift: InfrastConfiguration {
        var value = InfrastConfiguration()
        value.mode = .fullShift
        value.facilities = InfrastFacility.allCases
        value.drones = .money
        return value
    }

    public var usesCustomSettings: Bool {
        get { settingsMode == .custom }
        set { settingsMode = newValue ? .custom : .maaDefault }
    }
}

public struct MallConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var settingsMode = TaskSettingsMode.custom
    public var visitFriends = true
    public var shopping = true
    public var buyFirst = ["招聘许可", "龙门币"]
    public var blacklist = ["加急许可", "家具零件"]
    public var forceShoppingIfCreditFull = true
    public var onlyBuyDiscount = false
    public var reserveMaxCredit = false
    public var creditFight = false
    public var formationIndex = 0

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
    public var specialAccess = false

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

    public init(
        id: UUID = UUID(),
        name: String,
        accountSelector: String = "",
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.accountSelector = accountSelector
        self.enabled = enabled
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
        address: String = "127.0.0.1:1717",
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

public struct PlanSchedule: Codable, Equatable, Sendable {
    public var enabled = false
    public var hour = 8
    public var minute = 0

    public init(enabled: Bool = false, hour: Int = 8, minute: Int = 0) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
    }
}

public struct ExecutionPolicy: Codable, Equatable, Sendable {
    public var hotUpdateBeforeRun = true
    public var maxRetries = 1
    public var continueAfterStepFailure = true

    public init() {}
}

public struct AutomationPlan: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var includesAllEnabledAccounts: Bool
    public var accountIDs: Set<UUID>
    public var stepOrder: [TaskKind]
    public var fight: FightConfiguration
    public var recruit: RecruitConfiguration
    public var infrast: InfrastConfiguration
    public var mall: MallConfiguration
    public var award: AwardConfiguration
    public var schedule: PlanSchedule
    public var policy: ExecutionPolicy

    public init(
        id: UUID = UUID(),
        name: String,
        includesAllEnabledAccounts: Bool = true,
        accountIDs: Set<UUID> = [],
        stepOrder: [TaskKind] = TaskKind.allCases,
        fight: FightConfiguration = .init(),
        recruit: RecruitConfiguration = .init(),
        infrast: InfrastConfiguration = .init(),
        mall: MallConfiguration = .init(),
        award: AwardConfiguration = .init(),
        schedule: PlanSchedule = .init(),
        policy: ExecutionPolicy = .init()
    ) {
        self.id = id
        self.name = name
        self.includesAllEnabledAccounts = includesAllEnabledAccounts
        self.accountIDs = accountIDs
        self.stepOrder = stepOrder
        self.fight = fight
        self.recruit = recruit
        self.infrast = infrast
        self.mall = mall
        self.award = award
        self.schedule = schedule
        self.policy = policy
    }

    public func isEnabled(_ task: TaskKind) -> Bool {
        switch task {
        case .fight: fight.enabled
        case .recruit: recruit.enabled
        case .infrast: infrast.enabled
        case .mall: mall.enabled
        case .award: award.enabled
        }
    }

    public func includes(_ account: AccountConfiguration) -> Bool {
        account.enabled && (includesAllEnabledAccounts || accountIDs.contains(account.id))
    }

    public var enabledTasks: [TaskKind] {
        stepOrder.filter(isEnabled)
    }

    public static var lightRoutine: AutomationPlan {
        var mall = MallConfiguration()
        mall.enabled = false
        return AutomationPlan(
            name: "轻量日常",
            infrast: .init(),
            mall: mall,
            schedule: .init(hour: 8, minute: 0)
        )
    }

    public static var completeRoutine: AutomationPlan {
        AutomationPlan(
            name: "完整日常",
            infrast: .fullShift,
            schedule: .init(hour: 20, minute: 0)
        )
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var cliPath: String
    public var clients: [ClientConfiguration]
    public var plans: [AutomationPlan]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        cliPath: String = "/opt/homebrew/bin/maa",
        clients: [ClientConfiguration],
        plans: [AutomationPlan] = [.lightRoutine, .completeRoutine]
    ) {
        self.schemaVersion = schemaVersion
        self.cliPath = cliPath
        self.clients = clients
        self.plans = plans
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
    public var planID: UUID?
    public var clientID: UUID?
    public var accountID: UUID?
    public var task: TaskKind?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        planID: UUID? = nil,
        clientID: UUID? = nil,
        accountID: UUID? = nil,
        task: TaskKind? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.planID = planID
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
