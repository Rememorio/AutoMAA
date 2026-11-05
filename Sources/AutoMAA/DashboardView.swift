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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "需要处理")
            ForEach(showsAllAttention ? items : Array(items.prefix(3))) { item in
                Button { open(item.destination) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(ActivityOutcome.awaitingReview.color)
                            .frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.callout).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("查看并处理：\(item.title)")
            }
            if items.count > 3 {
                Button(showsAllAttention ? "收起" : "查看全部 \(items.count) 项") { showsAllAttention.toggle() }
                    .buttonStyle(.borderless).font(.caption)
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
        VStack(alignment: .leading, spacing: 12) {
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
                let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading),
                                    count: min(3, sessions.count))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(sessions) { session in
                        DashboardRunCard(session: session,
                            title: ActivityRecordPresentation.title(session, plans: model.configuration.plans)) {
                            if let runID = session.runID { model.showActivity(runID: runID) }
                            else { model.selection = .activity }
                        }
                    }
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

private struct DashboardRunCard: View {
    let session: ActivitySession
    let title: String
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    ActivityOutcomeLabel(outcome: session.outcome).font(.caption)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ActivityRecordPresentation.listSummary(session))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                            .monospacedDigit()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            }
            .background(Color.primary.opacity(isHovered ? 0.035 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
        .help("查看「\(title)」的完整运行结果")
    }
}
