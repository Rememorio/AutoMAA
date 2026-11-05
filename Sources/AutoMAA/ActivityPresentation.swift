import AutoMAAKit
import Foundation

struct ActivityNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let runID: UUID
}

extension LogEntry {
    var terminalOutcome: ActivityOutcome? {
        guard task == nil, clientID == nil, accountID == nil,
              phase == .completed || phase == .failed || phase == .cancelled else { return nil }
        return ActivitySession(id: id.uuidString, runID: runID, entries: [self]).outcome
    }

    var highlightsMilestone: Bool {
        guard level == .success, task == nil, accountID == nil, runSummary == nil else { return false }
        switch phase {
        case .launching, .updating: return true
        case .completed: return planID == nil
        default: return false
        }
    }
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

enum ActivityOutcome {
    case completed, handled, partial, partiallyHandled, incomplete, awaitingReview, weeklyPending
    case failed, cancelled, unfinished, recorded

    var title: String {
        switch self {
        case .completed: "已完成"
        case .handled: "已处理"
        case .partial: "部分完成"
        case .partiallyHandled: "部分处理"
        case .incomplete: "未完成"
        case .awaitingReview: "待核实"
        case .weeklyPending: "本轮结束"
        case .failed: "失败"
        case .cancelled: "已停止"
        case .unfinished: "未记录结束"
        case .recorded: "运行记录"
        }
    }

    var symbol: String {
        switch self {
        case .completed: "checkmark.circle"
        case .handled: "person.crop.circle"
        case .partial, .partiallyHandled: "circle.lefthalf.filled"
        case .incomplete: "circle.dashed"
        case .awaitingReview: "exclamationmark.circle"
        case .weeklyPending: "calendar.badge.clock"
        case .failed: "xmark.circle"
        case .cancelled: "stop.circle"
        case .unfinished: "questionmark.circle"
        case .recorded: "clock"
        }
    }
}

extension ActivitySession {
    var outcome: ActivityOutcome {
        if hasUnfinishedActivity { return .unfinished }
        if finalPhase == .failed { return .failed }
        if finalPhase == .cancelled { return .cancelled }
        if let summary = runSummary, summary.isPartial {
            if summary.manuallyHandledSteps > 0 { return .partiallyHandled }
            if summary.completedSteps + summary.unnecessarySteps > 0 { return .partial }
            if summary.failedSteps > 0 { return .failed }
            return .incomplete
        }
        if finalLevel == .error { return .failed }
        if (runSummary?.pendingWeeklyAnnihilation ?? 0) > 0 { return .weeklyPending }
        if (runSummary?.manuallyHandledSteps ?? 0) > 0 { return .handled }
        if finalPhase == .attention { return .awaitingReview }
        if finalPhase == .completed {
            return finalLevel == .warning && runSummary == nil ? .awaitingReview : .completed
        }
        return switch finalLevel {
        case .info: .recorded
        case .success: .completed
        case .warning: .awaitingReview
        case .error: .failed
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

struct ActivityResultSummary {
    let accounts: [ActivityAccountSummary]
    let notices: [LogEntry]

    init(session: ActivitySession) {
        accounts = ActivityAccountSummary.groups(in: session)
        let displayedIDs = Set(accounts.isEmpty
            ? session.entries.last.map { [$0.id] } ?? []
            : accounts.flatMap { account in
                account.outcomes.isEmpty ? [account.lastEvent.id] : account.outcomes.map(\.id)
            })
        notices = session.entries.filter {
            ($0.level == .warning || $0.level == .error)
                && $0.phase != .completed && !displayedIDs.contains($0.id)
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
