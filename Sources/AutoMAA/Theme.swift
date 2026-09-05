import AppKit
import AutoMAAKit
import SwiftUI

extension Color {
    static let maaAction = Color(red: 0, green: 0.49, blue: 0.47)
    static let maaAccent = Color(nsColor: NSColor(name: "AutoMAA Accent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.31, green: 0.80, blue: 0.76, alpha: 1)
            : NSColor(Color.maaAction)
    })
    static let maaBlue = Color(red: 0.13, green: 0.48, blue: 0.94)
    static let panelStroke = Color.primary.opacity(0.09)
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.panelStroke, lineWidth: 1)
            }
    }
}

struct EditableDisplayNameField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.title2.weight(.bold))
                .focused($isFocused)
                .onSubmit { finishEditing() }
                .accessibilityLabel(label)

            Button {
                if isFocused {
                    finishEditing()
                } else {
                    isFocused = true
                }
            } label: {
                Image(systemName: fieldSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fieldTint)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isFocused ? "完成编辑" : "修改\(label)")
            .accessibilityLabel(isFocused ? "完成编辑" : "修改\(label)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: 380)
        .background(
            (isFocused ? Color.maaAccent.opacity(0.08) : Color.primary.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    fieldTint.opacity(isFocused || isEmpty ? 0.75 : 0.28),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if !focused { normalizeName() }
        }
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fieldSymbol: String {
        if isFocused { return "checkmark" }
        return isEmpty ? "exclamationmark" : "pencil"
    }

    private var fieldTint: Color {
        isEmpty && !isFocused ? .red : .maaAccent
    }

    private func finishEditing() {
        normalizeName()
        isFocused = false
    }

    private func normalizeName() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != text {
            text = trimmed
        }
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

struct WorkflowProgressView: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: normalizedProgress)
                .progressViewStyle(.linear)
            Text(normalizedProgress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("运行进度")
        .accessibilityValue(normalizedProgress.formatted(.percent.precision(.fractionLength(0))))
    }

    private var normalizedProgress: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }
}

struct TaskIcon: View {
    let task: TaskKind
    var enabled = true

    var body: some View {
        Image(systemName: task.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? Color.maaAccent : Color.secondary)
            .frame(width: 32, height: 32)
            .background((enabled ? Color.maaAccent : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension LogLevel {
    var color: Color {
        switch self {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    var symbol: String {
        switch self {
        case .info: "ellipsis"
        case .success: "checkmark"
        case .warning: "exclamationmark"
        case .error: "xmark"
        }
    }
}

extension RunnerPhase {
    var displayName: String {
        switch self {
        case .idle: "空闲"
        case .preparing: "准备中"
        case .updating: "更新中"
        case .launching: "启动客户端"
        case .switchingAccount: "准备账号"
        case .runningTask: "任务进行中"
        case .closing: "关闭客户端"
        case .attention: "需要手动处理"
        case .cancelled: "已停止"
        case .completed: "已完成"
        case .failed: "发生错误"
        }
    }

    var statusSymbol: String {
        switch self {
        case .idle: "circle"
        case .preparing: "slider.horizontal.3"
        case .updating: "arrow.triangle.2.circlepath"
        case .launching: "macwindow.badge.plus"
        case .switchingAccount: "person.crop.circle.badge.clock"
        case .runningTask: "checklist"
        case .closing: "rectangle.portrait.and.arrow.right"
        case .attention: "exclamationmark.triangle.fill"
        case .cancelled: "stop.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var statusTint: Color {
        switch self {
        case .attention: .orange
        case .failed: .red
        case .cancelled: .secondary
        case .completed: .green
        default: .maaAccent
        }
    }
}
