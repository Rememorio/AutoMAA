import AppKit
import AutoMAAKit
import SwiftUI

enum ActivityRecordPresentation {
    static func title(_ session: ActivitySession, plans: [AutomationPlan]) -> String {
        if let planID = session.planID {
            return plans.first { $0.id == planID }?.displayName ?? "已移除的方案"
        }
        return session.runID == nil ? "较早的运行记录" : "MAA 维护"
    }

    static func context(_ entry: LogEntry, clients: [ClientConfiguration]) -> String? {
        guard let clientID = entry.clientID, let client = clients.first(where: { $0.id == clientID }) else { return nil }
        if let accountID = entry.accountID, let account = client.accounts.first(where: { $0.id == accountID }) {
            return "\(client.displayName) · \(account.displayName)"
        }
        return client.displayName
    }

    static func todaySummary(_ progress: PlanContinuation) -> String {
        if !progress.fightRecoveryItems.isEmpty {
            return (progress.hasStarted ? "\(progress.resolved) 项已处理 · " : "")
                + "\(progress.fightRecoveryItems.count) 项作战待处理"
                + (progress.pending > 0 ? " · \(progress.pending) 项可继续" : "")
        }
        guard progress.hasStarted else { return "今日尚未运行" }
        if progress.pending == 0, progress.unconfirmed == 0 { return progress.completionTitle }
        return "\(progress.resolved) 项已处理"
            + (progress.pending > 0 ? " · \(progress.pending) 项可继续" : "")
            + (progress.unconfirmed > 0 ? " · \(progress.unconfirmed) 项待确认" : "")
    }

    static func summary(_ session: ActivitySession) -> String {
        var parts: [String] = []
        if let summary = session.runSummary {
            parts.append("\(summary.completedSteps + summary.unnecessarySteps + summary.manuallyHandledSteps)/\(summary.totalSteps) 项已处理")
            if summary.unnecessarySteps > 0 { parts.append("\(summary.unnecessarySteps) 项无需执行") }
            if summary.manuallyHandledSteps > 0 { parts.append("\(summary.manuallyHandledSteps) 项人工处理") }
            if summary.unconfirmedSteps > 0 { parts.append("\(summary.unconfirmedSteps) 项未确认") }
            if summary.failedSteps > 0 { parts.append("\(summary.failedSteps) 项失败") }
            if summary.unexecutedSteps > 0 { parts.append("\(summary.unexecutedSteps) 项未执行") }
            if summary.pendingWeeklyAnnihilation > 0 { parts.append("\(summary.pendingWeeklyAnnihilation) 个账号剿灭待补打") }
        } else {
            parts.append("\(session.entries.count) 条记录")
        }
        if session.warningCount > 0 { parts.append("\(session.warningCount) 条提醒") }
        if session.errorCount > 0, (session.runSummary?.failedSteps ?? 0) == 0 { parts.append("\(session.errorCount) 条错误") }
        if session.endedAt > session.startedAt { parts.append(duration(from: session.startedAt, to: session.endedAt)) }
        return parts.joined(separator: " · ")
    }

    static func symbol(_ session: ActivitySession) -> String {
        if session.hasUnfinishedActivity { return "questionmark.circle" }
        if session.finalPhase == .completed, session.finalLevel == .warning { return "exclamationmark.circle.fill" }
        return session.finalPhase?.statusSymbol ?? session.finalLevel.symbol
    }

    static func tint(_ session: ActivitySession) -> Color {
        if session.hasUnfinishedActivity { return .secondary }
        if session.finalPhase == .completed, session.finalLevel == .warning { return .orange }
        return session.finalPhase?.statusTint ?? session.finalLevel.color
    }

