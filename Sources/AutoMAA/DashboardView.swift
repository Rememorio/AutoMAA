import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppPage(width: PageLayout.listWidth) {
            VStack(alignment: .leading, spacing: 32) {
                header
                routines
                recentActivity
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("今日总览")
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(context.date, format: .dateTime.month(.wide).day())
                    Text(context.date, format: .dateTime.weekday(.wide))
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(DashboardGreeting.resolve(at: context.date).title)
                    .font(.system(size: 26, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if model.isWorkflowRunning {
                    Text(model.activeStatusMessage).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var routines: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("今日安排")
                .padding(.bottom, 8)
            if model.configuration.plans.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("从一份日常方案开始").font(.headline)
                    Text("配置任务和账号，准备好后即可运行。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
                        .buttonStyle(.borderedProminent).tint(.maaAction)
                        .controlSize(.small).disabled(model.isWorkflowRunning)
                }
                .padding(.vertical, 16)
            } else {
                ForEach(Array(model.configuration.plans.enumerated()), id: \.element.id) { index, plan in
                    if index > 0 { Divider() }
                    routineRow(plan)
                }
            }
        }
    }

    private func routineRow(_ plan: AutomationPlan) -> some View {
        let runState = model.planRunState(planID: plan.id)
        let status = DashboardPlanStatus.resolve(runState: runState, progress: model.continuation(for: plan.id),
                                                readiness: model.planReadiness(for: plan.id))
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(plan.displayName).font(.system(size: 16, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(targetSummary(plan)).lineLimit(1).help(targetNames(plan))
                    Text("·").accessibilityHidden(true)
                    scheduleSummary(plan)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if runState != .configurationIncomplete {
                planStatus(status, planID: plan.id, runState: runState)
            }
            HStack(spacing: 4) {
                ActionIconButton(title: "编辑「\(plan.displayName)」", symbol: "pencil") {
                    model.selection = .plan(plan.id)
                }
                PlanRunControl(planID: plan.id)
            }
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func planStatus(_ status: DashboardPlanStatus, planID: UUID, runState: PlanRunState) -> some View {
        if let destination = status.destination, !(destination == .readiness && runState == .configurationIncomplete) {
            Button {
                switch destination {
                case .activity: model.showPlanActivity(planID)
                case .readiness: model.readinessRequest = .init(id: planID)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(status.title)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(status.tone.color)
            .help(destination == .activity ? "查看本方案今日事项" : "查看本方案的提醒")
            .fixedSize()
        } else {
            Text(status.title).font(.caption).foregroundStyle(status.tone.color).fixedSize()
        }
    }

    @ViewBuilder
    private func scheduleSummary(_ plan: AutomationPlan) -> some View {
        if model.isPlanScheduleCurrent(plan) {
            Text("下次 \(PlanScheduleFormatter.nextRunLabel(plan.schedule) ?? "已安排")")
                .monospacedDigit().help(PlanScheduleFormatter.summary(plan.schedule))
        } else if plan.schedule.enabled || model.installedPlanIDs.contains(plan.id) {
            Button { model.selection = .plan(plan.id) } label: {
                Text(model.isSynchronizingSchedules ? "定时同步中" : "定时需检查")
            }
            .buttonStyle(.borderless).foregroundStyle(.orange)
            .disabled(model.isSynchronizingSchedules)
        } else {
            Text("未设定时")
        }
    }

    private var recentActivity: some View {
        let latest = ActivityHistory.sessions(from: model.activityEntries).first
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("最近运行")
                Spacer()
                if latest != nil {
                    ActionTextButton(title: "全部记录", symbol: "clock.arrow.circlepath", help: "查看全部运行记录") { model.selection = .activity }
                }
            }
            if let latest, let lastEntry = latest.entries.last {
                Button {
                    if let runID = latest.runID { model.showActivity(runID: runID) }
                    else { model.selection = .activity }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: activitySymbol(latest))
                            .font(.system(size: 15)).foregroundStyle(activityTint(latest))
                            .frame(width: 22).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activityTitle(latest)).font(.callout.weight(.medium))
                            Text(lastEntry.timestamp, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(activityStatus(latest)).font(.caption).foregroundStyle(activityTint(latest))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看这次运行的完整结果")
            } else {
                Text("还没有运行记录").font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func targetAccounts(_ plan: AutomationPlan) -> [AccountConfiguration] {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }
    }

    private func targetNames(_ plan: AutomationPlan) -> String {
        targetAccounts(plan).map(\.displayName).joined(separator: "、")
    }

    private func targetSummary(_ plan: AutomationPlan) -> String {
        let accounts = targetAccounts(plan)
        switch accounts.count {
        case 0: return "尚未选择账号"
        case 1: return accounts[0].displayName
        default: return "\(accounts.count) 个账号"
        }
    }

    private func activityTitle(_ session: ActivitySession) -> String {
        if let planID = session.planID,
           let plan = model.configuration.plans.first(where: { $0.id == planID }) { return plan.displayName }
        if session.planID != nil { return "已移除的方案" }
        return session.runID == nil ? "较早的运行记录" : "MAA 维护"
    }

    private func isCurrentActivity(_ session: ActivitySession) -> Bool {
        model.isWorkflowRunning && session.runID != nil && session.runID == model.activeRunID
    }

    private func activityStatus(_ session: ActivitySession) -> String {
        isCurrentActivity(session) ? model.activePhase.displayName : session.historyStatusTitle
    }

    private func activitySymbol(_ session: ActivitySession) -> String {
        if !isCurrentActivity(session), session.hasUnfinishedActivity { return "questionmark.circle" }
        if session.finalPhase == .completed, session.finalLevel == .warning { return "exclamationmark.circle" }
        return session.finalPhase?.statusSymbol ?? session.finalLevel.symbol
    }

    private func activityTint(_ session: ActivitySession) -> Color {
        if !isCurrentActivity(session), session.hasUnfinishedActivity { return .secondary }
        if session.finalPhase == .completed, session.finalLevel == .warning { return .orange }
        return session.finalPhase?.statusTint ?? session.finalLevel.color
    }
}

private extension DashboardPlanStatus.Tone {
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .active: .maaAccent
        case .attention: .orange
        case .success: .green
        }
    }
}
