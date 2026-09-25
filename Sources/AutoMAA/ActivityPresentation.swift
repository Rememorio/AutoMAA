import AutoMAAKit
import Foundation

struct ActivityNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let runID: UUID
}

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all, attention, failed

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .attention: "提醒"
        case .failed: "失败"
        }
    }

    func includes(_ session: ActivitySession) -> Bool {
        switch self {
        case .all: true
        case .attention:
            session.warningCount > 0 || session.errorCount > 0 || session.finalLevel == .warning
                || session.runSummary?.isPartial == true || (session.runSummary?.pendingWeeklyAnnihilation ?? 0) > 0
                || session.finalPhase == .failed || session.finalPhase == .attention
                || session.hasUnfinishedActivity
        case .failed:
            session.finalPhase == .failed || (session.runSummary?.failedSteps ?? 0) > 0
                || (session.runSummary == nil && session.finalLevel == .error)
        }
    }
}

extension ActivitySession {
    var historyStatusTitle: String {
        let phase = finalPhase
        let level = finalLevel
        if hasUnfinishedActivity { return "未记录结束" }
        if phase == .failed { return "失败" }
        if phase == .cancelled { return "已取消" }
        if let summary = runSummary, summary.isPartial {
            if summary.manuallyHandledSteps > 0 { return "部分处理" }
            return summary.completedSteps + summary.unnecessarySteps > 0 ? "部分完成" : "未完成"
        }
        if phase == .completed, (runSummary?.manuallyHandledSteps ?? 0) > 0 { return "已处理" }
        if phase == .completed, level == .warning { return "完成 · 提醒" }
        if phase == .completed, (runSummary?.pendingWeeklyAnnihilation ?? 0) > 0 { return "本轮结束" }
        if let phase { return phase.displayName }
        return switch level {
        case .info: "运行记录"
        case .success: "已完成"
        case .warning: "需要留意"
        case .error: "发生错误"
        }
    }

    var hasUnfinishedActivity: Bool {
        guard let finalPhase else { return false }
        return ![.idle, .completed, .failed, .attention, .cancelled].contains(finalPhase)
    }
}

struct ActivityDay: Identifiable {
    let date: Date
    let sessions: [ActivitySession]
    var id: Date { date }

    static func groups(_ sessions: [ActivitySession], calendar: Calendar = .current) -> [Self] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
            .map { Self(date: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.date > $1.date }
    }
}

struct ActivityAccountSummary: Identifiable {
    struct ID: Hashable {
        let client: UUID?
        let account: UUID
    }
    let id: ID
    let lastEvent: LogEntry
    let outcomes: [LogEntry]

    static func groups(in session: ActivitySession) -> [Self] {
        var order: [ID] = []
        var entries: [ID: [LogEntry]] = [:]
        for entry in session.entries {
            guard let account = entry.accountID else { continue }
            let id = ID(client: entry.clientID, account: account)
            if entries[id] == nil { order.append(id) }
            entries[id, default: []].append(entry)
        }
        return order.compactMap { id in
            guard let values = entries[id], let last = values.last else { return nil }
            // Use recorded task outcomes; never infer completion from an informational progress message.
            var outcomes: [TaskKind: LogEntry] = [:]
            for entry in values {
                guard let task = entry.task,
                      entry.level == .success || entry.level == .error || entry.fightResult != nil else { continue }
                outcomes[task] = entry
            }
            return Self(id: id, lastEvent: last, outcomes: outcomes.values.sorted { $0.timestamp < $1.timestamp })
        }
    }
}

enum ActivitySearch {
    static func matches(_ session: ActivitySession, query: String, title: String,
                        context: (LogEntry) -> String?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query) || session.entries.contains { entry in
            entry.message.localizedCaseInsensitiveContains(query)
                || entry.details?.localizedCaseInsensitiveContains(query) == true
                || entry.task?.title.localizedCaseInsensitiveContains(query) == true
                || context(entry)?.localizedCaseInsensitiveContains(query) == true
        }
    }
}
