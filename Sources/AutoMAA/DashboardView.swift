import AppKit
import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAllAttention = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = model.dashboardSnapshot(at: context.date)
            AppPage {
                VStack(alignment: .leading, spacing: 24) {
                    header(snapshot, at: context.date)
                    DashboardFocusView(summary: snapshot.focusedPlan)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            routines(snapshot, at: context.date).frame(minWidth: 340)
                            sideColumn(snapshot, at: context.date).frame(width: 252)
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            routines(snapshot, at: context.date)
                            sideColumn(snapshot, at: context.date)
                        }
                    }
                    recentActivity(snapshot.recentRuns)
                }
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("今日总览")
    }

    private func header(_ snapshot: DashboardSnapshot, at date: Date) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(date, format: .dateTime.month(.wide).day().weekday(.wide))
                    .font(.caption).foregroundStyle(.secondary)
                Text(DashboardGreeting.resolve(at: date).title)
                    .font(.system(size: 26, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(headerDetail(snapshot, at: date))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DashboardIllustration().frame(width: 194, height: 142)
        }
    }

    private func headerDetail(_ snapshot: DashboardSnapshot, at date: Date) -> String {
        if model.isWorkflowRunning { return "运行进度和需要处理的事项，都在这里。" }
        if let next = snapshot.upcoming.first {
            return "下次定时：\(next.schedule.title(relativeTo: date)) · \(next.plan.displayName)"
        }
        return snapshot.plans.isEmpty ? "从一份日常方案开始。" : "选好方案，把日常交给 AutoMAA。"
    }

    private func routines(_ snapshot: DashboardSnapshot, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "我的方案").padding(.bottom, 10)
            if snapshot.plans.isEmpty {
                Text("添加方案后，可在这里切换和查看执行安排。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(Array(snapshot.plans.enumerated()), id: \.element.id) { index, summary in
                if index > 0 { Divider() }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button { model.selectCurrentPlan(summary.id) } label: {
                            HStack(spacing: 6) {
                                if summary.id == snapshot.focusedPlan?.id {
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Color.maaAccent)
                                }
                                Text(summary.plan.displayName).font(.callout.weight(.medium))
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(model.isWorkflowRunning)
                        .help("选择「\(summary.plan.displayName)」为当前方案")
                        .accessibilityLabel("选择方案：\(summary.plan.displayName)，\(summary.scope)")
                        Text("\(summary.scope) · \(summary.schedule.title(relativeTo: date))")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        planStatus(summary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ActionIconButton(title: "编辑「\(summary.plan.displayName)」", symbol: "pencil") {
                        model.selection = .plan(summary.id)
                    }
                    PlanRunControl(planID: summary.id)
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func planStatus(_ summary: DashboardPlanSummary) -> some View {
        if let destination = summary.status.destination {
            Button {
                switch destination {
                case .activity: model.showPlanActivity(summary.id)
                case .readiness: model.readinessRequest = .init(id: summary.id)
                }
            } label: {
                Text(summary.status.title).font(.caption).foregroundStyle(summary.status.tone.color)
            }
            .buttonStyle(.borderless)
            .help(destination == .activity ? "查看本方案今日事项" : "查看本方案的提醒")
        } else {
            Text(summary.status.title).font(.caption).foregroundStyle(summary.status.tone.color)
        }
    }

    private func sideColumn(_ snapshot: DashboardSnapshot, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "需要处理")
                if snapshot.attention.isEmpty {
                    Label("暂无待处理事项", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    ForEach(showsAllAttention ? snapshot.attention : Array(snapshot.attention.prefix(3))) { item in
                        Button { open(item.destination) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.callout).foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("查看并处理：\(item.title)")
                    }
                    if snapshot.attention.count > 3 {
                        Button(showsAllAttention ? "收起" : "查看全部 \(snapshot.attention.count) 项") { showsAllAttention.toggle() }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "接下来的定时")
                if snapshot.upcoming.isEmpty {
                    Text("暂无已生效的定时安排")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                }
                ForEach(snapshot.upcoming.prefix(3)) { summary in
                    Button { model.selection = .plan(summary.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.schedule.title(relativeTo: date)).font(.callout.monospacedDigit())
                            Text(summary.plan.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("预计触发时间 · 查看方案定时设置")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentActivity(_ sessions: [ActivitySession]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeading(title: "最近运行")
                Spacer()
                ActionTextButton(title: "全部记录", symbol: "clock.arrow.circlepath", help: "查看全部运行记录") {
                    model.selection = .activity
                }
            }
            .padding(.bottom, 8)
            if sessions.isEmpty {
                Text("方案运行结束后，可以在这里回看结果。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 { Divider() }
                Button {
                    if let runID = session.runID { model.showActivity(runID: runID) }
                    else { model.selection = .activity }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: ActivityRecordPresentation.symbol(session))
                            .foregroundStyle(ActivityRecordPresentation.tint(session)).frame(width: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ActivityRecordPresentation.title(session, plans: model.configuration.plans))
                                .font(.callout.weight(.medium))
                            Text(ActivityRecordPresentation.summary(session)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(session.historyStatusTitle).foregroundStyle(ActivityRecordPresentation.tint(session))
                            Text(session.startedAt, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                        }
                        .font(.caption).fixedSize()
                    }
                    .padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("查看这次运行的完整结果")
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

private struct DashboardIllustration: View {
    private static let image: NSImage? = Bundle.main.url(forResource: "AutoMAA-overview", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let image = Self.image { Image(nsImage: image).resizable().scaledToFit() }
            else { BrandLogo() }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}
