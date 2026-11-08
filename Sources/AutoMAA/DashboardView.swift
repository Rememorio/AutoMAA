import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAllAttention = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = model.dashboardSnapshot(at: context.date)
            AppPage(width: PageLayout.readingWidth) {
                VStack(alignment: .leading, spacing: 24) {
                    header(at: context.date)
                    DashboardFocusView(summary: snapshot.focusedPlan)
                    if !snapshot.attention.isEmpty { attention(snapshot.attention) }
                    recentActivity(snapshot.recentRuns)
                    if !snapshot.upcoming.isEmpty { upcoming(snapshot.upcoming, at: context.date) }
                }
                .padding(.bottom, 16)
            }
        }
        .workspaceToolbar(title: "今日总览")
    }

    private func header(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date, format: .dateTime.month(.wide).day().weekday(.wide))
                .font(.caption).foregroundStyle(.secondary)
            Text(DashboardGreeting.resolve(at: date).title)
                .font(.system(size: 26, weight: .semibold)).accessibilityAddTraits(.isHeader)
        }
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
            summaryPanel(showsAllAttention ? items : Array(items.prefix(3))) { item in
                DashboardSummaryRow(title: item.title, detail: Text(item.detail), outcome: .awaitingReview,
                                    help: "查看并处理\(item.title)") {
                    open(item.destination)
                }
            }
        }
    }

    private func upcoming(_ plans: [DashboardPlanSummary], at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "接下来的定时")
            ForEach(plans.prefix(3)) { summary in
                Button { model.selection = .plan(summary.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "calendar").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(summary.schedule.title(relativeTo: date)).font(.callout.monospacedDigit())
                        Text(summary.plan.displayName).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("预计触发时间 · 查看方案定时设置")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentActivity(_ sessions: [ActivitySession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeading(title: "最近运行")
                ActionTextButton(title: "全部记录", symbol: "clock.arrow.circlepath", help: "查看全部运行记录") {
                    model.selection = .activity
                }
            }
            if sessions.isEmpty {
                Text("方案运行结束后，可以在这里回看结果。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                summaryPanel(sessions) { session in
                    let title = ActivityRecordPresentation.title(session, plans: model.configuration.plans)
                    let outcome = session.outcome
                    let status = Text(outcome.title).foregroundStyle(outcome == .completed ? Color.secondary : outcome.color)
                    let time = Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                    let detail = Text("\(status) · \(ActivityRecordPresentation.listSummary(session)) · \(time)")
                    DashboardSummaryRow(title: title, detail: detail, outcome: outcome, help: "查看「\(title)」的完整运行结果") {
                        if let runID = session.runID { model.showActivity(runID: runID) }
                        else { model.selection = .activity }
                    }
                }
            }
        }
    }

    private func summaryPanel<Item: Identifiable, Row: View>(
        _ items: [Item], @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        Panel {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id { Divider().padding(.leading, 32) }
                }
            }
        }
    }

    private func open(_ destination: DashboardAttentionItem.Destination) {
        switch destination {
        case let .activity(id): model.showPlanActivity(id)
        case let .readiness(id): model.readinessRequest = .init(id: id)
        case let .schedule(id): model.selection = .plan(id)
        }
    }
}

private struct DashboardSummaryRow: View {
    let title: String
    let detail: Text
    let outcome: ActivityOutcome
    let help: String
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: outcome.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(outcome.color)
                    .frame(width: 18, height: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right").font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    detail.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
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
