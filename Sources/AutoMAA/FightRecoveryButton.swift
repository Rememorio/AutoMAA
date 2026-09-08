import AutoMAAKit
import SwiftUI

struct FightRecoveryButton: View {
    @EnvironmentObject private var model: AppModel
    let step: WorkflowStep
    let context: String
    @State private var showsConfirmation = false

    var body: some View {
        Button("处理作战结果…") { showsConfirmation = true }
            .buttonStyle(.link).font(.caption)
            .disabled(!model.canRun(planID: step.planID))
            .confirmationDialog("处理这项理智作战", isPresented: $showsConfirmation) {
                Button("重跑本项") { model.runPlan(step.planID, retryStep: step) }
                if model.canConfirmAnnihilation(step) {
                    Button("已确认本周剿灭完成，继续常规") {
                        model.runPlan(step.planID, retryStep: step, confirmAnnihilation: true)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("\(context)。\(model.fightRetryHint(step))")
            }
    }
}
