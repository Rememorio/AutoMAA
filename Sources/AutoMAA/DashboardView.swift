import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppPage(width: PageLayout.contentWidth) {
            header
            routines
            recentActivity
        }
        .navigationTitle("自动化总览")
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let greeting = DashboardGreeting.resolve(at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(model.isWorkflowRunning ? model.activeStatusMessage : greeting.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var routines: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("自动化方案", detail: "\(model.activeAccountCount) 个启用账号 · \(model.activeScheduleCount) 个定时方案")
            if model.configuration.plans.isEmpty {
                Panel {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.badge.plus")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.maaAccent)
                        Text("创建你的第一个自动化方案")
                            .font(.headline)
                        Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
                            .buttonStyle(.borderedProminent)
                            .tint(.maaAction)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .topLeading)], spacing: 12) {
                    ForEach(model.configuration.plans) { plan in
                        routineCard(plan)
                    }
                }
            }
        }
    }

    private func routineCard(_ plan: AutomationPlan) -> some View {
        let progress = model.continuation(for: plan.id)
        let readiness = model.planReadiness(for: plan.id)
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.displayName).font(.headline)
                    Spacer()
                    Button("编辑方案") { model.selection = .plan(plan.id) }
                        .tint(.secondary)
                }
                scheduleSummary(plan)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.configuration.clients.filter { $0.enabled && $0.accounts.contains(where: plan.includes) }) { client in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.displayName).font(.callout.weight(.medium))
                                Text(client.accounts.filter(plan.includes).map(\.displayName).joined(separator: "、"))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Text(plan.enabledTasks.map(\.title).joined(separator: " → "))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("客户端依次运行，关闭并释放连接后再进入下一项。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                } label: {
                    Label("\(targetCount(plan)) 个账号 · \(plan.enabledTasks.count) 个步骤", systemImage: "person.2")
                        .font(.callout).foregroundStyle(.secondary)
                }
                let issues = readiness.directIssues + readiness.externalBlockers
                if let issue = issues.first(where: { $0.severity == .error }) ?? issues.first {
                    Label(issue.message, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !readiness.hasBlockingErrors, issues.count > 1 {
                    Button("查看全部 \(issues.count) 项提醒") { model.readinessRequest = .init(id: plan.id) }
                        .tint(.orange)
                }
                if progress.unconfirmed > 0, progress.pending > 0 {
                    Button {
                        model.selectCurrentPlan(plan.id)
                        model.selection = .activity
                    } label: {
                        Label("\(progress.unconfirmed) 项结果待确认", systemImage: "exclamationmark.circle")
                    }.tint(.orange)
                }
                if progress.hasStarted, !progress.pendingItems.isEmpty {
                    let recoveryIDs = Set(progress.fightRecoveryItems.map(\.id))
                    let items = progress.pendingItems.filter { !recoveryIDs.contains($0.id) }
                    if !items.isEmpty { PendingWorkList(items: items) }
                }
                Divider()
                HStack {
                    if progress.hasStarted, progress.pending > 0 {
                        Text("\(progress.resolved) 项已处理").font(.caption).foregroundStyle(.secondary)
                    } else if !progress.hasStarted, !readiness.hasBlockingErrors {
                        Text("今日尚未运行").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PlanRunControl(planID: plan.id)
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleSummary(_ plan: AutomationPlan) -> some View {
        if model.isPlanScheduleCurrent(plan) {
            Label("下次 \(PlanScheduleFormatter.nextRunLabel(plan.schedule) ?? "已安排")", systemImage: "clock")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .help(PlanScheduleFormatter.summary(plan.schedule))
        } else if plan.schedule.enabled || model.installedPlanIDs.contains(plan.id) {
            Button {
                model.selection = .plan(plan.id)
            } label: {
                Label(model.isSynchronizingSchedules ? "正在同步定时任务" : "定时任务需要检查", systemImage: "clock.badge.exclamationmark")
            }.tint(.orange).disabled(model.isSynchronizingSchedules)
        } else {
            Label("手动运行", systemImage: "clock").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var recentActivity: some View {
        let latest = ActivityHistory.sessions(from: model.activityEntries).first
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("最近活动", detail: nil)
                Spacer()
                if latest != nil {
                    Button("查看全部") { model.selection = .activity }
                        .tint(.secondary)
                }
            }
            Panel {
                if let latest, let lastEntry = latest.entries.last {
                    HStack(spacing: 13) {
                        Image(systemName: activitySymbol(latest))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(activityTint(latest))
                            .frame(width: 34, height: 34)
                            .background(
                                activityTint(latest).opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 9)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(activityTitle(latest))
                                    .font(.callout.weight(.semibold))
                                Text(activityStatus(latest))
                                    .font(.caption)
                                    .foregroundStyle(activityTint(latest))
                            }
                            Text(lastEntry.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(lastEntry.timestamp, format: .dateTime.month().day().hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("还没有运行记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        SectionHeading(title: title, detail: detail)
    }

    private func targetCount(_ plan: AutomationPlan) -> Int {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }.count
    }

    private func activityTitle(_ session: ActivitySession) -> String {
        if let planID = session.planID,
           let plan = model.configuration.plans.first(where: { $0.id == planID }) {
            return plan.displayName
        }
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
        if session.finalPhase == .completed, session.finalLevel == .warning {
            return "exclamationmark.circle.fill"
        }
        return session.finalPhase?.statusSymbol ?? session.finalLevel.symbol
    }

    private func activityTint(_ session: ActivitySession) -> Color {
        if !isCurrentActivity(session), session.hasUnfinishedActivity { return .secondary }
        if session.finalPhase == .completed, session.finalLevel == .warning { return .orange }
        return session.finalPhase?.statusTint ?? session.finalLevel.color
    }

}
