import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAllAttention = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = model.dashboardSnapshot(at: context.date)
            AppPage(width: PageLayout.readingWidth) {
                VStack(alignment: .leading, spacing: 18) {
                    DashboardFocusView(summary: snapshot.focusedPlan, blocker: snapshot.focusedBlocker)
                    if let next = snapshot.upcoming.first { nextSchedule(next, at: context.date) }
                    if !snapshot.attention.isEmpty { attention(snapshot.attention) }
                    if !snapshot.recentRuns.isEmpty { recentActivity(snapshot.recentRuns) }
                }
            }
        }
        .workspaceToolbar(for: .overview, title: "今日总览")
    }

    private func attention(_ items: [DashboardAttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeading(title: "需要处理")
                if items.count > 3 {
                    ActionTextButton(title: showsAllAttention ? "收起" : "查看全部 \(items.count) 项",
                                     symbol: showsAllAttention ? "chevron.up" : "chevron.down",
                                     symbolAfterTitle: true) {
                        showsAllAttention.toggle()
                    }
                }
            }
            summaryRows(showsAllAttention ? items : Array(items.prefix(3))) { item in
                let account = item.accountStep.map(model.pendingWorkContext)
                DashboardSummaryRow(title: account ?? item.title, detail: Text(account == nil ? item.detail : "\(item.title) · \(item.detail)"),
                                    outcome: item.isResumable ? nil : .awaitingReview,
                                    help: item.isResumable ? "查看本轮剩余任务" : item.title) {
                    open(item.destination)
                }
            }
        }
    }

    private func nextSchedule(_ plan: DashboardPlanSummary, at date: Date) -> some View {
        Button { model.showArrangement(for: plan.id, opensAtSchedule: true) } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").accessibilityHidden(true)
                Text("下次定时")
                Text(plan.schedule.title(relativeTo: date)).monospacedDigit().foregroundStyle(.primary)
                Text(plan.plan.displayName).lineLimit(2)
                Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
            }
            .font(.callout).foregroundStyle(.secondary).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("查看方案定时设置")
    }

    private func recentActivity(_ sessions: [ActivityHistoryGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeading(title: "最近运行")
                Spacer()
                ActionTextButton(title: "全部记录", symbol: "clock.arrow.circlepath", help: "查看全部运行记录") {
                    model.showAllActivity()
                }
            }
            summaryRows(sessions) { group in
                let session = group.latest
                let title = ActivityRecordPresentation.title(session, plans: model.configuration.plans)
                let outcome = session.outcome
                let status = Text(outcome.title).foregroundStyle(outcome == .completed ? Color.secondary : outcome.color)
                let time = Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                let detail = Text("\(status) · \(ActivityRecordPresentation.listSummary(session, attempts: group.earlier.count + 1)) · \(time)")
                DashboardSummaryRow(title: title, detail: detail, outcome: outcome, help: "查看「\(title)」的完整运行结果") {
                    if let runID = session.runID { model.showActivity(runID: runID) }
                    else {
                        model.showAllActivity()
                        model.activitySelection = .session(session.id)
                    }
                }
            }
        }
    }

    private func summaryRows<Item: Identifiable, Row: View>(
        _ items: [Item], @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id { Divider().padding(.leading, 28) }
            }
        }
    }

    private func open(_ destination: DashboardAttentionItem.Destination) {
        switch destination {
        case let .reviewFight(id): model.reviewFight(in: id)
        case let .resumePlan(id): model.showPlanActivity(id)
        case let .readiness(id): model.readinessRequest = .init(id: id)
        case let .schedule(id): model.showArrangement(for: id, opensAtSchedule: true)
        }
    }
}

private struct DashboardSummaryRow: View {
    let title: String
    let detail: Text
    let outcome: ActivityOutcome?
    let help: String
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: outcome?.symbol ?? "play.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(outcome?.color ?? .secondary)
                    .frame(width: 18, height: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    detail.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.04 : 0), in: .rect(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
        .help(help)
    }
}
