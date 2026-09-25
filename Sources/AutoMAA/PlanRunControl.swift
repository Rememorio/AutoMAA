import SwiftUI

struct PlanRunControl: View {
    @EnvironmentObject private var model: AppModel

    let planID: UUID
    var controlSize: ControlSize = .regular

    var body: some View {
        switch model.planRunState(planID: planID) {
        case .ready:
            let progress = model.continuation(for: planID)
            if progress.pending > 0 {
                Button { model.runPlan(planID) } label: {
                    Label(model.runTitle(for: planID), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.maaAction)
                .controlSize(controlSize)
                .help(model.runHelp(for: planID))
            } else if progress.unconfirmed > 0 {
                Button {
                    model.selectCurrentPlan(planID)
                    model.selection = .activity
                } label: {
                    Label("处理待确认结果", systemImage: "exclamationmark.circle")
                }
                .controlSize(controlSize)
            } else {
                status(progress.completionTitle, symbol: progress.manuallyHandled > 0 ? "checkmark.circle" : "checkmark.circle.fill", tint: progress.manuallyHandled > 0 ? .secondary : .green)
            }
        case .running:
            status("正在运行", symbol: "arrow.triangle.2.circlepath", tint: .maaAccent)
        case .anotherPlanRunning:
            status("其他方案运行中", symbol: "clock.arrow.circlepath")
        case .maintenanceRunning:
            status("维护进行中", symbol: "wrench.and.screwdriver")
        case .configurationIncomplete:
            Button {
                model.readinessRequest = PlanReadinessRequest(id: planID)
            } label: {
                Label("检查配置", systemImage: "exclamationmark.circle")
            }
            .controlSize(controlSize)
            .tint(.orange)
        }
    }

    private func status(_ title: String, symbol: String, tint: Color = .secondary) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }
}
