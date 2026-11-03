import AutoMAAKit
import SwiftUI

struct FightRecoveryActions: View {
    @EnvironmentObject private var model: AppModel
    let item: FightRecoveryItem
    let context: String
    var onAction: (() -> Void)? = nil
    @State private var confirmsWeeklyCompletion = false
    @State private var confirmsRetry = false
    @State private var confirmsManualHandling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { actions }
                VStack(alignment: .leading, spacing: 9) { actions }
            }
            .controlSize(.regular)
            .tint(.primary)
            if model.isFightRecoveryBusy {
                Text("运行或更新进行中，结束后可处理")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !model.canRun(planID: item.step.planID) {
                Text("请先完善方案的运行检查，再重新尝试作战。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("确认本周剿灭奖励已满？", isPresented: $confirmsWeeklyCompletion) {
            Button("确认奖励已满") {
                model.confirmWeeklyAnnihilation(item.step)
                onAction?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(context)。请先确认游戏中的本周奖励已满。这只更新该账号的本周记录，所有参与方案都会跳过本周剿灭；不会启动游戏。")
        }
        .confirmationDialog("重新尝试这项作战？", isPresented: $confirmsRetry) {
            Button("重新尝试作战") {
                model.retryFight(item)
                onAction?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(context)。\(model.fightRetryHint(item.step))本次仅处理该账号的理智作战。")
        }
        .confirmationDialog("今天不再重试这项常规作战？", isPresented: $confirmsManualHandling) {
            Button("已核实，今天不再重试") {
                model.handleRegularFightWithoutRetry(item)
                onAction?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(context)。请先检查游戏结果。仅停止本方案中该账号今天的常规作战重试，保留原始未确认记录，不记为自动成功。其他任务、方案和每周剿灭不受影响；不会启动游戏。")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if item.canConfirmWeeklyCompletion {
            Button("确认本周剿灭奖励已满…") { confirmsWeeklyCompletion = true }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(model.isFightRecoveryBusy)
        }
        Button("重新尝试作战…") { confirmsRetry = true }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(!model.canRun(planID: item.step.planID))
        if item.canHandleRegularWithoutRetry {
            Button("今天不再重试…") { confirmsManualHandling = true }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(model.isFightRecoveryBusy)
        }
    }
}

struct FightRecoveryRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsReview = false
    let item: FightRecoveryItem
    let context: String
    var pendingTitle: String? = nil
    var presentsReview = false

    private var reason: String {
        item.result.reason?.title ?? "请检查游戏中的作战结果，再选择如何继续。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(item.canConfirmWeeklyCompletion && item.result.reason == .navigationUnavailable
                 ? "本周剿灭 · 待核实" : item.title)
                .font(.subheadline.weight(.semibold))
            Text(context).font(.callout).textSelection(.enabled)
            if let pendingTitle { Text("待执行：" + pendingTitle).font(.callout) }
            Text(reason)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if presentsReview, model.canOpenFightStageSettings(for: item.step) {
                Button("前往关卡设置") { model.openFightStageSettings(for: item.step) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("在自定义参数中调整关卡策略和兜底关卡")
            }
            if presentsReview {
                Button("核实结果…") { showsReview = true }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .help(model.isFightRecoveryBusy ? "运行或更新结束后可核实" : "核实 \(context) 的作战结果")
                    .disabled(model.isFightRecoveryBusy)
            } else {
                FightRecoveryActions(item: item, context: context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsReview) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("核实作战结果").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(context).font(.callout)
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
                FightRecoveryActions(item: item, context: context, onAction: { showsReview = false })
                Divider()
                HStack {
                    Spacer()
                    Button("关闭") { showsReview = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(width: 460)
        }
    }
}
