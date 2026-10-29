import AppKit
import SwiftUI

enum ApplicationFeedbackWindow: Sendable { case workspace, settings }

struct ApplicationFeedback: Identifiable, Equatable {
    enum Tone: Sendable {
        case information, success, warning, error

        var symbol: String {
            switch self {
            case .information: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "exclamationmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .information: .secondary
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let id = UUID()
    let message: String
    let tone: Tone
    let window: ApplicationFeedbackWindow
}

@MainActor
final class ApplicationFeedbackCenter: ObservableObject {
    @Published private(set) var notice: ApplicationFeedback?
    var activeWindow = ApplicationFeedbackWindow.workspace
    private var dismissalTask: Task<Void, Never>?
    private let dismissalDelay: Duration

    init(dismissalDelay: Duration = .seconds(6)) {
        self.dismissalDelay = dismissalDelay
    }

    func post(_ message: String, tone: ApplicationFeedback.Tone = .information) {
        dismissalTask?.cancel()
        let notice = ApplicationFeedback(message: message, tone: tone, window: activeWindow)
        self.notice = notice
        guard tone != .error, tone != .warning else { return }
        dismissalTask = Task { [weak self, dismissalDelay] in
            do { try await Task.sleep(for: dismissalDelay) }
            catch { return }
            self?.dismiss(id: notice.id)
        }
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || notice?.id == id else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        notice = nil
    }
}

struct ApplicationFeedbackRegion: View {
    @ObservedObject var center: ApplicationFeedbackCenter
    let window: ApplicationFeedbackWindow

    var body: some View {
        if let notice = center.notice, notice.window == window {
            ApplicationFeedbackSurface(message: notice.message, tone: notice.tone) {
                Button { center.dismiss(id: notice.id) } label: {
                    Label("关闭提示", systemImage: "xmark")
                        .frame(width: 20, height: 20)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help("关闭提示")
            }
        }
    }
}

struct ConfigurationSaveFeedback: View {
    let error: String
    let retry: () -> Void

    var body: some View {
        ApplicationFeedbackSurface(title: "配置尚未保存", message: error, tone: .warning) {
            ActionTextButton(title: "重试保存", symbol: "arrow.clockwise", action: retry)
        }
    }
}

private struct ApplicationFeedbackSurface<Actions: View>: View {
    var title: String?
    let message: String
    let tone: ApplicationFeedback.Tone
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: tone.symbol)
                    .foregroundStyle(tone.color)
                    .frame(width: 18).padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    if let title {
                        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(tone.color)
                    }
                    Text(message).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

/// Each native window owns one feedback region; sheets retain their parent window's destination.
struct ApplicationWindowContext: NSViewRepresentable {
    let feedback: ApplicationFeedbackCenter
    let destination: ApplicationFeedbackWindow

    func makeNSView(context: Context) -> WindowView { WindowView() }

    func updateNSView(_ view: WindowView, context: Context) {
        view.feedback = feedback
        view.destination = destination
        view.updateWindow()
    }

    final class WindowView: NSView {
        weak var feedback: ApplicationFeedbackCenter?
        var destination = ApplicationFeedbackWindow.workspace
        private weak var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindow()
        }

        func updateWindow() {
            if observedWindow !== window {
                NotificationCenter.default.removeObserver(self)
                observedWindow = window
                if let window {
                    NotificationCenter.default.addObserver(self, selector: #selector(becameKey),
                        name: NSWindow.didBecomeKeyNotification, object: window)
                }
            }
            if window?.isKeyWindow == true { becameKey() }
        }

        @objc private func becameKey() { feedback?.activeWindow = destination }
    }
}
