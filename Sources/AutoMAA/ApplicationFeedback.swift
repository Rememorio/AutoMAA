import AppKit
import SwiftUI

enum ApplicationFeedbackDestination: Hashable { case workspace, settings(SettingsSection), applicationUpdate }

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

    enum Style { case toast, banner }
    enum Action: Equatable { case activity(UUID), applicationUpdate }

    let id = UUID()
    let message: String
    let tone: Tone
    let destination: ApplicationFeedbackDestination
    let style: Style
    let action: Action?
}

@MainActor
final class ApplicationFeedbackCenter: ObservableObject {
    enum PauseReason: Hashable { case hover, focus }

    @Published private(set) var notices: [ApplicationFeedback] = []
    private struct Countdown {
        var remaining: Duration
        var resumedAt: ContinuousClock.Instant?
        var pauses: Set<PauseReason> = []
    }
    private let clock = ContinuousClock()
    private let dismissalDelay: Duration
    private var countdowns: [UUID: Countdown] = [:]
    private var dismissalTasks: [UUID: Task<Void, Never>] = [:]

    init(dismissalDelay: Duration = .seconds(6)) { self.dismissalDelay = dismissalDelay }

    deinit { for task in dismissalTasks.values { task.cancel() } }

    func notice(for destination: ApplicationFeedbackDestination, style: ApplicationFeedback.Style) -> ApplicationFeedback? {
        notices.first { $0.destination == destination && $0.style == style }
    }

    @discardableResult
    func post(_ message: String, tone: ApplicationFeedback.Tone = .information,
              destination: ApplicationFeedbackDestination = .workspace,
              style: ApplicationFeedback.Style? = nil, action: ApplicationFeedback.Action? = nil) -> UUID {
        let style = style ?? (tone == .error || tone == .warning ? .banner : .toast)
        if let previous = notice(for: destination, style: style) { dismiss(id: previous.id) }
        let notice = ApplicationFeedback(message: message, tone: tone, destination: destination, style: style, action: action)
        notices.append(notice)
        if style == .toast {
            countdowns[notice.id] = Countdown(remaining: dismissalDelay)
            resumeCountdown(id: notice.id)
        }
        return notice.id
    }

    func dismiss(id: UUID) {
        dismissalTasks.removeValue(forKey: id)?.cancel()
        countdowns.removeValue(forKey: id)
        notices.removeAll { $0.id == id }
    }

    func setPaused(_ paused: Bool, id: UUID, reason: PauseReason) {
        guard var countdown = countdowns[id] else { return }
        if paused {
            if let start = countdown.resumedAt {
                countdown.remaining = max(.zero, countdown.remaining - start.duration(to: clock.now))
                countdown.resumedAt = nil
            }
            countdown.pauses.insert(reason)
            dismissalTasks.removeValue(forKey: id)?.cancel()
        } else {
            countdown.pauses.remove(reason)
        }
        countdowns[id] = countdown
        if countdown.pauses.isEmpty, countdown.resumedAt == nil { resumeCountdown(id: id) }
    }

    private func resumeCountdown(id: UUID) {
        guard var countdown = countdowns[id] else { return }
        countdown.resumedAt = clock.now
        countdowns[id] = countdown
        let deadline = clock.now.advanced(by: countdown.remaining)
        dismissalTasks[id] = Task { [weak self, clock] in
            do { try await clock.sleep(until: deadline) }
            catch { return }
            self?.dismiss(id: id)
        }
    }
}

extension View {
    func applicationFeedback(_ model: AppModel, destination: ApplicationFeedbackDestination) -> some View {
        modifier(ApplicationFeedbackPresentation(model: model, destination: destination))
    }
}

private struct ApplicationFeedbackPresentation: ViewModifier {
    @ObservedObject var model: AppModel
    let destination: ApplicationFeedbackDestination
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            ApplicationProblemRegion(center: model.feedback, destination: destination,
                saveError: model.configurationSaveError, retrySave: { model.saveNow(showConfirmation: false) })
            content.overlay(alignment: .topTrailing) {
                ApplicationToastRegion(center: model.feedback, destination: destination) { action in
                    switch action {
                    case let .activity(id): model.showActivity(runID: id)
                    case .applicationUpdate:
                        model.openApplicationUpdate()
                        openWindow(id: ApplicationUpdateView.windowID)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct ApplicationProblemRegion: View {
    @ObservedObject var center: ApplicationFeedbackCenter
    let destination: ApplicationFeedbackDestination
    let saveError: String?
    let retrySave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let saveError { ConfigurationSaveFeedback(error: saveError, retry: retrySave) }
            if let notice = center.notice(for: destination, style: .banner) {
                ApplicationFeedbackSurface(message: notice.message, tone: notice.tone) {
                    ActionIconButton(title: "关闭提示", symbol: "xmark") { center.dismiss(id: notice.id) }
                }
                .onAppear { announce(notice.message) }
                .id(notice.id)
            }
        }
    }
}

private struct ApplicationToastRegion: View {
    @ObservedObject var center: ApplicationFeedbackCenter
    let destination: ApplicationFeedbackDestination
    let performAction: (ApplicationFeedback.Action) -> Void

    var body: some View {
        if let notice = center.notice(for: destination, style: .toast) {
            ApplicationToast(notice: notice, center: center, performAction: performAction).id(notice.id)
        }
    }
}

private struct ApplicationToast: View {
    let notice: ApplicationFeedback
    @ObservedObject var center: ApplicationFeedbackCenter
    let performAction: (ApplicationFeedback.Action) -> Void
    private enum Control: Hashable { case action, close }
    @FocusState private var focus: Control?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.tone.symbol).foregroundStyle(notice.tone.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.message).font(.callout).lineLimit(2).help(notice.message)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = notice.action {
                    ActionTextButton(title: action == .applicationUpdate ? "查看更新" : "查看结果", symbol: "arrow.right") {
                        center.dismiss(id: notice.id)
                        performAction(action)
                    }
                    .focused($focus, equals: .action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActionIconButton(title: "关闭提示", symbol: "xmark") { center.dismiss(id: notice.id) }
                .focused($focus, equals: .close)
        }
        .padding(12)
        .frame(width: 336, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.5)) }
        .onHover { center.setPaused($0, id: notice.id, reason: .hover) }
        .onChange(of: focus) { _, value in center.setPaused(value != nil, id: notice.id, reason: .focus) }
        .onAppear { announce(notice.message) }
        .onDisappear {
            center.setPaused(false, id: notice.id, reason: .hover)
            center.setPaused(false, id: notice.id, reason: .focus)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ConfigurationSaveFeedback: View {
    let error: String
    let retry: () -> Void

    var body: some View {
        ApplicationFeedbackSurface(title: "配置尚未保存", message: error, tone: .warning) {
            ActionTextButton(title: "重试保存", symbol: "arrow.clockwise", action: retry)
        }
        .onAppear { announce("配置尚未保存：\(error)") }
    }
}

private struct ApplicationFeedbackSurface<Actions: View>: View {
    var title: String?
    let message: String
    let tone: ApplicationFeedback.Tone
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: tone.symbol).foregroundStyle(tone.color)
                    .frame(width: 18).padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    if let title { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(tone.color) }
                    Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private func announce(_ message: String) {
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                         userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
}
