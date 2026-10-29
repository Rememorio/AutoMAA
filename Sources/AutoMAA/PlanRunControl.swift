import SwiftUI

struct PlanRunControl: View {
    @EnvironmentObject private var model: AppModel
    let planID: UUID

    var body: some View {
        switch model.planRunState(planID: planID) {
        case .ready:
            let progress = model.continuation(for: planID)
            if progress.pending > 0 {
                ActionIconButton(title: actionTitle(model.runTitle(for: planID)), symbol: "play.fill",
                                 tint: .maaAccent, help: model.runHelp(for: planID)) {
                    model.runPlan(planID)
                }
            } else if progress.unconfirmed > 0 {
                ActionTextButton(title: "处理结果", symbol: "exclamationmark.circle", tint: .orange,
                                 help: actionTitle("处理待确认结果")) {
                    model.showPlanActivity(planID)
                }
            } else {
                status(progress.completionTitle,
                       symbol: progress.manuallyHandled > 0 ? "checkmark.circle" : "checkmark.circle.fill",
                       tint: progress.manuallyHandled > 0 ? .secondary : .green)
            }
        case .running:
            status("正在运行", symbol: "arrow.triangle.2.circlepath", tint: .maaAccent)
        case .anotherPlanRunning:
            status("其他方案运行中", symbol: "clock.arrow.circlepath")
        case .maintenanceRunning:
            status("维护进行中", symbol: "wrench.and.screwdriver")
        case .configurationIncomplete:
            ActionTextButton(title: "检查配置", symbol: "exclamationmark.circle", tint: .orange,
                             help: actionTitle("检查配置")) {
                model.readinessRequest = PlanReadinessRequest(id: planID)
            }
        }
    }

    private func actionTitle(_ title: String) -> String {
        let name = model.configuration.plans.first { $0.id == planID }?.displayName ?? "当前方案"
        return "\(title) · \(name)"
    }

    private func status(_ title: String, symbol: String, tint: Color = .secondary) -> some View {
        Label(actionTitle(title), systemImage: symbol)
            .labelStyle(.iconOnly)
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .help(actionTitle(title))
            .accessibilityLabel(actionTitle(title))
    }
}
