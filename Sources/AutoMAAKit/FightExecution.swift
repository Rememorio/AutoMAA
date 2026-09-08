import Foundation

public enum FightResultStatus: String, Codable, Sendable {
    case completed, unnecessary, unconfirmed, failed
}

public enum FightKind: String, Codable, Sendable {
    case regular, annihilation
}

public enum FightStopReason: String, Codable, Sendable {
    case insufficientSanity, timesLimit, weeklyLimit, confirmedWeeklyLimit, navigationUnavailable, interruptedBattle, missingEvidence, commandFailed

    public var title: String {
        switch self {
        case .insufficientSanity: "理智不足"
        case .timesLimit: "已达到指定次数"
        case .weeklyLimit: "本周剿灭奖励已满"
        case .confirmedWeeklyLimit: "已手动确认本周剿灭完成"
        case .navigationUnavailable: "未能确认剿灭入口；请检查本周奖励或关卡页面"
        case .interruptedBattle: "作战被中断，结果未确认；请检查游戏结果"
        case .missingEvidence: "未取得有效作战结果；请检查游戏后重跑本项"
        case .commandFailed: "MAA 执行失败"
        }
    }
}

public struct FightResult: Codable, Equatable, Sendable {
    public var status: FightResultStatus
    public var stage: String?
    public var times: Int
    public var reason: FightStopReason?
    public var totalDrops: String?
    public var kind: FightKind?
    public var unrecognizedSettlements: Int?

    public init(status: FightResultStatus, stage: String? = nil, times: Int = 0,
                reason: FightStopReason? = nil, totalDrops: String? = nil, kind: FightKind? = nil,
                unrecognizedSettlements: Int? = nil) {
        self.status = status
        self.stage = stage
        self.times = times
        self.reason = reason
        self.totalDrops = totalDrops
        self.kind = kind
        self.unrecognizedSettlements = unrecognizedSettlements
    }

    public var isResolved: Bool { status == .completed || status == .unnecessary }

    public var description: String {
        let label = switch status {
        case .completed: "已完成"
        case .unnecessary: "无需作战"
        case .unconfirmed: "结果未确认"
        case .failed: "失败"
        }
        let count = times > 0 ? "（\(stage ?? "作战") × \((unrecognizedSettlements ?? 0) > 0 ? "至少 " : "")\(times)）" : ""
        return label + count + (reason.map { " · \($0.title)" } ?? "")
    }
}

public struct FightProgress: Codable, Equatable, Sendable {
    public var regularStage: String
    public var annihilation: FightResult?
    public var regular: FightResult?

    public init(regularStage: String) { self.regularStage = regularStage }
}

public struct WorkflowStep: Codable, Hashable, Sendable {
    public let planID: UUID
    public let clientID: UUID
    public let accountID: UUID
    public let task: TaskKind

    public init(planID: UUID, clientID: UUID, accountID: UUID, task: TaskKind) {
        self.planID = planID
        self.clientID = clientID
        self.accountID = accountID
        self.task = task
    }

    public var key: String { "\(planID)/\(clientID)/\(accountID)/\(task.rawValue)" }
}

/// Observations belong to one isolated maa-cli command, never a shared Core log.
struct FightObservation: Sendable {
    private(set) var stage: String?
    private(set) var times = 0
    private var awaitingSettlement = false
    private var insufficientSanity = false
    private var weeklyLimit = false
    private var navigationUnavailable = false
    private var offline = false
    private var chainFailed = false
    private var settlementKind: FightKind?
    private var kind: FightKind?
    private var nextSeries: Int?
    private var activeSeries: Int?
    private var unrecognizedSettlements = 0
    private var sanityBeforeStage: Int?
    private var insufficientAtLastCheck = false
    private var timesLimit = false

