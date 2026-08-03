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

public enum WorkflowNotificationComposer {
    public static func notification(for report: WorkflowReport) -> WorkflowSystemNotification? {
        if let level = report.notices.compactMap(highRarityLevel).max() {
            return WorkflowSystemNotification(
                title: "公开招募发现 \(level)★ 组合",
                body: "请打开 AutoMAA 查看对应账号与识别标签。\(issueSuffix(for: report))"
            )
        }
        if !report.notices.isEmpty {
            return WorkflowSystemNotification(
                title: "公开招募需要确认",
                body: "发现 \(report.notices.count) 项稀有或保留标签结果，请打开 AutoMAA 查看活动记录。\(issueSuffix(for: report))"
            )
        }
        if report.cancelled { return nil }
        if report.fatalError != nil {
            return WorkflowSystemNotification(
                title: "自动化流程已中止",
                body: "运行未能安全继续，请打开 AutoMAA 查看原因。"
            )
        }
        if !report.attentionMessages.isEmpty {
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

    private static func highRarityLevel(_ notice: WorkflowNotice) -> Int? {
        guard case let .highRarityRecruit(level) = notice.kind else { return nil }
        return level
    }

    private static func issueSuffix(for report: WorkflowReport) -> String {
        if report.fatalError != nil { return " 本次流程也已中止，请一并查看原因。" }
        if !report.attentionMessages.isEmpty { return " 本次流程另有情况需要手动处理。" }
        if report.failedSteps > 0 { return " 本次流程另有 \(report.failedSteps) 个步骤未完成。" }
        return ""
    }
}

@MainActor
public final class ImportantNotificationCenter {
    private let configuredCenter: UNUserNotificationCenter?

    public init(center: UNUserNotificationCenter? = nil) {
        configuredCenter = center
    }

    public func authorizationState() async -> NotificationAuthorizationState {
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
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationState()
    }

    @discardableResult
    public func post(
        report: WorkflowReport,
        planID: UUID
    ) async throws -> Bool {
        guard let notification = WorkflowNotificationComposer.notification(for: report) else { return false }
        guard await authorizationState().canDeliver else { return false }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "workflow.\(planID.uuidString.lowercased())"
        let request = UNNotificationRequest(
            identifier: "workflow-\(UUID().uuidString.lowercased())",
            content: content,
            trigger: nil
        )
        try await center.add(request)
        return true
    }

    private var center: UNUserNotificationCenter {
        configuredCenter ?? .current()
    }
}
