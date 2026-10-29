import AutoMAAKit
import Foundation

enum DashboardScheduleState: Equatable {
    case unscheduled
    case synchronizing
    case needsAttention
    case scheduled(Date)

    static func resolve(plan: AutomationPlan, isCurrent: Bool, isInstalled: Bool,
                        isSynchronizing: Bool, now: Date, calendar: Calendar = .current) -> Self {
        if isCurrent, let date = PlanScheduleFormatter.nextRunDate(plan.schedule, after: now, calendar: calendar) {
            return .scheduled(date)
        }
        if plan.schedule.enabled || isInstalled {
            return isSynchronizing ? .synchronizing : .needsAttention
        }
        return .unscheduled
    }

    func title(relativeTo now: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .unscheduled: return "未设定时"
        case .synchronizing: return "定时同步中"
        case .needsAttention: return "定时需检查"
        case let .scheduled(date):
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("Md")
            let day = calendar.isDate(date, inSameDayAs: now) ? "今天"
                : calendar.date(byAdding: .day, value: 1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } == true
                    ? "明天" : formatter.string(from: date)
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            return "\(day) \(formatter.string(from: date))"
        }
    }
}

struct DashboardPlanSummary: Identifiable {
    let plan: AutomationPlan
    let progress: PlanContinuation
    let readiness: PlanReadiness
    let runState: PlanRunState
    let schedule: DashboardScheduleState
    let accountCount: Int
    let clientCount: Int

    var id: UUID { plan.id }
    var status: DashboardPlanStatus {
        .resolve(runState: runState, progress: progress, readiness: readiness)
    }
    var scope: String {
        accountCount == 0 ? "尚未选择账号" : "\(clientCount) 个客户端 · \(accountCount) 个账号"
    }

    init(plan: AutomationPlan, configuration: AppConfiguration, progress: PlanContinuation,
         readiness: PlanReadiness, runState: PlanRunState, schedule: DashboardScheduleState) {
        self.plan = plan
        self.progress = progress
        self.readiness = readiness
        self.runState = runState
        self.schedule = schedule
        let clients = configuration.clients.filter { $0.enabled && $0.accounts.contains(where: plan.includes) }
        clientCount = clients.count
        accountCount = clients.reduce(0) { $0 + $1.accounts.filter(plan.includes).count }
    }
}

struct DashboardAttentionItem: Identifiable, Equatable {
    enum Destination: Equatable { case activity(UUID), readiness(UUID), schedule(UUID) }
    let id: String
    let title: String
    let detail: String
    let destination: Destination
}

/// Presentation data keeps the overview scoped to current checkpoints and verified schedules.
struct DashboardSnapshot {
    let plans: [DashboardPlanSummary]
    let focusedPlan: DashboardPlanSummary?
    let attention: [DashboardAttentionItem]
    let upcoming: [DashboardPlanSummary]
    let recentRuns: [ActivitySession]

    init(plans: [DashboardPlanSummary], currentPlanID: UUID?, activePlanID: UUID?, activeRunID: UUID?,
         isRunning: Bool, entries: [LogEntry]) {
        self.plans = plans
        // An unidentified external run or maintenance never borrows the idle selection.
        focusedPlan = isRunning ? plans.first { $0.id == activePlanID }
            : plans.first { $0.id == currentPlanID } ?? plans.first
        attention = Self.attentionItems(plans)
        upcoming = plans.filter { if case .scheduled = $0.schedule { true } else { false } }
            .sorted {
                guard case let .scheduled(left) = $0.schedule, case let .scheduled(right) = $1.schedule else { return false }
                return left < right
            }
        recentRuns = Array(ActivityHistory.sessions(from: entries).filter {
            $0.planID != nil && !(isRunning && activeRunID != nil && $0.runID == activeRunID)
        }.prefix(3))
    }

    private static func attentionItems(_ plans: [DashboardPlanSummary]) -> [DashboardAttentionItem] {
        var results: [DashboardAttentionItem] = []
        var configuration: [DashboardAttentionItem] = []
        var schedules: [DashboardAttentionItem] = []
        var issueIDs: Set<String> = []
        for summary in plans {
            let progress = summary.progress
            if progress.unconfirmed > 0 || !progress.fightRecoveryItems.isEmpty {
                results.append(.init(id: "result/\(summary.id)",
                    title: progress.unconfirmed > 0 ? "\(progress.unconfirmed) 项结果待确认" : "作战需要处理",
                    detail: summary.plan.displayName, destination: .activity(summary.id)))
            }
            for issue in summary.readiness.directIssues + summary.readiness.externalBlockers where issue.severity == .error {
                let scope = if case let .plan(id) = issue.scope { id.uuidString } else { "shared" }
                let key = "configuration/\(scope)/\(issue.id)"
                guard issueIDs.insert(key).inserted else { continue }
                let shared = issue.scope == .shared
                let owner = if case let .plan(id) = issue.scope { plans.first { $0.id == id } ?? summary } else { summary }
                configuration.append(.init(id: key,
                    title: issue.id == "maa-cli-missing" ? "找不到可执行的 maa-cli" : issue.message,
                    detail: shared ? "运行前检查" : owner.plan.displayName,
                    destination: .readiness(owner.id)))
            }
            if summary.schedule == .needsAttention {
                schedules.append(.init(id: "schedule/\(summary.id)", title: "定时需检查",
                    detail: summary.plan.displayName, destination: .schedule(summary.id)))
            }
        }
        return results + configuration + schedules
    }
}

@MainActor
extension AppModel {
    func dashboardSnapshot(at date: Date) -> DashboardSnapshot {
        let summaries = configuration.plans.map { plan in
            DashboardPlanSummary(plan: plan, configuration: configuration,
                progress: continuation(for: plan.id, at: date), readiness: planReadiness(for: plan.id),
                runState: planRunState(planID: plan.id),
                schedule: .resolve(plan: plan, isCurrent: isPlanScheduleCurrent(plan),
                    isInstalled: installedPlanIDs.contains(plan.id), isSynchronizing: isSynchronizingSchedules, now: date))
        }
        return DashboardSnapshot(plans: summaries, currentPlanID: currentPlanID, activePlanID: activePlanID,
            activeRunID: activeRunID, isRunning: isWorkflowRunning, entries: activityEntries)
    }
}
