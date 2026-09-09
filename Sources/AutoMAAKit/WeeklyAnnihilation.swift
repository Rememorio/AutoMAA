import Foundation

public struct WeeklyAnnihilationConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var startDay = ScheduleWeekday.monday

    public init(enabled: Bool = false, startDay: ScheduleWeekday = .monday) {
        self.enabled = enabled
        self.startDay = startDay
    }
}

public struct GameWeek: Equatable, Sendable {
    public let start: Date
    public let weekday: ScheduleWeekday

    public init(client: ClientKind, at date: Date) {
        // maa-cli server_time_zone includes the 04:00 game-day boundary.
        let offset = switch client {
        case .official, .bilibili, .txwy: 4
        case .yoStarJP, .yoStarKR: 5
        case .yoStarEN: -11
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset * 3600)!
        let day = (calendar.component(.weekday, from: date) + 5) % 7
        weekday = ScheduleWeekday.allCases[day]
        start = calendar.date(byAdding: .day, value: -day, to: calendar.startOfDay(for: date))!
    }

    public func hasReached(_ day: ScheduleWeekday) -> Bool {
        (weekday.calendarValue + 5) % 7 >= (day.calendarValue + 5) % 7
    }
}

public enum WeeklyAnnihilationStatus: Equatable, Sendable {
    case disabled, notStarted, pending, completed, unconfirmed

    public var title: String {
        switch self {
        case .disabled: "未启用"
        case .notStarted: "未到开始日"
        case .pending: "本周待补打"
        case .completed: "本周已满"
        case .unconfirmed: "剿灭结果待确认"
        }
    }
}

public struct WeeklyAnnihilationEntry: Codable, Equatable, Sendable {
    public let clientID: UUID
    public let accountID: UUID
    public let clientKind: ClientKind
    public let weekStart: Date
    public let result: FightResult
    public let updatedAt: Date

    public var isComplete: Bool {
        result.isResolved && (result.reason == .weeklyLimit || result.reason == .confirmedWeeklyLimit)
    }
}

public struct WeeklyAnnihilationState: Codable, Equatable, Sendable {
    public var entries: [WeeklyAnnihilationEntry] = []

    public init() {}

    public func entry(clientID: UUID, accountID: UUID) -> WeeklyAnnihilationEntry? {
        entries.first { $0.clientID == clientID && $0.accountID == accountID }
    }

    public func status(for configuration: WeeklyAnnihilationConfiguration, client: ClientConfiguration,
                       accountID: UUID, at date: Date = Date()) -> WeeklyAnnihilationStatus {
        guard configuration.enabled else { return .disabled }
        let week = GameWeek(client: client.kind, at: date)
        if let entry = entry(clientID: client.id, accountID: accountID), entry.clientKind == client.kind {
            // An interrupted battle cannot become safe to repeat merely because a week changed.
            if entry.result.status == .unconfirmed { return .unconfirmed }
            if entry.weekStart == week.start, entry.isComplete { return .completed }
        }
        return week.hasReached(configuration.startDay) ? .pending : .notStarted
    }

    public func canConfirmComplete(client: ClientConfiguration, accountID: UUID, at date: Date = Date()) -> Bool {
        guard let entry = entry(clientID: client.id, accountID: accountID) else { return false }
        return entry.clientKind == client.kind && entry.weekStart == GameWeek(client: client.kind, at: date).start
            && [.unconfirmed, .unnecessary].contains(entry.result.status)
            && entry.result.times == 0 && entry.result.reason == .navigationUnavailable
    }

    public mutating func record(_ result: FightResult, client: ClientConfiguration, accountID: UUID,
                                weekStart: Date, at date: Date = Date()) {
        entries.removeAll { $0.clientID == client.id && $0.accountID == accountID }
        entries.append(.init(clientID: client.id, accountID: accountID, clientKind: client.kind,
                             weekStart: weekStart, result: result, updatedAt: date))
        entries.sort { ($0.clientID.uuidString, $0.accountID.uuidString) < ($1.clientID.uuidString, $1.accountID.uuidString) }
    }
}

