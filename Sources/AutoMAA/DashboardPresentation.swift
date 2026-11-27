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
    enum Destination: Equatable { case reviewFight(UUID), resumePlan(UUID), readiness(UUID), schedule(UUID) }
    let id: String
    let title: String
    let detail: String
    let destination: Destination
    var accountStep: WorkflowStep?

    var isResumable: Bool {
        if case .resumePlan = destination { return true }
        return false
    }
}

private extension ReadinessIssue {
    var dashboardID: String {
        let owner = if case let .plan(id) = scope { id.uuidString } else { "shared" }
        return "configuration/\(owner)/\(id)"
    }

    var dashboardTitle: String {
        id == "maa-cli-missing" ? "找不到可执行的 maa-cli" : message
    }
}

/// Presentation data keeps the overview scoped to current checkpoints and verified schedules.
struct DashboardSnapshot {
    let plans: [DashboardPlanSummary]
    let focusedPlan: DashboardPlanSummary?
    let focusedBlocker: String?
    let attention: [DashboardAttentionItem]
    let upcoming: [DashboardPlanSummary]
    let recentRuns: [ActivityHistoryGroup]

    init(plans: [DashboardPlanSummary], currentPlanID: UUID?, activePlanID: UUID?, activeRunID: UUID?,
         isRunning: Bool, hasClients: Bool, entries: [LogEntry]) {
        self.plans = plans
        // An unidentified external run or maintenance never borrows the idle selection.
        focusedPlan = isRunning ? plans.first { $0.id == activePlanID }
            : plans.first { $0.id == currentPlanID } ?? plans.first
        let blocker: ReadinessIssue?
        if !isRunning, hasClients, let focus = focusedPlan, focus.runState == .configurationIncomplete {
            blocker = focus.readiness.directIssues.first { $0.severity == .error } ?? focus.readiness.externalBlockers.first
        } else {
            blocker = nil
        }
        if let blocker, case let .plan(owner) = blocker.scope, owner != focusedPlan?.id,
           let other = plans.first(where: { $0.id == owner }) {
            focusedBlocker = "「\(other.plan.displayName)」：\(blocker.dashboardTitle)"
        } else {
            focusedBlocker = blocker?.dashboardTitle
        }
        upcoming = plans.filter { if case .scheduled = $0.schedule { true } else { false } }
            .sorted {
                guard case let .scheduled(left) = $0.schedule, case let .scheduled(right) = $1.schedule else { return false }
                return left < right
            }
        let history = ActivityHistory.sessions(from: entries).filter { !(isRunning && activeRunID != nil && $0.runID == activeRunID) }
        recentRuns = Array(ActivityHistoryGroup.groups(history).filter { $0.latest.planID != nil }.prefix(3))
        let onboarding = !hasClients && recentRuns.isEmpty && !isRunning
        let reviewInFocus = !isRunning && focusedPlan?.runState == .ready
            && focusedPlan?.progress.blockingFightAction != nil ? focusedPlan?.id : nil
        attention = Self.attentionItems(plans, reviewInFocus: reviewInFocus, isRunning: isRunning).filter { item in
            if onboarding, case .readiness = item.destination { return false }
            return item.id != blocker?.dashboardID
        }
    }

    private static func attentionItems(_ plans: [DashboardPlanSummary], reviewInFocus: UUID?,
                                       isRunning: Bool) -> [DashboardAttentionItem] {
        var results: [DashboardAttentionItem] = []
        var configuration: [DashboardAttentionItem] = []
        var schedules: [DashboardAttentionItem] = []
        var issueIDs: Set<String> = []
        for summary in plans {
            let progress = summary.progress
            let recovery = progress.fightRecoveryItems
            if !isRunning, summary.id != reviewInFocus,
               summary.runState == .ready || summary.runState == .configurationIncomplete,
               !recovery.isEmpty {
                let single = recovery.count == 1 ? recovery[0] : nil
                let title = if let single {
                    single.actionTitle(in: summary.plan.fight)
                } else {
                    "\(recovery.count) 项作战待处理"
                }
                results.append(.init(id: "result/\(summary.id)",
                    title: title,
                    detail: summary.plan.displayName, destination: .reviewFight(summary.id),
                    accountStep: single?.step))
            } else if !isRunning, summary.runState == .ready, progress.resumableRoundID != nil {
                results.append(.init(id: "resume/\(summary.id)", title: "本轮还有 \(progress.pending) 项可继续",
                    detail: summary.plan.displayName, destination: .resumePlan(summary.id)))
            }
            for issue in summary.readiness.directIssues + summary.readiness.externalBlockers where issue.severity == .error {
                let key = issue.dashboardID
                guard issueIDs.insert(key).inserted else { continue }
                let shared = issue.scope == .shared
                let owner = if case let .plan(id) = issue.scope { plans.first { $0.id == id } ?? summary } else { summary }
                configuration.append(.init(id: key,
                    title: issue.dashboardTitle,
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
            activeRunID: activeRunID, isRunning: isWorkflowRunning,
            hasClients: !configuration.clients.isEmpty, entries: activityEntries)
    }
}
