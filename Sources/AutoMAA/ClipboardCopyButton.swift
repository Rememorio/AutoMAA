import AppKit
import SwiftUI

/// Copy actions name their content and acknowledge the result without changing their layout footprint.
struct ClipboardCopyButton: View {
    let subject: String
    let text: () -> String
    @State private var didCopy: Bool?
    @State private var attempt: UUID?

    var body: some View {
        Button(action: copy) {
            ActionTextLabel(title: feedbackLabel, symbol: symbol,
                            reservedTitles: [idleLabel, successLabel, failureLabel],
                            tint: didCopy == nil ? .secondary : .primary, symbolTint: color)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(feedbackLabel)
        .task(id: attempt) {
            guard didCopy == true else { return }
            do { try await Task.sleep(for: .seconds(4)) }
            catch { return }
            didCopy = nil
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        didCopy = pasteboard.setString(text(), forType: .string)
        attempt = UUID()
    }

    private var idleLabel: String { "复制\(subject)" }
    private var successLabel: String { "已复制\(subject)" }
    private var failureLabel: String { "复制\(subject)失败" }

    private var help: String {
        switch didCopy {
        case true: "\(successLabel)，可粘贴到其他应用。"
        case false: "\(failureLabel)，点击重试。"
        case nil: idleLabel
        }
    }

    private var symbol: String {
        switch didCopy {
        case true: "checkmark"
        case false: "exclamationmark.triangle"
        case nil: "doc.on.doc"
        }
    }

    private var color: Color {
        switch didCopy {
        case true: .green
        case false: .orange
        case nil: .secondary
        }
    }

    private var feedbackLabel: String {
        switch didCopy {
        case true: successLabel
        case false: failureLabel
        case nil: idleLabel
        }
    }
}
