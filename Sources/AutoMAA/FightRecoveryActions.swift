import AutoMAAKit
import SwiftUI

enum FightRecoveryDestination: Identifiable {
    case review(FightRecoveryItem)
    case stage(FightStageEditorContext)

    var id: String {
        switch self {
        case let .review(item): "review/\(item.id)"
        case let .stage(context): "stage/\(context.id)"
        }
    }
}

extension FightRecoveryItem {
    var reviewsWeekly: Bool {
        result.reason == .navigationUnavailable || result.kind == .annihilation
            || FightStagePolicy.isAnnihilation(result.stage ?? "")
    }

    var reviewTitle: String {
        if reviewsWeekly { return "核实本周剿灭" }
        return result.status == .failed ? "处理作战" : "核实作战结果"
    }

    func usesAccountStageEditor(in fight: FightConfiguration?) -> Bool {
        result.reason == .missingRegularTarget && !(fight?.usesCustomSettings == true && fight?.stageStrategy == .fixed)
    }

    func actionTitle(in fight: FightConfiguration?) -> String {
        if result.reason == .missingRegularTarget {
            return usesAccountStageEditor(in: fight) ? "设置常规目标" : "调整固定关卡"
        }
        return reviewTitle
    }

    var reviewReason: String {
        if reviewsWeekly, result.reason == .navigationUnavailable {
            return "未能确认剿灭入口，请在游戏中检查本周奖励进度。"
        }
        return result.reason?.title ?? "请先检查游戏中的作战结果。"
    }
}

struct FightRecoveryRow: View {
    @EnvironmentObject private var model: AppModel
    let item: FightRecoveryItem
    let context: String

    private var actionTitle: String {
        if item.result.reason == .missingRegularTarget {
            let fight = model.configuration.plans.first { $0.id == item.step.planID }?.fight
            return item.actionTitle(in: fight) + (item.usesAccountStageEditor(in: fight) ? "…" : "")
        }
        if model.canOpenFightStageSettings(for: item.step) { return "调整关卡设置" }
        return item.reviewTitle + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.reviewReason).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ActionTextButton(title: actionTitle, symbol: item.result.reason == .missingRegularTarget ? "scope" : "arrow.right",
                             help: "\(actionTitle) · \(context)") { model.reviewFight(item) }
                .disabled(model.isFightRecoveryBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FightRecoveryReview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: FightRecoveryItem
    @State private var choice: Decision?

    private enum Decision: String, Hashable {
        case weeklyComplete = "本周剿灭奖励已满"
        case skipToday = "今天不再重试常规作战"
        case retry = "重新尝试这项作战"

        var actionTitle: String {
            switch self {
            case .weeklyComplete: "确认奖励已满"
            case .skipToday: "确认不再重试"
            case .retry: "重新尝试作战"
            }
        }
    }

    private var choices: [Decision] {
        var values: [Decision] = []
        if item.canConfirmWeeklyCompletion { values.append(.weeklyComplete) }
        if item.canHandleRegularWithoutRetry { values.append(.skipToday) }
        values.append(.retry)
        return values
    }

    private var decision: Decision? { choices.count == 1 ? choices.first : choice }
    private var isCurrent: Bool { model.continuation(for: item.step.planID).fightRecoveryItems.contains(item) }
    private var context: String {
        let plan = model.configuration.plans.first { $0.id == item.step.planID }
        var parts = [plan?.displayName, model.pendingWorkContext(item.step)].compactMap { $0 }
        if let stage = item.result.stage, !stage.isEmpty, !FightStagePolicy.isAnnihilation(stage) {
            parts.append("关卡 \(stage)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.reviewTitle).font(.headline).accessibilityAddTraits(.isHeader)
                Text(context).font(.callout).foregroundStyle(.secondary)
            }
            if !isCurrent {
                Text("这项作战的状态已变化。").font(.callout)
            } else {
                Text(item.reviewReason).font(.callout)
                if choices.count > 1 {
                    Picker("处理方式", selection: $choice) {
                        ForEach(choices, id: \.self) { value in
                            Text(value.rawValue).tag(Optional(value))
                        }
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                }
                if let decision {
                    Text(explanation(for: decision))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.isFightRecoveryBusy {
                    Text("运行或更新结束后可处理。").font(.callout).foregroundStyle(.secondary)
                } else if decision == .retry, !model.canRun(planID: item.step.planID) {
                    Text("请先修正方案的运行配置。").font(.callout).foregroundStyle(.orange)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(isCurrent ? "取消" : "关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                if isCurrent {
                    Button(decision?.actionTitle ?? "确认") {
                        guard let decision else { return }
                        switch decision {
                        case .weeklyComplete: model.confirmWeeklyAnnihilation(item)
                        case .skipToday: model.handleRegularFightWithoutRetry(item)
                        case .retry: model.retryFight(item)
                        }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(decision == nil || model.isFightRecoveryBusy
                        || (decision == .retry && !model.canRun(planID: item.step.planID)))
                }
            }
        }
        .padding(20).frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func explanation(for decision: Decision) -> String {
        switch decision {
        case .weeklyComplete:
            "请确认游戏中的本周奖励已满。保存后，所有参与方案都会跳过该账号的本周剿灭。"
        case .skipToday:
            "保留原始未确认记录，今天跳过本方案中该账号的常规作战。其他任务和每周剿灭照常执行。"
        case .retry:
            "仅重试该账号的理智作战。\(model.fightRetryHint(item.step))"
        }
    }
}
