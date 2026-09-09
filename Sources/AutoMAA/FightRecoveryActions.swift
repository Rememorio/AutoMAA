import AutoMAAKit
import SwiftUI

struct FightRecoveryActions: View {
    @EnvironmentObject private var model: AppModel
    let item: FightRecoveryItem
    let context: String
    @State private var confirmsWeeklyCompletion = false
    @State private var confirmsRetry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { actions }
                VStack(alignment: .leading, spacing: 9) { actions }
            }
            .controlSize(.small)
            if model.isFightRecoveryBusy {
                Text("运行或更新进行中，结束后可处理")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !model.canRun(planID: item.step.planID) {
                Text("请先完善方案的运行检查，再重新尝试作战。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("确认本周剿灭已打满？", isPresented: $confirmsWeeklyCompletion) {
            Button("确认本周已满") { model.confirmWeeklyAnnihilation(item.step) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(context)。请先确认游戏中的本周奖励已满。这只更新该账号的本周记录，所有参与方案都会跳过本周剿灭；不会启动游戏。")
        }
        .confirmationDialog("重新尝试这项作战？", isPresented: $confirmsRetry) {
            Button("重新尝试作战") { model.runPlan(item.step.planID, retryStep: item.step) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(context)。\(model.fightRetryHint(item.step))本次仅处理该账号的理智作战。")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if item.canConfirmWeeklyCompletion {
            Button("已打满本周剿灭…") { confirmsWeeklyCompletion = true }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(model.isFightRecoveryBusy)
        }
        Button("重新尝试作战…") { confirmsRetry = true }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(!model.canRun(planID: item.step.planID))
    }
}

struct FightRecoveryRow: View {
    let item: FightRecoveryItem
    let context: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(item.title, systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            Text(context).font(.callout).textSelection(.enabled)
            Text(item.result.reason?.title ?? "请检查游戏中的作战结果，再选择如何继续。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FightRecoveryActions(item: item, context: context)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
