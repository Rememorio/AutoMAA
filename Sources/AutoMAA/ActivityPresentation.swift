import AutoMAAKit
import Foundation

struct ActivityNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let runID: UUID
}

extension LogEntry {
    var isHandledTaskOutcome: Bool {
        guard task != nil, !isCarriedForwardFight, level != .warning, level != .error else { return false }
        return fightResult?.isResolved ?? (level == .success)
    }

    var accountResultMessage: String {
        guard accountID != nil, message.hasPrefix("账号「"), let end = message.range(of: "」：") else { return message }
        return String(message[end.upperBound...])
    }

    var terminalOutcome: ActivityOutcome? {
        if startBlocker != nil { return .blocked }
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
    case failed, blocked, cancelled, unfinished, recorded

    var title: String {
        switch self {
        case .completed: "已完成"
        case .handled: "已处理"
        case .partial: "部分完成"
        case .partiallyHandled: "部分处理"
        case .incomplete: "未完成"
        case .awaitingReview: "待核实"
        case .weeklyPending: "本轮结束"
        case .blocked: "未启动"
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
        case .blocked: "pause.circle"
        case .failed: "xmark.circle"
        case .cancelled: "stop.circle"
        case .unfinished: "questionmark.circle"
        case .recorded: "clock"
        }
    }
}

extension ActivitySession {
    var outcome: ActivityOutcome {
        if startBlocker != nil { return .blocked }
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

/// One visible row may represent adjacent attempts. Each attempt keeps its original identity and entries.
struct ActivityHistoryGroup: Identifiable {
    let latest: ActivitySession
    var earlier: [ActivitySession] = []
    var id: String { earlier.last?.id ?? latest.id }
    var sessions: [ActivitySession] { [latest] + earlier }

    static func groups(_ ordered: [ActivitySession], calendar: Calendar = .current) -> [Self] {
        var result: [Self] = []
        for session in ordered where !session.isStandaloneMaintenance {
            if let latest = result.last?.latest, let blocker = session.startBlocker,
               session.roundID != nil, session.roundID == latest.roundID,
               session.planID == latest.planID, latest.startBlocker == blocker,
               latest.entries.last?.message == session.entries.last?.message,
               calendar.isDate(latest.startedAt, inSameDayAs: session.startedAt),
               latest.startedAt.timeIntervalSince(session.startedAt) <= 300 {
                result[result.count - 1].earlier.append(session)
            } else {
                result.append(Self(latest: session))
            }
        }
        return result
    }

    func matching(_ includes: (ActivitySession) -> Bool) -> Self? {
        let matches = sessions.filter(includes)
        guard let first = matches.first else { return nil }
        return Self(latest: first, earlier: Array(matches.dropFirst()))
    }
}

struct ActivityDay: Identifiable {
    let date: Date
    let groups: [ActivityHistoryGroup]
    var id: Date { date }

    static func days(_ groups: [ActivityHistoryGroup], calendar: Calendar = .current) -> [Self] {
        Dictionary(grouping: groups) { calendar.startOfDay(for: $0.latest.startedAt) }
            .map { Self(date: $0.key, groups: $0.value) }
            .sorted { $0.date > $1.date }
    }
}

struct ActivityAccountID: Hashable {
    let client: UUID?
    let account: UUID
}

struct ActivityAccountSummary: Identifiable {
    let id: ActivityAccountID
    let lastEvent: LogEntry
    let outcomes: [LogEntry]
    let unreportedFightPhases: [FightResult]

    var fight: LogEntry? { outcomes.first { $0.task == .fight } }
    var fightLines: [ActivityResultLine] {
        unreportedFightPhases.isEmpty ? (fight?.handledFightLines ?? []) : unreportedFightPhases.map(ActivityResultLine.init)
    }
    var completedTasks: [LogEntry] { outcomes.filter { $0.task != .fight && $0.isHandledTaskOutcome } }

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
            var outcomes: [TaskKind: Int] = [:]
            for (index, entry) in values.enumerated() {
                guard let task = entry.task,
                      entry.level == .success || entry.level == .error || entry.fightResult != nil else { continue }
                outcomes[task] = index
            }
            let fight = outcomes[.fight].map { values[$0] }
            var unreported: [FightResult] = []
            // A stop or error between phases may leave no final fight report for this account.
            if fight?.executedFightPhases == nil, fight?.fightResult == nil {
                var seen: Set<UUID> = []
                for entry in values where entry.isSettledPhaseEvent && seen.insert(entry.id).inserted {
                    unreported += entry.executedFightPhases ?? []
                }
            }
            return Self(id: id, lastEvent: last, outcomes: outcomes.values.sorted().map { values[$0] },
                        unreportedFightPhases: unreported)
        }
    }
}

/// A visible result with the drops recorded for that outcome.
struct ActivityResultLine: Equatable {
    let title: String
    let drops: String?
    let note: String?

    init(title: String, drops: String? = nil, note: String? = nil) {
        self.title = title
        self.drops = drops
        self.note = note
    }

