import AppKit
import AutoMAAKit
import SwiftUI

enum ActivityRecordPresentation {
    static func title(_ session: ActivitySession, plans: [AutomationPlan]) -> String {
        if let planID = session.planID {
            return plans.first { $0.id == planID }?.displayName ?? "已移除的方案"
        }
        return session.isStandaloneMaintenance ? "MAA 维护" : "较早的运行记录"
    }

    static func context(_ entry: LogEntry, clients: [ClientConfiguration]) -> String? {
        guard let clientID = entry.clientID, let client = clients.first(where: { $0.id == clientID }) else { return nil }
        if let accountID = entry.accountID, let account = client.accounts.first(where: { $0.id == accountID }) {
            return "\(client.displayName) · \(account.displayName)"
        }
        return client.displayName
    }

    static func showsContext(in visibleEntries: [LogEntry], at index: Int) -> Bool {
        let entry = visibleEntries[index]
        guard entry.clientID != nil || entry.accountID != nil else { return false }
        if index == 0 || entry.level == .warning || entry.level == .error { return true }
        let previous = visibleEntries[index - 1]
        return entry.clientID != previous.clientID || entry.accountID != previous.accountID
    }

    static func listSummary(_ session: ActivitySession, attempts: Int = 1) -> String {
        if let blocker = session.startBlocker {
            return attempts > 1 ? "\(blocker.title) · \(attempts) 次尝试" : blocker.title
        }
        var parts: [String] = []
        if let summary = session.runSummary {
            let resolved = summary.completedSteps + summary.unnecessarySteps + summary.manuallyHandledSteps
            parts.append("\(resolved)/\(summary.totalSteps) 项")
            if summary.failedSteps > 0 { parts.append("\(summary.failedSteps) 项失败") }
            else if summary.unconfirmedSteps > 0 { parts.append("\(summary.unconfirmedSteps) 项待确认") }
            else if summary.pendingWeeklyAnnihilation > 0 { parts.append("剿灭待补打") }
        } else {
            parts.append("\(session.entries.count) 条记录")
        }
        if parts.count == 1 {
            let notices = session.warningCount + session.errorCount
            if notices > 0, session.outcome == .completed { parts.append("\(notices) 条提醒") }
            else if session.endedAt > session.startedAt {
                parts.append(duration(from: session.startedAt, to: session.endedAt))
            }
        }
        return parts.joined(separator: " · ")
    }

    static func summary(_ session: ActivitySession) -> String {
        guard let result = session.runSummary else { return session.outcome.title }
        let handled = result.completedSteps + result.unnecessarySteps + result.manuallyHandledSteps
        let outcomes = ActivityAccountSummary.groups(in: session).flatMap(\.outcomes)
        var parts: [String] = []
        if outcomes.filter(\.isHandledTaskOutcome).count != handled || outcomes.isEmpty {
            parts.append("本轮已处理 \(handled)/\(result.totalSteps) 项")
        }
        if result.failedSteps > outcomes.count(where: { $0.level == .error || $0.fightResult?.status == .failed }) {
            parts.append("\(result.failedSteps) 项失败")
        }
        if result.unconfirmedSteps > outcomes.count(where: { $0.fightResult?.status == .unconfirmed }) {
            parts.append("\(result.unconfirmedSteps) 项待核实")
        }
        if result.unexecutedSteps > 0 { parts.append("\(result.unexecutedSteps) 项未执行") }
        if result.pendingWeeklyAnnihilation > 0 { parts.append("\(result.pendingWeeklyAnnihilation) 个账号剿灭待补打") }
        if [.cancelled, .failed, .unfinished].contains(session.outcome) { parts.insert(session.outcome.title, at: 0) }
        return parts.joined(separator: " · ")
    }

