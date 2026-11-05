import AutoMAAKit
import SwiftUI

struct PlanTodaySummaryPresentation: Equatable {
    let title: String
    let scope: String?
    let remaining: String?
    let review: String?
    let needsAttention: Bool
    let guidance: String?

    init(progress: PlanContinuation, runState: PlanRunState) {
        let total = progress.resolved + progress.pending + progress.unconfirmed
        let isRunning = runState == .running
        needsAttention = !isRunning && progress.hasStarted && (progress.pending > 0 || progress.unconfirmed > 0)
        if total == 0 { title = "暂无可执行任务" }
        else if isRunning { title = "今日任务" }
        else if !progress.hasStarted { title = "今日尚未运行" }
        else if progress.pending == 0, progress.unconfirmed == 0 { title = progress.completionTitle }
        else if progress.unconfirmed > 0, progress.pending == 0 { title = "结果待核实" }
        else if progress.resolved == 0 { title = "未完成" }
        else { title = progress.manuallyHandled > 0 ? "部分处理" : "部分完成" }
        scope = progress.hasStarted && total > 0 ? "已处理 \(progress.resolved)/\(total) 项" : nil
        remaining = progress.pending > 0
            ? (progress.hasStarted ? "剩余 \(progress.pending) 项" : "\(progress.pending) 项待执行") : nil
        review = progress.unconfirmed > 0 ? "\(progress.unconfirmed) 项待核实" : nil
        if runState == .ready, progress.hasStarted, progress.pending > 0 {
            guidance = progress.unconfirmed > 0
                ? "点击顶部播放按钮继续，待核实作战会保留。"
                : "点击顶部播放按钮继续，已处理的任务会自动跳过。"
        } else { guidance = nil }
    }
}

struct PlanTodaySummary: View {
    let progress: PlanContinuation
    let runState: PlanRunState
    var showsGuidance = true

    private var presentation: PlanTodaySummaryPresentation {
        .init(progress: progress, runState: runState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if showsGuidance, let guidance = presentation.guidance {
                Text(guidance).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: showsGuidance ? 34 : 0, alignment: .topLeading)
    }

    private var summary: AttributedString {
        let value = presentation
        let warning = ActivityOutcome.partial.color
        var text = AttributedString(value.title)
        text.foregroundColor = value.needsAttention ? warning : .secondary
        for (part, attention) in [(value.scope, false), (value.remaining, value.needsAttention), (value.review, true)] {
            guard let part else { continue }
            var separator = AttributedString(" · ")
            separator.foregroundColor = .secondary
            text += separator
            var fragment = AttributedString(part)
            fragment.foregroundColor = attention ? warning : .secondary
            text += fragment
        }
        return text
    }
}