    init(_ result: FightResult) {
        if result.status == .unnecessary {
            self.init(title: result.reason == .navigationUnavailable ? "本次跳过作战" : "无需作战", note: result.reason?.recordedTitle)
            return
        }
        guard result.status == .completed, result.times > 0 else {
            let drops = result.totalDrops.flatMap { $0.isEmpty ? nil : "已识别掉落：" + $0 }
            self.init(title: "作战" + result.recordedDescription, drops: drops)
            return
        }
        let stage = result.stage.flatMap { $0.isEmpty ? nil : $0 }
        let target = if stage?.lowercased() == "annihilation" {
            "剿灭"
        } else if result.kind == .annihilation {
            stage.map { "剿灭 · " + $0 } ?? "剿灭"
        } else {
            stage ?? "作战"
        }
        let count = (result.unrecognizedSettlements ?? 0) > 0 ? "至少 \(result.times) 次" : "\(result.times) 次"
        var notes: [String] = []
        if let missing = result.missingDropRuns { notes.append("\(missing) 次掉落未识别") }
        if let reason = result.reason { notes.append(reason.recordedTitle) }
        if let original = result.fallbackFrom { notes.append("兜底作战，原目标为" + (original.isEmpty ? "游戏当前/上次" : original)) }
        self.init(title: "\(target) × \(count)", drops: result.dropsSummary,
                  note: notes.isEmpty ? nil : notes.joined(separator: " · "))
    }
}

extension LogEntry {
    var isSettledPhaseEvent: Bool {
        guard phase == .runningTask, task == .fight, level == .info, fightResult == nil, !isCarriedForwardFight,
              let phases = executedFightPhases, !phases.isEmpty else { return false }
        return phases.allSatisfy { $0.status == .completed && $0.times > 0 }
    }

    var handledFightLines: [ActivityResultLine] {
        guard task == .fight, !isCarriedForwardFight else { return [] }
        let manual = ActivityResultLine(title: "常规作战已人工处理")
        if let phases = executedFightPhases {
            var lines = phases.filter { result in
                (result.status == .completed && result.times > 0) || (result.status == .unnecessary && isHandledTaskOutcome)
            }.map(ActivityResultLine.init)
            if fightResult?.status == .manuallyHandled { lines.append(manual) }
            if lines.isEmpty, isHandledTaskOutcome {
                lines.append(.init(title: "本轮作战已处理，本次未执行"))
            }
            return lines
        }
        guard isHandledTaskOutcome else { return [] }
        guard let result = fightResult else { return [.init(title: accountResultMessage)] }
        if result.status == .manuallyHandled { return [manual] }
        // Earlier combined outcomes retain per-stage counts in the original recorded message.
        if accountResultMessage.hasPrefix("理智作战：") {
            return [.init(title: accountResultMessage, drops: recordedDropsSummary)]
        }
        return [ActivityResultLine(result)]
    }

    var exceptionLine: ActivityResultLine {
        if isCarriedForwardFight { return .init(title: "上次作战待核实，本次跳过") }
        if let last = executedFightPhases?.last(where: { !$0.isResolved }) { return ActivityResultLine(last) }
        return .init(title: accountResultMessage, drops: recordedDropsSummary)
    }
}

struct ActivityResultSummary {
    let accounts: [ActivityAccountSummary]
    let notices: [LogEntry]
    let earlierFailuresByOutcome: [UUID: [LogEntry]]

    var exceptions: [LogEntry] {
        accounts.flatMap { account in
            if account.outcomes.isEmpty { return account.lastEvent.isSettledPhaseEvent ? [] : [account.lastEvent] }
            return account.outcomes.filter { !$0.isHandledTaskOutcome }
        }
    }

    init(session: ActivitySession) {
        accounts = ActivityAccountSummary.groups(in: session)
        var shown = accounts.isEmpty ? Array(session.entries.suffix(1)) : accounts.flatMap { account in
            account.outcomes.isEmpty ? [account.lastEvent] : account.outcomes
        }
        let successfulTasks = accounts.flatMap(\.outcomes).filter {
            $0.level == .success && ($0.fightResult == nil || $0.fightResult?.status == .completed)
        }
        var earlierFailures: [UUID: [LogEntry]] = [:]
        notices = session.entries.filter { entry in
            guard entry.level == .warning || entry.level == .error, entry.phase != .completed else { return false }
            if shown.contains(where: { previous in
                previous.clientID == entry.clientID && previous.accountID == entry.accountID
                    && previous.task == entry.task && previous.phase == entry.phase && previous.level == entry.level
                    && previous.message == entry.message && previous.details == entry.details
                    && previous.fightResult == entry.fightResult
            }) { return false }
            shown.append(entry)
            if let runID = session.runID, entry.runID == runID, entry.phase == .runningTask,
               entry.clientID != nil, entry.accountID != nil, entry.task != nil,
               entry.level == .error || entry.fightResult?.status == .failed,
               let outcome = successfulTasks.first(where: {
                   $0.runID == runID && $0.phase == .runningTask && $0.timestamp > entry.timestamp
                       && $0.clientID == entry.clientID && $0.accountID == entry.accountID && $0.task == entry.task
               }) {
                earlierFailures[outcome.id, default: []].append(entry)
                return false
            }
            return true
        }
        earlierFailuresByOutcome = earlierFailures
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
