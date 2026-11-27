import AutoMAAKit
import SwiftUI

extension PlanContinuation {
    var blockingFightAction: String? { newRoundTasks == 0 ? fightReviewAction : nil }
}

struct PlanRunControl: View {
    @EnvironmentObject private var model: AppModel
    let summary: DashboardPlanSummary
    private var planID: UUID { summary.id }

    var body: some View {
        switch summary.runState {
        case .ready:
            if summary.progress.newRoundTasks > 0 {
                titledRunButton
            } else if let action = summary.progress.blockingFightAction {
                secondaryAction(action, symbol: "exclamationmark.circle", help: actionTitle(action)) {
                    model.reviewFight(in: planID)
                }
            } else {
                unavailableRunButton("没有可执行任务")
            }
        case .running:
            unavailableRunButton("正在运行")
        case .anotherPlanRunning:
            unavailableRunButton("其他方案运行中")
        case .maintenanceRunning:
            unavailableRunButton("维护进行中")
        case .configurationIncomplete:
            secondaryAction("检查配置", symbol: "exclamationmark.circle", help: actionTitle("检查配置")) {
                model.readinessRequest = PlanReadinessRequest(id: planID)
            }
        }
    }

    private func actionTitle(_ title: String) -> String {
        "\(title) · \(summary.plan.displayName)"
    }

    private var titledRunButton: some View {
        let button = Button { model.runPlan(planID) } label: {
            Label(model.runTitle(for: planID), systemImage: "play.fill")
        }
        return button.buttonStyle(.borderedProminent).tint(.maaAction).controlSize(.large)
            .help(model.runHelp(for: planID))
            .accessibilityLabel(actionTitle(model.runTitle(for: planID)))
    }

    private func unavailableRunButton(_ title: String) -> some View {
        Button {} label: {
            Label("运行新一轮", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent).tint(.maaAction).controlSize(.large)
        .disabled(true)
        .help(actionTitle(title))
        .accessibilityLabel(actionTitle(title))
    }

    private func secondaryAction(_ title: String, symbol: String, help: String,
                                 action: @escaping () -> Void) -> some View {
        ActionTextButton(title: title, symbol: symbol, tint: .orange, help: help, action: action)
    }
}
