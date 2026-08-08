import Foundation

public enum ScheduleWeekday: String, Codable, CaseIterable, Identifiable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        case .sunday: "周日"
        }
    }

    public var shortTitle: String {
        switch self {
        case .monday: "一"
        case .tuesday: "二"
        case .wednesday: "三"
        case .thursday: "四"
        case .friday: "五"
        case .saturday: "六"
        case .sunday: "日"
        }
    }

    public var launchdValue: Int {
        switch self {
        case .monday: 1
        case .tuesday: 2
        case .wednesday: 3
        case .thursday: 4
        case .friday: 5
        case .saturday: 6
        case .sunday: 0
        }
    }

    var calendarValue: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }

    public static let everyDay = Set(Self.allCases)
    public static let weekdays = Set(Self.allCases.prefix(5))
    public static let weekend: Set<Self> = [.saturday, .sunday]

    public static func ordered(_ values: Set<Self>) -> [Self] {
        allCases.filter(values.contains)
    }
}

public struct WeeklyScheduleRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var weekdays: Set<ScheduleWeekday>
    public var hour: Int
    public var minute: Int

    public init(
        id: UUID = UUID(),
        weekdays: Set<ScheduleWeekday> = ScheduleWeekday.everyDay,
        hour: Int = 8,
        minute: Int = 0
    ) {
        self.id = id
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
    }

    private enum CodingKeys: CodingKey {
        case id, weekdays, hour, minute
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        weekdays = Set(try container.decode([ScheduleWeekday].self, forKey: .weekdays))
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ScheduleWeekday.ordered(weekdays), forKey: .weekdays)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
    }
}

public struct PlanSchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var rules: [WeeklyScheduleRule]

    public init(enabled: Bool = false, hour: Int = 8, minute: Int = 0) {
        self.enabled = enabled
        rules = [.init(hour: hour, minute: minute)]
    }

    public init(enabled: Bool, rules: [WeeklyScheduleRule]) {
        self.enabled = enabled
        self.rules = rules
    }
}

public struct WeeklyScheduleSlot: Hashable, Sendable {
    public let weekday: ScheduleWeekday
    public let hour: Int
    public let minute: Int

    public init(weekday: ScheduleWeekday, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

public enum PlanScheduleProblem: Equatable, Sendable {
    case noRules
    case duplicateRuleID
    case emptyWeekdays
    case invalidTime
    case repeatedWeekday(ScheduleWeekday)

    public func message(planName: String) -> String {
        switch self {
        case .noRules:
            "「\(planName)」至少需要保留一个定时时段"
        case .duplicateRuleID:
            "「\(planName)」的定时时段标识重复，请删除后重新添加"
        case .emptyWeekdays:
            "「\(planName)」的每个定时时段都需要选择星期"
        case .invalidTime:
            "「\(planName)」的定时时间无效"
        case let .repeatedWeekday(weekday):
            "「\(planName)」在\(weekday.title)设置了多个时段；同一方案每天最多运行一次"
        }
    }
}

public struct PlanScheduleConflict: Equatable, Sendable {
    public let firstPlanID: UUID
    public let firstPlanName: String
    public let secondPlanID: UUID
    public let secondPlanName: String
    public let slot: WeeklyScheduleSlot
}

public enum PlanScheduleValidator {
    public static func problem(in schedule: PlanSchedule) -> PlanScheduleProblem? {
        guard !schedule.rules.isEmpty else { return .noRules }
        guard Set(schedule.rules.map(\.id)).count == schedule.rules.count else { return .duplicateRuleID }
        var occupied: Set<ScheduleWeekday> = []
        for rule in schedule.rules {
            guard !rule.weekdays.isEmpty else { return .emptyWeekdays }
            guard (0...23).contains(rule.hour), (0...59).contains(rule.minute) else { return .invalidTime }
            for weekday in ScheduleWeekday.ordered(rule.weekdays) {
                guard occupied.insert(weekday).inserted else { return .repeatedWeekday(weekday) }
            }
        }
        return nil
    }

    public static func conflict(
        planID: UUID,
        schedule: PlanSchedule,
        among plans: [AutomationPlan]
    ) -> PlanScheduleConflict? {
        let candidateName = plans.first(where: { $0.id == planID })?.displayName ?? "方案"
        for plan in plans where plan.id != planID && plan.schedule.enabled {
            let occupied = Set(plan.schedule.slots)
            if let slot = schedule.slots.first(where: occupied.contains) {
                return PlanScheduleConflict(
                    firstPlanID: plan.id,
                    firstPlanName: plan.displayName,
                    secondPlanID: planID,
                    secondPlanName: candidateName,
                    slot: slot
                )
            }
        }
        return nil
    }

    static func firstConflict(in plans: [AutomationPlan]) -> PlanScheduleConflict? {
        for index in plans.indices where plans[index].schedule.enabled {
            let previous = Array(plans[..<index])
            if let conflict = conflict(
                planID: plans[index].id,
                schedule: plans[index].schedule,
                among: previous + [plans[index]]
            ) {
                return conflict
            }
        }
        return nil
    }
}

public extension PlanSchedule {
    var slots: [WeeklyScheduleSlot] {
        rules.flatMap { rule in
            ScheduleWeekday.ordered(rule.weekdays).map {
                WeeklyScheduleSlot(weekday: $0, hour: rule.hour, minute: rule.minute)
            }
        }
    }

    var scheduledWeekdays: Set<ScheduleWeekday> {
        rules.reduce(into: []) { $0.formUnion($1.weekdays) }
    }
}

public enum PlanScheduleFormatter {
    public static func summary(_ schedule: PlanSchedule) -> String {
        guard !schedule.rules.isEmpty else { return "未设置" }
        return schedule.rules.map { rule in
            "\(weekdayDescription(rule.weekdays)) \(time(hour: rule.hour, minute: rule.minute))"
        }.joined(separator: "；")
    }

    public static func nextRunLabel(
        _ schedule: PlanSchedule,
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard schedule.enabled, PlanScheduleValidator.problem(in: schedule) == nil else { return nil }
        let candidates = schedule.slots.compactMap { slot -> (Date, WeeklyScheduleSlot)? in
            var components = DateComponents()
            components.weekday = slot.weekday.calendarValue
            components.hour = slot.hour
            components.minute = slot.minute
            guard let next = calendar.nextDate(
                after: date,
                matching: components,
                matchingPolicy: .nextTime,
                direction: .forward
            ) else { return nil }
            return (next, slot)
        }
        guard let next = candidates.min(by: { $0.0 < $1.0 })?.1 else { return nil }
        return "\(next.weekday.title) \(time(hour: next.hour, minute: next.minute))"
    }

    public static func time(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private static func weekdayDescription(_ weekdays: Set<ScheduleWeekday>) -> String {
        if weekdays == ScheduleWeekday.everyDay { return "每天" }
        if weekdays == ScheduleWeekday.weekdays { return "工作日" }
        if weekdays == ScheduleWeekday.weekend { return "周末" }
        let ordered = ScheduleWeekday.ordered(weekdays)
        guard let first = ordered.first else { return "未选星期" }
        if ordered.count == 1 { return first.title }
        let indices = ordered.compactMap { ScheduleWeekday.allCases.firstIndex(of: $0) }
        if let lower = indices.first,
           let upper = indices.last,
           indices == Array(lower...upper) {
            return "\(first.title)至\(ordered.last?.title ?? first.title)"
        }
        return ordered.map(\.title).joined(separator: "、")
    }
}
