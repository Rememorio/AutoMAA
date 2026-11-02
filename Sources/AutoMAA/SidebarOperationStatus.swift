import SwiftUI

struct SidebarOperationStatus: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isWorkflowRunning {
                VStack(alignment: .leading, spacing: 6) {
                    Text(identity)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 6) {
                        if progress == nil {
                            ProgressView().controlSize(.mini)
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                        }
                        Text(stage).lineLimit(1)
                        Spacer(minLength: 0)
                        if let progress {
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(minHeight: 14)
                    Group {
                        if let progress {
                            ProgressView(value: progress).progressViewStyle(.linear)
                                .tint(.maaAccent)
                                .accessibilityHidden(true)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: 4)
                }
                .padding(8)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("\(identity) · \(model.activeStatusMessage)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("当前运行：\(identity)，\(stage)")
                .accessibilityValue(progressDescription)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: 68, alignment: .bottom)
        .padding(.bottom, 6)
    }

    private var identity: String {
        if let id = model.activePlanID {
            return model.configuration.plans.first { $0.id == id }?.displayName ?? "运行中的方案"
        }
        return model.isExternalRunActive ? "后台任务" : "MAA 维护"
    }

    private var stage: String {
        model.isCancellingRun ? "正在结束并清理" : model.activePhase.displayName
    }

    private var progress: Double? {
        guard !model.isCancellingRun else { return nil }
        if model.activePlanID == nil, !model.isExternalRunActive {
            return model.maaUpdateActivity?.progress?.download?.fractionCompleted
        }
        let value = model.activeProgress
        return value.isFinite && value > 0 ? min(value, 1) : nil
    }

    private var progressDescription: String {
        guard let progress else { return "进度未确定" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }
}