public struct WeeklyAnnihilationStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) { self.directories = directories }

    public func load() throws -> WeeklyAnnihilationState {
        guard FileManager.default.fileExists(atPath: directories.weeklyAnnihilation.path) else { return .init() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(WeeklyAnnihilationState.self, from: Data(contentsOf: directories.weeklyAnnihilation))
        try validate(state)
        return state
    }

    public func save(_ state: WeeklyAnnihilationState) throws {
        try validate(state)
        try directories.prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: directories.weeklyAnnihilation, options: .atomic)
    }

    /// A confirmation updates only the weekly record; it never dispatches a workflow.
    @discardableResult
    public func confirmComplete(client: ClientConfiguration, accountID: UUID, at date: Date = Date()) throws -> WeeklyAnnihilationState {
        try directories.prepare()
        let lock = try ProcessLock(url: directories.lock)
        return try withExtendedLifetime(lock) {
            var state = try load()
            guard state.canConfirmComplete(client: client, accountID: accountID, at: date) else {
                throw WeeklyAnnihilationConfirmationError.noCurrentAttempt
            }
            state.record(.init(status: .unnecessary, stage: "Annihilation", reason: .confirmedWeeklyLimit),
                         client: client, accountID: accountID, weekStart: GameWeek(client: client.kind, at: date).start, at: date)
            try save(state)
            return state
        }
    }

    private func validate(_ state: WeeklyAnnihilationState) throws {
        var keys: Set<String> = []
        for entry in state.entries {
            guard keys.insert("\(entry.clientID)/\(entry.accountID)").inserted,
                  entry.weekStart == GameWeek(client: entry.clientKind, at: entry.weekStart).start,
                  entry.result.times >= 0 else {
                throw FightPersistenceError(details: "每周剿灭记录包含无效或重复的账号数据")
            }
        }
    }
}

public enum WeeklyAnnihilationConfirmationError: LocalizedError {
    case noCurrentAttempt

    public var errorDescription: String? { "本周剿灭状态已变化，请刷新后重新检查" }
}

extension ExecutionState {
    /// Derive executable work without erasing the independent daily regular-stage checkpoint.
    public mutating func prepareWeeklyAnnihilation(plan: AutomationPlan, clients: [ClientConfiguration],
                                                   weekly: WeeklyAnnihilationState, at date: Date = Date()) {
        guard plan.fight.enabled, plan.fight.weeklyAnnihilation.enabled else { return }
        for client in clients where client.enabled {
            for account in client.accounts.filter(plan.includes) {
                let key = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight).key
                let status = weekly.status(for: plan.fight.weeklyAnnihilation, client: client, accountID: account.id, at: date)
                if status == .unconfirmed, let entry = weekly.entry(clientID: client.id, accountID: account.id) {
                    if fightProgress == nil { fightProgress = [:] }
                    if fightProgress?[key] == nil { fightProgress?[key] = FightProgress(regularStage: "") }
                    fightProgress?[key]?.annihilation = entry.result
                    // Both targets survive if a separate regular attempt also needs confirmation.
                    let regular = fightProgress?[key]?.regular
                    record(regular?.status == .unconfirmed ? regular! : entry.result, for: key)
                } else if status == .pending {
                    let progress = fightProgress?[key]
                    if progress?.annihilation?.isResolved == true, progress?.regular?.isResolved != true { continue }
                    if let regular = progress?.regular, !regular.isResolved { continue }
                    if progress?.annihilation?.status == .unconfirmed { continue }
                    fightProgress?[key]?.annihilation = nil
                    fightResults?.removeValue(forKey: key)
                    completedSteps.remove(key)
                } else if status == .completed, fightProgress?[key]?.annihilation?.status == .unconfirmed {
                    fightProgress?[key]?.annihilation = weekly.entry(clientID: client.id, accountID: account.id)?.result
                    if let regular = fightProgress?[key]?.regular { record(regular, for: key) }
                    else { fightResults?.removeValue(forKey: key) }
                }
            }
        }
    }
}