    static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天的记录" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.year().month().day().weekday())
    }

    private static func duration(from start: Date, to end: Date) -> String {
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
                .padding(20)
            Divider()
            ScrollView {
                ActivitySessionContents(session: session, section: section)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActivityRecordHeader: View {
    @EnvironmentObject private var model: AppModel
    let session: ActivitySession
    let title: String
    var showFullHistory: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.headline).textSelection(.enabled)
                Spacer(minLength: 8)
                Label(session.historyStatusTitle, systemImage: ActivityRecordPresentation.symbol(session))
                    .font(.caption).foregroundStyle(ActivityRecordPresentation.tint(session))
                    .fixedSize()
                if let information = session.updateInformation {
                    ActionTextButton(title: "更新内容", symbol: "doc.text", help: "查看本次 MAA 更新内容") {
                        model.updateDetailsRequest = .maa(information)
                    }
                }
                if let showFullHistory {
                    ActionTextButton(title: "完整记录", symbol: "clock.arrow.circlepath",
                                     help: "查看本方案的完整运行记录", action: showFullHistory)
                }
            }
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(ActivityRecordPresentation.summary(session))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ActivityRecordSection: CaseIterable, Identifiable {
    case results, process
    var id: Self { self }
    var title: String { self == .results ? "运行结果" : "完整过程" }
    var symbol: String { self == .results ? "checklist" : "doc.text" }
}

struct ActivityRecordSectionPicker: View {
    @Binding var selection: ActivityRecordSection

    var body: some View {
        Picker("记录内容", selection: $selection) {
            ForEach(ActivityRecordSection.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .accessibilityLabel(section.title).help(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented).labelStyle(.iconOnly).labelsHidden().fixedSize()
        .help("切换运行结果与完整过程")
    }
}

struct ActivitySessionContents: View {
    @EnvironmentObject private var model: AppModel
    let session: ActivitySession
    var section = ActivityRecordSection.results
    @State private var onlyAttention = false

    private var attentionEntries: [LogEntry] { session.entries.filter { $0.level == .warning || $0.level == .error } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if section == .process {
                HStack {
                    Text("完整过程").font(.subheadline.weight(.semibold))
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
    }

    private var results: some View {
        let summary = ActivityResultSummary(session: session)
        let accounts = summary.accounts
        return VStack(alignment: .leading, spacing: 18) {
            if accounts.isEmpty, let entry = session.entries.last {
                ActivityLogRows(entries: [entry])
            }
            ForEach(accounts) { account in
                VStack(alignment: .leading, spacing: 9) {
                    Text(ActivityRecordPresentation.context(account.lastEvent, clients: model.configuration.clients) ?? "已移除的账号")
                        .font(.subheadline.weight(.semibold))
                    if account.outcomes.isEmpty {
                        Text("未记录任务结果")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ActivityLogRows(entries: account.outcomes.isEmpty ? [account.lastEvent] : account.outcomes,
                                    showsContext: false)
                }
                if account.id != accounts.last?.id { Divider() }
            }
            if !summary.notices.isEmpty {
                Divider()
                Text("其他提醒与错误 · \(summary.notices.count) 条").font(.subheadline.weight(.semibold))
                ActivityLogRows(entries: summary.notices)
            }
        }
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
                ActivityEmptyState(title: entries.isEmpty ? "正在准备" : "当前没有提醒",
                                   symbol: entries.isEmpty ? "clock" : "checkmark.circle",
                                   detail: entries.isEmpty ? "等待第一条运行记录。" : "警告与错误会显示在这里。")
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
                        ? ActivityRecordPresentation.context(entry, clients: model.configuration.clients) : nil)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: NSColor.alternatingContentBackgroundColors[index % 2]))
                    .id(entry.id)
            }
        }
    }
}

struct ActivityEventRow: View {
    let entry: LogEntry
    let context: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message).font(.callout).textSelection(.enabled)
                    .foregroundStyle(entry.level.messageColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(entry.level.displayName)：\(entry.message)")
                if let context {
                    Text(context).font(.caption).foregroundStyle(.secondary)
                }
                ActivityEntryDetails(entry: entry)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ActivityEmptyState: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
