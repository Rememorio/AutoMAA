import Foundation
@preconcurrency import UserNotifications

public enum NotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case provisional
    case denied

    public var canDeliver: Bool {
        self == .authorized || self == .provisional
    }
}

public struct WorkflowSystemNotification: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum NotificationDeliveryResult: Equatable, Sendable {
    case delivered
    case noContent
    case unavailable
    case notAuthorized(NotificationAuthorizationState)
    case failed(String)

    public var wasDelivered: Bool {
        self == .delivered
    }

    public var failureDescription: String? {
        switch self {
        case .delivered, .noContent:
            nil
        case .unavailable:
            "当前进程无法使用 macOS 通知中心"
        case .notAuthorized(.notDetermined):
            "macOS 尚未允许此运行器发送通知"
        case .notAuthorized(.denied):
            "macOS 已关闭 AutoMAA 通知"
        case .notAuthorized(.provisional), .notAuthorized(.authorized):
            nil
        case let .failed(message):
            "macOS 通知投递失败：\(message)"
        }
    }
}

public enum WorkflowNotificationComposer {
    public static func notification(for report: WorkflowReport) -> WorkflowSystemNotification? {
        if let notification = notification(
            for: report.pendingNotificationNotices,
            suffix: issueSuffix(for: report)
        ) {
            return notification
        }
        if report.cancelled { return nil }
        if report.fatalError != nil {
            return WorkflowSystemNotification(
                title: "自动化流程已中止",
                body: "运行未能安全继续，请打开 AutoMAA 查看原因。"
            )
        }
        if !report.attentionMessages.isEmpty {
            if report.unexecutedSteps > 0 {
                return WorkflowSystemNotification(
                    title: "自动化流程部分完成",
                    body: "有 \(report.unexecutedSteps) 个步骤未执行，请打开 AutoMAA 查看活动记录。"
                )
            }
            return WorkflowSystemNotification(
                title: "自动化流程需要手动处理",
                body: "有 \(report.attentionMessages.count) 项情况需要确认，请打开 AutoMAA 查看活动记录。"
            )
        }
        if report.failedSteps > 0 {
            return WorkflowSystemNotification(
                title: "自动化流程有步骤失败",
                body: "有 \(report.failedSteps) 个步骤未完成，请打开 AutoMAA 查看活动记录。"
            )
        }
        return nil
    }

    public static func notification(for notices: [WorkflowNotice]) -> WorkflowSystemNotification? {
        notification(for: notices, suffix: "")
    }

    private static func notification(
        for notices: [WorkflowNotice],
        suffix: String
    ) -> WorkflowSystemNotification? {
        if let level = notices.compactMap(highRarityLevel).max() {
            return WorkflowSystemNotification(
                title: "公开招募发现 \(level)★ 组合",
                body: "请打开 AutoMAA 查看对应账号与识别标签。\(suffix)"
            )
        }
        guard !notices.isEmpty else { return nil }
        return WorkflowSystemNotification(
            title: "公开招募需要确认",
            body: "发现 \(notices.count) 项稀有或保留标签结果，请打开 AutoMAA 查看活动记录。\(suffix)"
        )
    }

    private static func highRarityLevel(_ notice: WorkflowNotice) -> Int? {
        guard case let .highRarityRecruit(level) = notice.kind else { return nil }
        return level
    }

    private static func issueSuffix(for report: WorkflowReport) -> String {
        if report.fatalError != nil { return " 本次流程也已中止，请一并查看原因。" }
        if report.unexecutedSteps > 0 { return " 本次流程另有 \(report.unexecutedSteps) 个步骤未执行。" }
        if !report.attentionMessages.isEmpty { return " 本次流程另有情况需要手动处理。" }
        if report.failedSteps > 0 { return " 本次流程另有 \(report.failedSteps) 个步骤未完成。" }
        return ""
    }
}

@MainActor
public final class ImportantNotificationCenter {
    private let configuredCenter: UNUserNotificationCenter?
    private let canUseSystemCenter: Bool

    public init(center: UNUserNotificationCenter? = nil) {
        configuredCenter = center
        canUseSystemCenter = center != nil || Bundle.main.bundleIdentifier?.isEmpty == false
    }

    init(center: UNUserNotificationCenter? = nil, canUseSystemCenter: Bool) {
        configuredCenter = center
        self.canUseSystemCenter = canUseSystemCenter
    }

    public func authorizationState() async -> NotificationAuthorizationState {
        guard let center else { return .denied }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .ephemeral:
            return .authorized
        case .provisional:
            return .provisional
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    @discardableResult
    public func requestAuthorization() async throws -> NotificationAuthorizationState {
        guard let center else { return .denied }
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationState()
    }

    @discardableResult
    public func post(
        report: WorkflowReport,
        planID: UUID
    ) async -> NotificationDeliveryResult {
        guard let notification = WorkflowNotificationComposer.notification(for: report) else { return .noContent }
        return await post(notification, threadIdentifier: "workflow.\(planID.uuidString.lowercased())")
    }

    @discardableResult
    public func post(
        notices: [WorkflowNotice],
        planID: UUID
    ) async -> NotificationDeliveryResult {
        guard let notification = WorkflowNotificationComposer.notification(for: notices) else { return .noContent }
        return await post(notification, threadIdentifier: "workflow.\(planID.uuidString.lowercased())")
    }

    @discardableResult
    public func postTestNotification() async -> NotificationDeliveryResult {
        await post(
            WorkflowSystemNotification(
                title: "AutoMAA 通知测试",
                body: "后台定时通知可以正常送达。"
            ),
            threadIdentifier: "notification-test"
        )
    }

    private func post(
        _ notification: WorkflowSystemNotification,
        threadIdentifier: String
    ) async -> NotificationDeliveryResult {
        guard let center else { return .unavailable }
        let state = await authorizationState()
        guard state.canDeliver else { return .notAuthorized(state) }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = threadIdentifier
        let request = UNNotificationRequest(
            identifier: "workflow-\(UUID().uuidString.lowercased())",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            return .delivered
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private var center: UNUserNotificationCenter? {
        if let configuredCenter { return configuredCenter }
        guard canUseSystemCenter else { return nil }
        return .current()
    }
}
