import SwiftUI

struct WorkspaceToolbarRunControls: View {
    @EnvironmentObject private var model: AppModel

    @MainActor
    static func isVisible(in _: AppModel) -> Bool { true }

    var body: some View {
        HStack(spacing: 10) {
            if model.isWorkflowRunning {
                runningStatus
            } else {
                Color.clear.frame(width: 132, height: 28).accessibilityHidden(true)
            }
            Group {
                if model.isWorkflowRunning {
                    stopButton
                } else if let planID = Self.planID(in: model) {
                    PlanRunControl(planID: planID, isToolbar: true)
                } else {
                    Button {} label: {
                        Label("选择方案后运行", systemImage: "play.fill")
                    }
                    .buttonStyle(WorkspaceToolbarButtonStyle())
                    .foregroundStyle(.secondary).disabled(true)
                    .help("选择方案后运行")
                    .accessibilityLabel("选择方案后运行")
                }
            }
            .frame(width: 28, height: 28)
        }
        .frame(width: 170, height: 28, alignment: .trailing)
        .fixedSize()
    }

    private var runningStatus: some View {
        Button { model.showCurrentActivity() } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(runningIdentity)
                    .font(.callout.weight(.medium))
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 5) {
                    Text(model.activePhase.displayName).foregroundStyle(model.activePhase.statusTint)
                    if model.activeProgress.isFinite, model.activeProgress > 0 {
                        Text(min(model.activeProgress, 1), format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 132, height: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(runningIdentity) · \(model.activeStatusMessage) · 查看运行记录")
        .accessibilityLabel("当前运行：\(runningIdentity)，\(model.activePhase.displayName)，查看运行记录")
        .accessibilityValue(progressDescription)
    }

    private var stopButton: some View {
        Button { model.cancelCurrentOperation() } label: {
            Label(stopTitle, systemImage: model.isCancellingRun ? "hourglass" : "stop.fill")
        }
        .buttonStyle(WorkspaceToolbarButtonStyle())
        .disabled(!model.canCancelRun || model.isCancellingRun)
        .help(stopHelp)
        .accessibilityLabel("\(stopTitle) · \(runningIdentity)")
    }

    private var runningIdentity: String {
        if let planID = model.activePlanID {
            return model.configuration.plans.first { $0.id == planID }?.displayName ?? "运行中的方案"
        }
        return model.isExternalRunActive ? "后台任务" : "MAA 维护"
    }

    private var stopTitle: String {
        if model.isCancellingRun { return "正在停止" }
        return model.activePlanID == nil && !model.isExternalRunActive ? "取消更新" : "安全停止"
    }

    private var stopHelp: String {
        if model.isCancellingRun { return "等待当前操作停止并清理连接" }
        guard model.canCancelRun else { return "当前操作未提供可用的停止控制" }
        return "\(stopTitle) · \(runningIdentity)"
    }

    private var progressDescription: String {
        guard model.activeProgress.isFinite, model.activeProgress > 0 else { return "" }
        return min(model.activeProgress, 1).formatted(.percent.precision(.fractionLength(0)))
    }

    @MainActor
    private static func planID(in model: AppModel) -> UUID? {
        switch model.selection {
        case let .plan(id): id
        case .activity:
            if case let .plan(id) = model.activitySelection { id } else { nil }
        default: nil
        }
    }
}
