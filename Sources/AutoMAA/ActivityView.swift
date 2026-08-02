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
        case .attention: "警告与错误"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var filter: ActivityFilter = .all
    @State private var expandedSessionIDs: Set<String> = []
    @State private var followsLatest = true
    @State private var showingClearConfirmation = false

    private var sessions: [ActivitySession] {
        var sessions = ActivityHistory.sessions(from: model.activityEntries)
        guard model.isRunning, let runID = model.activityEntries.last?.runID,
              let index = sessions.firstIndex(where: { $0.runID == runID }), index != 0
        else { return sessions }
        let current = sessions.remove(at: index)
        sessions.insert(current, at: 0)
        return sessions
    }

    private var displayedSessions: [DisplayActivitySession] {
        sessions.compactMap { session in
            let entries = session.entries.filter { entry in
                let matchesLevel = filter == .all || entry.level == .warning || entry.level == .error
                let matchesSearch = search.isEmpty
                    || entry.message.localizedCaseInsensitiveContains(search)
                    || entry.details?.localizedCaseInsensitiveContains(search) == true
                    || entry.task?.title.localizedCaseInsensitiveContains(search) == true
                return matchesLevel && matchesSearch
            }
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

            if model.isRunning {
                Toggle(isOn: $followsLatest) {
                    Label("跟随最新", systemImage: "arrow.down.to.line.compact")
                }
                .toggleStyle(.button)
                .help("有新活动时自动滚动到当前运行位置")
            }

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
                .disabled(model.activityEntries.isEmpty || model.isRunning)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    explanation

                    if model.isRunning {
                        currentActivity
                    }

                    if displayedSessions.isEmpty {
                        ContentUnavailableView(
                            model.activityEntries.isEmpty ? "还没有活动记录" : "没有匹配的活动",
                            systemImage: model.activityEntries.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                            description: Text(model.activityEntries.isEmpty
                                ? "运行方案或更新 MAA 后，这里会按每次运行整理进度与结果。"
                                : "试试其他关键词，或切换到“全部”。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
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
                if model.isRunning, let runID = model.activityEntries.last?.runID,
                   let current = sessions.first(where: { $0.runID == runID }) {
                    expandedSessionIDs.insert(current.id)
                }
            }
            .onChange(of: displayedSessions.first?.id) { _, id in
                if let id { expandedSessionIDs.insert(id) }
            }
            .onChange(of: model.activityEntries.count) { _, _ in
                guard followsLatest, model.isRunning,
                      let entry = model.activityEntries.last,
                      let session = sessions.first(where: { $0.entries.contains(where: { $0.id == entry.id }) })
                else { return }
                expandedSessionIDs.insert(session.id)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo(entry.id, anchor: .bottom)
                }
            }
        }
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.maaAccent)
                .padding(.top, 1)
            Text("这里展示经过整理的运行进度和结果。maa-cli 的完整命令输出与定时运行输出保存在诊断日志中，仅在排查问题时需要查看。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentActivity: some View {
        Panel {
            HStack(spacing: 14) {
                Image(systemName: model.phase.statusSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.phase.statusTint)
                    .frame(width: 40, height: 40)
                    .background(model.phase.statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("当前运行")
                            .font(.headline)
                        Text(model.phase.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(model.phase.statusTint)
                    }
                    Text(model.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                }

                Button(role: .destructive) { model.cancelRun() } label: {
                    Label(model.runningPlanID == nil ? "停止更新" : "安全停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
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
        let isCurrent = model.isRunning && session.runID != nil && session.runID == model.activityEntries.last?.runID
        let phase = isCurrent ? model.phase : session.finalPhase
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
                    Text(sessionStatus(phase: phase, level: session.finalLevel))
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
                if session.completedTaskCount > 0 {
                    sessionBadge("\(session.completedTaskCount) 完成", color: .green)
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
            return plan.name
        }
        if session.runID == nil { return "较早的运行记录" }
        return "MAA 维护"
    }

    private func context(for entry: LogEntry) -> String? {
        var components: [String] = []
        if let clientID = entry.clientID,
           let client = model.configuration.clients.first(where: { $0.id == clientID }) {
            components.append(client.name)
            if let accountID = entry.accountID,
               let account = client.accounts.first(where: { $0.id == accountID }) {
                components.append(account.name)
            }
        }
        if let task = entry.task { components.append(task.title) }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private func sessionStatus(phase: RunnerPhase?, level: LogLevel) -> String {
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
                        Label(showsDetails ? "收起诊断详情" : "查看诊断详情", systemImage: "chevron.right")
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
