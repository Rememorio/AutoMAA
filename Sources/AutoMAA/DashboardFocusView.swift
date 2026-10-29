import AutoMAAKit
import SwiftUI

struct DashboardFocusView: View {
    @EnvironmentObject private var model: AppModel
    let summary: DashboardPlanSummary?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                if model.isWorkflowRunning {
                    running
                } else if let summary {
                    ready(summary)
                } else {
                    Text("从一份日常方案开始").font(.headline)
                    Text("配置任务和账号，准备好后即可运行。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
                        .buttonStyle(.borderedProminent).tint(.maaAction)
                }
            }
            .padding(8)
        }
    }

    private func ready(_ summary: DashboardPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前方案").font(.caption).foregroundStyle(.secondary)
                    Text(summary.plan.displayName).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text(summary.scope).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.configuration.plans.count > 1 {
                    Picker("切换方案", selection: Binding(get: { summary.id }, set: { model.selectCurrentPlan($0) })) {
                        ForEach(model.configuration.plans) { plan in Text(plan.displayName).tag(plan.id) }
                    }
                    .labelsHidden().frame(maxWidth: 180).help("切换当前方案")
                }
            }
            Text(summary.plan.enabledTasks.isEmpty ? "尚未启用任务" : summary.plan.enabledTasks.map(\.title).joined(separator: "  →  "))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                PlanRunControl(planID: summary.id, showsTitle: true)
                Spacer(minLength: 8)
                Button { openStatus(summary) } label: {
                    Label(summary.status.title, systemImage: "chevron.right")
                        .font(.caption).foregroundStyle(summary.status.tone.color)
                }
                .buttonStyle(.borderless)
                .help(summary.status.destination == .readiness ? "查看运行前检查" : "查看本方案今日事项")
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前运行").font(.caption).foregroundStyle(.secondary)
                    Text(summary?.plan.displayName ?? (model.isExternalRunActive ? "后台任务" : "MAA 维护"))
                        .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                Label(model.activePhase.displayName, systemImage: model.activePhase.statusSymbol)
                    .font(.callout).foregroundStyle(model.activePhase.statusTint)
            }
            Text(model.activeStatusMessage).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.activePlanID != nil {
                WorkflowProgressView(progress: model.activeProgress)
            } else if let activity = model.maaUpdateActivity, !activity.isFinished {
                Text("已用时 \(activity.startedAt, style: .timer) · 上限 \(UpdatePolicy.durationDescription(activity.timeout))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                OperationStopControl(showsTitle: true).controlSize(.large)
                Spacer()
                ActionTextButton(title: "查看运行", symbol: "arrow.right", help: "查看当前运行的过程与结果") {
                    model.showCurrentActivity()
                }
            }
        }
    }

    private func openStatus(_ summary: DashboardPlanSummary) {
        if summary.status.destination == .readiness { model.readinessRequest = .init(id: summary.id) }
        else { model.showPlanActivity(summary.id) }
    }
}

extension DashboardPlanStatus.Tone {
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .active: .maaAccent
        case .attention: .orange
        case .success: .green
        }
    }
}
