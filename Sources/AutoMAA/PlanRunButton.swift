import SwiftUI

struct PlanRunButton: View {
    @EnvironmentObject private var model: AppModel

    let planID: UUID
    var readyTitle = "运行"
    var controlSize: ControlSize = .regular

    var body: some View {
        switch model.planRunState(planID: planID) {
        case .ready:
            Button {
                model.runPlan(planID)
            } label: {
                Label(readyTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.maaAction)
            .controlSize(controlSize)
        case .running:
            disabledButton("正在运行", systemImage: "progress.indicator")
        case .anotherPlanRunning:
            disabledButton("其他方案运行中", systemImage: "clock.arrow.circlepath")
        case .maintenanceRunning:
            disabledButton("维护进行中", systemImage: "wrench.and.screwdriver")
        case .configurationIncomplete:
            disabledButton("配置未完成", systemImage: "exclamationmark.circle")
                .help("请选择该方案并查看运行检查")
        }
    }

    private func disabledButton(_ title: String, systemImage: String) -> some View {
        Button {} label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
        .disabled(true)
    }
}