    mutating func consume(_ line: String) {
        guard let marker = line.range(of: "Assistant::append_callback | "),
              let brace = line[marker.upperBound...].firstIndex(of: "{"),
              let data = String(line[brace...]).data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["taskchain"] as? String == "Fight"
        else { return }
        let kind = line[marker.upperBound..<brace].trimmingCharacters(in: .whitespaces)
        let details = event["details"] as? [String: Any] ?? [:]
        let task = (details["task"] as? String ?? "").split(separator: "@").last.map(String.init) ?? ""
        let inFightLoop = (event["first"] as? [String]) == ["FightBegin"]
        if kind == "TaskChainError" || kind == "TaskChainStopped" { chainFailed = true }
        if kind == "SubTaskStart" {
            if task == "OfflineConfirm" { offline = true }
            if task == "StartButton2" || task == "AnnihilationConfirm" {
                awaitingSettlement = true
                settlementKind = nil
                activeSeries = nextSeries
                nextSeries = nil
                insufficientAtLastCheck = false
            }
            if inFightLoop, task == "NoStone" || task == "CloseStonePageExceeded" { insufficientSanity = true }
        }
        if kind == "SubTaskError", let first = event["first"] as? [String],
           first == ["Annihilation"], (event["pre_task"] as? String ?? "").isEmpty {
            navigationUnavailable = true
        }
        // Core's drop plugin runs before SubTaskCompleted is forwarded; capture the recognized settlement at start.
        if kind == "SubTaskStart", event["subtask"] as? String == "ProcessTask" {
            if task == "EndOfActionAnnihilation" { settlementKind = .annihilation }
            if task == "EndOfAction" { settlementKind = .regular }
        }
        guard kind == "SubTaskExtraInfo" else { return }
        if event["what"] as? String == "SanityBeforeStage" {
            sanityBeforeStage = (details["current_sanity"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
            insufficientAtLastCheck = false
        }
        if event["what"] as? String == "FightTimes" {
            insufficientAtLastCheck = false
            nextSeries = (details["series"] as? Int).flatMap { (1...10).contains($0) ? $0 : nil }
            if let sanity = sanityBeforeStage, let series = nextSeries,
               let cost = details["sanity_cost"] as? Int, cost > 0, cost % series == 0 {
                insufficientAtLastCheck = sanity < cost / series
            }
            sanityBeforeStage = nil
            timesLimit = details["finished"] as? Bool == true
        }
        if inFightLoop, event["what"] as? String == "ExceededLimit",
           ["MedicineConfirm", "StoneConfirm"].contains(task) { insufficientSanity = true }
        guard event["what"] as? String == "StageDrops" else { return }
        let limit = details["annihilation_weekly_process"] as? [Int]
        let hasWeeklyProgress = limit.map { $0.count == 2 && $0[0] >= 0 && $0[1] > 0 } == true
        if details["stage"] is [String: Any], details["drops"] is [[String: Any]] {
            // Pair the batch size with its settlement; a CLI start count alone is never completion evidence.
            let recognized = (details["cur_times"] as? Int).flatMap { (1...10).contains($0) ? $0 : nil }
            let count = recognized ?? activeSeries ?? (hasWeeklyProgress || settlementKind == .annihilation ? 1 : nil)
            times += count ?? 1
            if count == nil { unrecognizedSettlements += 1 }
            let value = (details["stage"] as? [String: Any])?["stageCode"] as? String
            stage = value?.isEmpty == false ? value : nil
            self.kind = hasWeeklyProgress ? .annihilation : settlementKind
            settlementKind = nil
            awaitingSettlement = false
            activeSeries = nil
        }
        if hasWeeklyProgress, let limit, limit[0] >= limit[1] { weeklyLimit = true }
    }

    func result(for command: CommandResult, configuredStage: String?) -> FightResult {
        let summary = MAAOutputSummaryParser.fightSummary(in: command.combinedOutput)
        let count = times
        let stage = count > 0 ? stage : summary?.stage ?? configuredStage
        // An explicit annihilation command can conservatively require recovery even on older callbacks.
        let kind = kind ?? (configuredStage.map(FightStagePolicy.isAnnihilation) == true ? .annihilation : nil)
        func result(_ status: FightResultStatus, _ reason: FightStopReason? = nil) -> FightResult {
            FightResult(status: status, stage: stage, times: count, reason: reason, totalDrops: summary?.totalDrops, kind: kind,
                        unrecognizedSettlements: unrecognizedSettlements > 0 ? unrecognizedSettlements : nil)
        }
        if command.cancelled || command.timedOut || awaitingSettlement || offline
            || StartupFailureClassifier.isGameOffline(command.combinedOutput) {
            return result(.unconfirmed, .interruptedBattle)
        }
        if command.exitCode != 0 || chainFailed {
            return count > 0 || (summary?.times ?? 0) > 0
                ? result(.unconfirmed, .interruptedBattle) : result(.failed, .commandFailed)
        }
        if navigationUnavailable { return result(.unconfirmed, .navigationUnavailable) }
        let insufficient = insufficientSanity || insufficientAtLastCheck
        if count > 0 { return result(.completed, weeklyLimit ? .weeklyLimit : timesLimit ? .timesLimit : insufficient ? .insufficientSanity : nil) }
        if weeklyLimit { return result(.unnecessary, .weeklyLimit) }
        if timesLimit { return result(.unnecessary, .timesLimit) }
        if insufficient { return result(.unnecessary, .insufficientSanity) }
        return result(.unconfirmed, .missingEvidence)
    }
}

struct FightCommandEvidence: Sendable {
    var observation = FightObservation()
    var callbacks = ""

    static func read(from root: URL) -> Self {
        var result = Self()
        for name in ["asst.bak.log", "asst.log"] {
            let url = root.appending(path: "debug/\(name)")
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            var pending = Data()
            while let data = try? handle.read(upToCount: 65_536), !data.isEmpty {
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    guard line.contains("Assistant::append_callback | ") else { continue }
                    result.observation.consume(line)
                    result.callbacks += line + "\n"
                    if result.callbacks.utf8.count > 131_072 { result.callbacks = String(result.callbacks.suffix(65_536)) }
                }
                if pending.count > 1_048_576 { pending.removeAll() }
            }
        }
        return result
    }
}

extension ExecutionState {
    public func needsFightConfirmation(_ key: String) -> Bool {
        guard fightResults?[key]?.status == .unconfirmed else { return false }
        if let progress = fightProgress?[key], progress.annihilation?.isResolved == true, progress.regular == nil { return false }
        return true
    }