    static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天的记录" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.year().month().day().weekday())
    }

    static func duration(from start: Date, to end: Date) -> String {
        let seconds = max(1, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

struct ActivityRecordDetail: View {
    let session: ActivitySession
    let title: String
    let section: ActivityRecordSection

    var body: some View {
        VStack(spacing: 0) {
            ActivityRecordHeader(session: session, title: title)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            ScrollView {
                ActivitySessionContents(session: session, section: section)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActivityRecordHeader: View {
    let session: ActivitySession
    let title: String
    var showFullHistory: (() -> Void)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                heading
                metadataLabel
                actions
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    heading
                    actions.fixedSize(horizontal: true, vertical: false)
                }
                metadataLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        Text(title).font(.headline).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metadataLabel: some View {
        Text(metadata).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var actions: some View {
        if let showFullHistory {
            ActionTextButton(title: "完整记录", symbol: "clock.arrow.circlepath",
                             help: "在运行记录中查看该次结果和日志", action: showFullHistory)
        }
    }

    private var metadata: String {
        var parts = [session.startedAt.formatted(.dateTime.year().month().day().hour().minute())]
        if session.endedAt.timeIntervalSince(session.startedAt) >= 1 {
            parts.append(ActivityRecordPresentation.duration(from: session.startedAt, to: session.endedAt))
        }
        let summary = ActivityRecordPresentation.summary(session)
        if !summary.isEmpty { parts.append(summary) }
        return parts.joined(separator: " · ")
    }
}

enum ActivityRecordSection: CaseIterable, Identifiable {
    case results, process
    var id: Self { self }
    var title: String { self == .results ? "运行结果" : "完整日志" }
    var symbol: String { self == .results ? "checklist" : "list.bullet.rectangle" }
    var help: String {
        self == .results ? "运行结果 · 按账号查看任务结果、掉落与提醒" : "完整日志 · 按时间查看本次运行的全部日志"
    }
}

struct ActivitySessionContents: View {
    @EnvironmentObject private var model: AppModel
    let session: ActivitySession
    var section = ActivityRecordSection.results
    @State private var expandedTaskAccounts: Set<ActivityAccountSummary.ID> = []
    @State private var onlyAttention = false
    @State private var feedbackVisibilityID = UUID()

    private var attentionEntries: [LogEntry] { session.entries.filter { $0.level == .warning || $0.level == .error } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if section == .process {
                HStack {
                    if let information = session.updateInformation {
                        ActionTextButton(title: "更新内容", symbol: "doc.text", help: "查看本次运行的 MAA 更新内容") {
                            model.updateDetailsRequest = .maa(information)
                        }
                    }
                    Spacer(minLength: 12)
                    Toggle("只看警告与错误", isOn: $onlyAttention)
                        .toggleStyle(.checkbox).font(.caption).fixedSize()
                        .help("只显示警告与错误")
                }
            }
            if section == .results {
                results
            } else if onlyAttention, attentionEntries.isEmpty {
                Text("这次运行没有警告或错误").font(.callout).foregroundStyle(.secondary)
            } else {
                ActivityLogRows(entries: onlyAttention ? attentionEntries : session.entries)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: session.runID, initial: true) { _, runID in
            model.setActivityResultVisible(runID, viewID: feedbackVisibilityID)
        }
        .onDisappear { model.setActivityResultVisible(nil, viewID: feedbackVisibilityID) }
        .onChange(of: session.id) { expandedTaskAccounts.removeAll() }
    }

    private var results: some View {
        let summary = ActivityResultSummary(session: session)
        var events = summary.exceptions
        if summary.accounts.isEmpty, let last = session.entries.last,
           last.runSummary == nil || [.failed, .cancelled].contains(last.phase) {
            events.append(last)
        }
        events.append(contentsOf: summary.notices)

        return VStack(alignment: .leading, spacing: 14) {
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, entry in
                        resultRow(entry, index: index)
                    }
                }
            }
            ForEach(summary.accounts) { account in
                let fight = account.fight
                let lines = account.fightLines
                let tasks = account.completedTasks
                if !lines.isEmpty || !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(accountName(account.lastEvent) ?? "历史账号")
                            .font(.callout.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 5)
                        ForEach(lines.indices, id: \.self) { index in
                            resultLine(lines[index])
                                .activityTableRow(index)
                        }
                        if let fight, !lines.isEmpty, fight.isHandledTaskOutcome {
                            ActivityEntryDetails(entry: fight, showsRecordedDrops: false)
                                .padding(.horizontal, 8)
                            earlierAttempts(summary.earlierFailuresByOutcome[fight.id])
                        }
                        if !tasks.isEmpty {
                            DisclosureGroup(isExpanded: Binding {
                                expandedTaskAccounts.contains(account.id)
                            } set: { expanded in
                                if expanded { expandedTaskAccounts.insert(account.id) }
                                else { expandedTaskAccounts.remove(account.id) }
                            }) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, entry in
                                        Text(entry.accountResultMessage)
                                            .activityTableRow(index)
                                        ActivityEntryDetails(entry: entry).padding(.horizontal, 8)
                                        earlierAttempts(summary.earlierFailuresByOutcome[entry.id])
                                    }
                                }
                                .textSelection(.enabled)
                            } label: {
                                let summary = expandedTaskAccounts.contains(account.id)
                                    ? "\(tasks.count) 项任务" : tasks.compactMap { $0.task?.title }.joined(separator: "、")
                                Text("已完成 · " + summary)
                                    .foregroundStyle(.secondary)
                                    .activityTableRow(lines.count)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }

    private func resultLine(_ line: ActivityResultLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(line.title).font(.callout)
            if let drops = line.drops { Text(drops).font(.callout).foregroundStyle(.secondary) }
            if let note = line.note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }

    @ViewBuilder
    private func earlierAttempts(_ entries: [LogEntry]?) -> some View {
        if let entries {
            DisclosureGroup("较早的尝试 · \(entries.count) 条") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Text(entry.accountResultMessage).textSelection(.enabled)
                            .activityTableRow(index)
                        ActivityEntryDetails(entry: entry).padding(.horizontal, 8)
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func accountName(_ entry: LogEntry) -> String? {
        if let client = model.configuration.clients.first(where: { $0.id == entry.clientID }),
           let account = client.accounts.first(where: { $0.id == entry.accountID }) {
            return "\(client.displayName) · \(account.displayName)"
        }
        if entry.accountID != nil, entry.message.hasPrefix("账号「"), let end = entry.message.range(of: "」：") {
            return String(entry.message.dropFirst(3)[..<end.lowerBound])
        }
        return ActivityRecordPresentation.context(entry, clients: model.configuration.clients)
    }

    private func resultRow(_ entry: LogEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                if let context = accountName(entry) {
                    Text(context).font(.caption).foregroundStyle(.secondary)
                }
                resultLine(entry.exceptionLine)
                    .foregroundStyle(entry.messageColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(entry.level.displayName)
            .activityTableRow(index)
            ActivityEntryDetails(entry: entry, showsRecordedDrops: false)
                .padding(.horizontal, 8)
        }
    }
}

private extension View {
    func activityTableRow(_ index: Int, horizontal: CGFloat = 8, vertical: CGFloat = 5) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: NSColor.alternatingContentBackgroundColors[index % 2]))
    }
}

struct ActivityLiveLog: View {
    let entries: [LogEntry]
    @State private var followsLatest = true
    @State private var onlyAttention = false

    private var displayedEntries: [LogEntry] {
        onlyAttention ? entries.filter { $0.level == .warning || $0.level == .error } : entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("实时记录").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Toggle("只看警告与错误", isOn: $onlyAttention)
                    .help("只显示警告与错误")
                Toggle("跟随最新", isOn: $followsLatest)
                    .help("新记录到达时滚动到最新位置")
            }
            .toggleStyle(.checkbox).font(.caption).fixedSize(horizontal: false, vertical: true)

            if displayedEntries.isEmpty {
                ActivityEmptyState(title: entries.isEmpty ? "等待运行记录" : "暂无警告或错误",
                                   symbol: entries.isEmpty ? "clock" : "checkmark.circle")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        ActivityLogRows(entries: displayedEntries)
                            .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: displayedEntries.last?.id) {
                        guard followsLatest, let id = displayedEntries.last?.id else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                    .onChange(of: followsLatest) { _, follows in
                        guard follows, let id = displayedEntries.last?.id else { return }
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ActivityLogRows: View {
    @EnvironmentObject private var model: AppModel
    let entries: [LogEntry]
    var showsContext = true

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("时间").frame(width: 58, alignment: .leading)
                Text("信息").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .accessibilityAddTraits(.isHeader)
            Divider()
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ActivityEventRow(entry: entry,
                    context: showsContext
                        ? ActivityRecordPresentation.context(entry, clients: model.configuration.clients) : nil,
                    showsContextSubtitle: showsContext && ActivityRecordPresentation.showsContext(in: entries, at: index))
                    .activityTableRow(index, horizontal: 10, vertical: 8)
                    .id(entry.id)
            }
        }
    }
}

struct ActivityEventRow: View {
    let entry: LogEntry
    let context: String?
    let showsContextSubtitle: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let outcome = entry.terminalOutcome {
                        Image(systemName: outcome.symbol)
                            .foregroundStyle(outcome.color)
                            .accessibilityHidden(true)
                    }
                    Text(entry.message).font(.callout).textSelection(.enabled)
                        .foregroundStyle(entry.messageColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityValue(context ?? "")
                        .accessibilityHint(entry.level.displayName)
                }
                if showsContextSubtitle, let context {
                    Text(context).font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ActivityEntryDetails(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .help(context ?? entry.level.displayName)
    }
}

struct ActivityEmptyState: View {
    let title: String
    let symbol: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
