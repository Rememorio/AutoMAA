import AppKit
import AutoMAAKit
import SwiftUI

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case attention

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .attention: "需留意"
        }
    }
}

private struct DisplayActivitySession: Identifiable {
    let session: ActivitySession
    let entries: [LogEntry]

    var id: String { session.id }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var filter: ActivityFilter = .all
    @State private var expandedSessionIDs: Set<String> = []
    @State private var followsLiveActivity = true
    @State private var showingClearConfirmation = false

    private var sessions: [ActivitySession] {
        ActivityHistory.sessions(from: model.activityEntries)
    }

    private var currentRunID: UUID? {
        model.activeRunID
    }

    private var currentSession: ActivitySession? {
        guard let currentRunID else { return nil }
        return sessions.first { $0.runID == currentRunID }
    }

    private var historicalSessions: [ActivitySession] {
        guard let currentRunID else { return sessions }
        return sessions.filter { $0.runID != currentRunID }
    }

    private var displayedSessions: [DisplayActivitySession] {
        historicalSessions.compactMap { session in
            let entries = filteredEntries(in: session)
            return entries.isEmpty ? nil : DisplayActivitySession(session: session, entries: entries)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            activityContent
        }
        .navigationTitle("活动记录")
        .alert("清除全部活动记录？", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { model.clearActivityHistory() }
        } message: {
            Text("活动摘要会被清除，诊断日志文件不会受影响。")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            TextField("搜索活动记录", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 300)

            Picker("显示范围", selection: $filter) {
                ForEach(ActivityFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Spacer()

            Menu {
                Button {
                    try? model.directories.prepare()
                    NSWorkspace.shared.open(model.directories.logs)
                } label: {
                    Label("在 Finder 中显示诊断日志", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("清除活动记录", systemImage: "trash")
                }
                .disabled(model.activityEntries.isEmpty || model.isWorkflowRunning)
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var activityContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explanation

                if model.isWorkflowRunning {
                    currentActivity
                    if !displayedSessions.isEmpty {
                        Text("历史运行")
                            .font(.headline)
                            .padding(.top, 4)
                    }
                }

                if displayedSessions.isEmpty {
                    if !model.isWorkflowRunning {
                        ContentUnavailableView(
                            model.activityEntries.isEmpty ? "还没有活动记录" : "没有匹配的活动",
                            systemImage: model.activityEntries.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                            description: Text(model.activityEntries.isEmpty
                                ? "运行方案或更新 MAA 后，这里会按每次运行整理进度与结果。"
                                : "试试其他关键词，或切换到“全部”。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                    }
                } else {
                    ForEach(displayedSessions) { item in
                        sessionCard(item)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            if let first = displayedSessions.first {
                expandedSessionIDs.insert(first.id)
            }
        }
        .onChange(of: displayedSessions.first?.id) { _, id in
            if let id { expandedSessionIDs.insert(id) }
        }
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.maaAccent)
                .padding(.top, 1)
            Text("手动与定时运行都会在这里整理为活动记录；理智作战会保留关卡、次数和总掉落，高星公招与保留标签会作为醒目提醒保留。maa-cli 的完整命令输出与 LaunchAgent 原始输出保存在诊断日志中，仅在排查问题时需要查看。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentActivity: some View {
        let entries = currentSession.map(filteredEntries(in:)) ?? []

        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: model.activePhase.statusSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.activePhase.statusTint)
                        .frame(width: 40, height: 40)
                        .background(model.activePhase.statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("当前运行")
                                .font(.headline)
                            Text(model.activePhase.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(model.activePhase.statusTint)
                        }
                        Text(model.activeStatusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        WorkflowProgressView(progress: model.activeProgress)
                    }

                    if model.canCancelRun {
                        Button(role: .destructive) { model.cancelRun() } label: {
                            Label(model.runningPlanID == nil ? "取消更新" : "安全停止", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        Label("定时任务在后台运行", systemImage: "clock.badge.checkmark")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                liveActivityFeed(entries)
            }
        }
    }

    private func liveActivityFeed(_ entries: [LogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实时活动", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle(isOn: $followsLiveActivity) {
                    Label("跟随最新", systemImage: "arrow.down.to.line.compact")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("开启后，新活动只会在当前运行卡内滚动到最新位置")
            }

            if entries.isEmpty {
                Text(search.isEmpty && filter == .all ? "正在等待第一条活动…" : "当前运行没有匹配的活动")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                ActivityEventRow(
                                    entry: entry,
                                    context: context(for: entry),
                                    drawsConnector: index < entries.count - 1
                                )
                            }
                        }
                        .padding(.trailing, 8)
                    }
                    .frame(height: 210)
                    .task(id: entries.last?.id) {
                        guard followsLiveActivity, let id = entries.last?.id else { return }
                        await Task.yield()
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                    .onChange(of: followsLiveActivity) { _, follows in
                        guard follows, let id = entries.last?.id else { return }
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func filteredEntries(in session: ActivitySession) -> [LogEntry] {
        session.entries.filter { entry in
            let matchesLevel = filter == .all || entry.level == .warning || entry.level == .error
            let matchesSearch = search.isEmpty
                || entry.message.localizedCaseInsensitiveContains(search)
                || entry.details?.localizedCaseInsensitiveContains(search) == true
                || entry.task?.title.localizedCaseInsensitiveContains(search) == true
            return matchesLevel && matchesSearch
        }
    }

    private func sessionCard(_ item: DisplayActivitySession) -> some View {
        Panel {
            DisclosureGroup(isExpanded: expansionBinding(for: item.id)) {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.vertical, 12)
                    ForEach(Array(item.entries.enumerated()), id: \.element.id) { index, entry in
                        ActivityEventRow(
                            entry: entry,
                            context: context(for: entry),
                            drawsConnector: index < item.entries.count - 1
                        )
                    }
                }
            } label: {
                sessionHeader(item.session)
                    .contentShape(Rectangle())
            }
            .disclosureGroupStyle(.automatic)
        }
    }

    private func sessionHeader(_ session: ActivitySession) -> some View {
        let isCurrent = model.isWorkflowRunning && session.runID != nil && session.runID == model.activeRunID
        let phase = isCurrent ? model.activePhase : session.finalPhase
        let tint = sessionTint(phase: phase, level: session.finalLevel)

        return HStack(spacing: 13) {
            Image(systemName: sessionSymbol(phase: phase, level: session.finalLevel))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(sessionTitle(session))
                    .font(.headline)
                HStack(spacing: 7) {
                    Text(sessionStatus(session: session, phase: phase, level: session.finalLevel))
                        .foregroundStyle(tint)
                    Text("·")
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                    if session.endedAt > session.startedAt {
                        Text("· \(duration(from: session.startedAt, to: session.endedAt))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                if let summary = session.runSummary {
                    sessionBadge("\(summary.completedSteps)/\(summary.totalSteps) 完成", color: .green)
                } else if session.completedTaskCount > 0 {
                    sessionBadge("\(session.completedTaskCount) 完成", color: .green)
                }
                if session.unexecutedTaskCount > 0 {
                    sessionBadge("\(session.unexecutedTaskCount) 未执行", color: .orange)
                }
                if session.warningCount > 0 {
                    sessionBadge("\(session.warningCount) 警告", color: .orange)
                }
                if session.errorCount > 0 {
                    sessionBadge("\(session.errorCount) 错误", color: .red)
                }
            }
        }
        .padding(.trailing, 8)
    }

    private func sessionBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding {
            expandedSessionIDs.contains(id)
        } set: { expanded in
            if expanded {
                expandedSessionIDs.insert(id)
            } else {
                expandedSessionIDs.remove(id)
            }
        }
    }

    private func sessionTitle(_ session: ActivitySession) -> String {
        if let planID = session.planID,
           let plan = model.configuration.plans.first(where: { $0.id == planID }) {
            return plan.displayName
        }
        if session.runID == nil { return "较早的运行记录" }
        return "MAA 维护"
    }

    private func context(for entry: LogEntry) -> String? {
        var components: [String] = []
        if let clientID = entry.clientID,
           let client = model.configuration.clients.first(where: { $0.id == clientID }) {
            components.append(client.displayName)
            if let accountID = entry.accountID,
               let account = client.accounts.first(where: { $0.id == accountID }) {
                components.append(account.displayName)
            }
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private func sessionStatus(session: ActivitySession, phase: RunnerPhase?, level: LogLevel) -> String {
        if session.runSummary?.isPartial == true { return "部分完成，需处理" }
        if phase == .completed, level == .warning { return "完成，需留意" }
        if let phase { return phase.displayName }
        return switch level {
        case .info: "运行记录"
        case .success: "已完成"
        case .warning: "需要留意"
        case .error: "发生错误"
        }
    }

    private func sessionSymbol(phase: RunnerPhase?, level: LogLevel) -> String {
        if phase == .completed, level == .warning { return "exclamationmark.circle.fill" }
        if let phase { return phase.statusSymbol }
        return level.symbol
    }

    private func sessionTint(phase: RunnerPhase?, level: LogLevel) -> Color {
        if phase == .completed, level == .warning { return .orange }
        if let phase { return phase.statusTint }
        return level.color
    }

    private func duration(from start: Date, to end: Date) -> String {
        let seconds = max(1, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

private struct ActivityEventRow: View {
    let entry: LogEntry
    let context: String?
    let drawsConnector: Bool
    @State private var showsDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: entry.level.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(entry.level.color)
                    .frame(width: 24, height: 24)
                    .background(entry.level.color.opacity(0.11), in: Circle())
                if drawsConnector {
                    Rectangle()
                        .fill(Color.panelStroke)
                        .frame(width: 1)
                        .frame(minHeight: 22)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.message)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                    if let context {
                        Text("·")
                        Text(context)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let details = entry.details, !details.isEmpty {
                    Button {
                        showsDetails.toggle()
                    } label: {
                        Label(showsDetails ? "收起详情" : "查看详情", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if showsDetails {
                        ScrollView(.horizontal) {
                            Text(details)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(10)
                        }
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity)
                    }
                }
            }
            .padding(.bottom, drawsConnector ? 8 : 0)

            Spacer(minLength: 0)
        }
        .id(entry.id)
    }
}