    public func isResolved(_ key: String) -> Bool {
        if let result = fightResults?[key] { return result.isResolved }
        return completedSteps.contains(key)
    }

    public mutating func record(_ result: FightResult, for key: String) {
        if fightResults == nil { fightResults = [:] }
        fightResults?[key] = result
        if result.status == .completed { completedSteps.insert(key) }
        else { completedSteps.remove(key) }
        updatedAt = Date()
    }
}

public struct PlanContinuation: Equatable, Sendable {
    public var pending = 0
    public var unconfirmed = 0
    public var resolved = 0
    public var hasStarted = false

    public init(configuration: AppConfiguration, planID: UUID, state: ExecutionState, history: [LogEntry],
                now: Date = Date(), calendar: Calendar = .current) {
        guard let plan = configuration.plans.first(where: { $0.id == planID }) else { return }
        let state = state.dateKey == ExecutionStateStore.dateKey(for: now, calendar: calendar)
            ? state : ExecutionState(dateKey: "")
        hasStarted = history.contains {
            $0.planID == planID && $0.phase == .preparing && calendar.isDate($0.timestamp, inSameDayAs: now)
        }
        for client in configuration.clients where client.enabled {
            for account in client.accounts.filter(plan.includes) {
                for task in plan.enabledTasks {
                    let key = WorkflowStep(planID: planID, clientID: client.id, accountID: account.id, task: task).key
                    hasStarted = hasStarted || state.fightResults?[key] != nil
                    if state.isResolved(key) { resolved += 1 }
                    else if state.needsFightConfirmation(key) { unconfirmed += 1 }
                    else { pending += 1 }
                }
            }
        }
        hasStarted = hasStarted || resolved > 0 || unconfirmed > 0
    }
}

struct FightPersistenceError: LocalizedError {
    let details: String
    var errorDescription: String? { "作战记录保存失败，流程已停止：" + details }
}
