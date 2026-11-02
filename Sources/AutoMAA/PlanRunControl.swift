import SwiftUI

struct PlanRunControl: View {
    @EnvironmentObject private var model: AppModel
    let planID: UUID
    var showsTitle = false

    var body: some View {
        switch model.planRunState(planID: planID) {
        case .ready:
            let progress = model.continuation(for: planID)
            if progress.pending > 0 {
                if showsTitle {
                    titledRunButton
                } else {
                    ActionIconButton(title: actionTitle(model.runTitle(for: planID)), symbol: "play.fill",
                                     tint: .maaAccent, help: model.runHelp(for: planID)) {
                        model.runPlan(planID)
                    }
                }
            } else if progress.unconfirmed > 0 {
                secondaryAction("处理结果", symbol: "exclamationmark.circle", help: actionTitle("处理待确认结果")) {
                    model.showPlanActivity(planID)
                }
            } else {
                unavailableRunButton(progress.completionTitle)
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
        let name = model.configuration.plans.first { $0.id == planID }?.displayName ?? "当前方案"
        return "\(title) · \(name)"
    }

    private var titledRunButton: some View {
        let button = Button { model.runPlan(planID) } label: {
            Label(model.runTitle(for: planID, readyTitle: "运行方案"), systemImage: "play.fill")
        }
        return button.buttonStyle(.borderedProminent).tint(.maaAction).controlSize(.large)
            .help(model.runHelp(for: planID))
            .accessibilityLabel(actionTitle(model.runTitle(for: planID)))
    }

    private func unavailableRunButton(_ title: String) -> some View {
        let button = Button {} label: {
            Label(showsTitle ? "运行方案" : title, systemImage: "play.fill")
        }
        return Group {
            if showsTitle {
                button.buttonStyle(.borderedProminent).tint(.maaAction).controlSize(.large)
            } else {
                button.labelStyle(.iconOnly).frame(width: 26, height: 26)
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .disabled(true)
        .help(actionTitle(title))
        .accessibilityLabel(actionTitle(title))
    }

    private func secondaryAction(_ title: String, symbol: String, help: String,
                                 action: @escaping () -> Void) -> some View {
        ActionTextButton(title: title, symbol: symbol, tint: .orange, help: help, action: action)
    }
}
