import AppKit
import AutoMAAKit
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    private var search: String { model.activitySearch }
    private var filter: ActivityFilter { model.activityFilter }
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

    private var displayedSessions: [ActivitySession] {
        historicalSessions.filter { session in
            filter.includes(session) && ActivitySearch.matches(session, query: search,
                title: sessionTitle(session), context: context(for:))
        }
    }

    private var recoveryPlans: [AutomationPlan] {
        model.configuration.plans.filter { !model.continuation(for: $0.id).fightRecoveryItems.isEmpty }
    }

    var body: some View {
        activityContent
        .navigationTitle("活动记录")
        .alert("清除全部活动记录？", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { model.clearActivityHistory() }
        } message: {
            Text("活动摘要会被清除，诊断日志文件不会受影响。")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    recordScope
                    Spacer(minLength: 0)
                    searchActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    recordScope
                    searchActions
                }
            }

            HStack(spacing: 12) {
                Text("\(displayedSessions.count) 次运行" + (hasActiveFilters ? " · 按整次运行筛选，保留完整过程" : " · 展开查看账号结果"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("清除筛选", action: clearFilters)
                    .buttonStyle(.link)
                    .opacity(hasActiveFilters ? 1 : 0)
                    .disabled(!hasActiveFilters)
                    .accessibilityHidden(!hasActiveFilters)
            }
            .font(.caption)
        }
        .padding(.horizontal, PageLayout.inset)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, PageLayout.inset)
        }
    }

    private var recordScope: some View {
        HStack(spacing: 16) {
            Text("历史记录")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("历史运行筛选", selection: $model.activityFilter) {
                ForEach(ActivityFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(.maaAction)
            .labelsHidden()
            .frame(width: 200)
            .help("提醒包含警告、错误与未完成事项；失败筛选有失败结果的运行。保留整次过程，不影响当前状态。")
        }
        .fixedSize()
    }

    private var searchActions: some View {
        HStack(spacing: 12) {
            ActivitySearchField(text: $model.activitySearch)
                .frame(minWidth: 200, maxWidth: 280)
            Spacer(minLength: 0)
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
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .tint(.secondary)
            .fixedSize()
            .help("记录操作")
            .accessibilityLabel("记录操作")
        }
        .frame(maxWidth: 340)
    }

    private var activityContent: some View {
        GeometryReader { viewport in
            let gutter = NSScroller.preferredScrollerStyle == .legacy
                ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PageLayout.sectionSpacing, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !recoveryPlans.isEmpty { currentRecovery }
                        if model.isWorkflowRunning { currentActivity }
                        if let planID = model.currentPlanID, !model.isWorkflowRunning {
                            currentPlanProgress(planID)
                        }
                    }
                    .padding(.horizontal, PageLayout.inset)
                    .padding(.top, PageLayout.inset)

                    Section {
                        Group {
                            if displayedSessions.isEmpty {
                                ContentUnavailableView(
                                    historicalSessions.isEmpty ? "还没有历史记录" : "没有匹配的历史记录",
                                    systemImage: historicalSessions.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                                    description: Text(historicalSessions.isEmpty
                                        ? "运行方案或更新 MAA 后，这里会按每次运行整理进度与结果。"
                                        : "试试其他关键词，或清除筛选查看全部记录。")
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                ForEach(ActivityDay.groups(displayedSessions)) { day in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(dayTitle(day.date))
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                            .accessibilityAddTraits(.isHeader)
                                        Panel {
                                            VStack(spacing: 0) {
                                                ForEach(Array(day.sessions.enumerated()), id: \.element.id) { index, session in
                                                    if index > 0 { Divider().padding(.vertical, 12) }
                                                    sessionRow(session)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, PageLayout.inset)
                    } header: {
                        controls
                    }
                }
                .padding(.bottom, PageLayout.inset)
                .frame(maxWidth: PageLayout.readingWidth)
                .frame(width: max(0, viewport.size.width - gutter))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .clipped()
        }
    }

    private var hasActiveFilters: Bool {
        !search.isEmpty || filter != .all
    }

    private func clearFilters() {
        model.activitySearch = ""
        model.activityFilter = .all
    }

    private var currentRecovery: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("需要处理", systemImage: "exclamationmark.circle")
                        .font(.headline).foregroundStyle(.orange)
                    Spacer()
                    Text("\(recoveryPlans.count) 个方案").font(.caption).foregroundStyle(.secondary)
                }
                Text("请先核实游戏结果，再决定是否重试。历史提醒不会加入这里。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(recoveryPlans) { plan in
                    let progress = model.continuation(for: plan.id)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(plan.displayName).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(progress.fightRecoveryItems.count) 项待核实").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(progress.fightRecoveryItems) { item in
                            Divider()
                            FightRecoveryRow(item: item, context: model.pendingWorkContext(item.step),
                                pendingTitle: progress.pendingItems.first { $0.id == item.id }?.title)
                        }
                    }
                }
            }
        }
    }

    private func currentPlanProgress(_ planID: UUID) -> some View {
        let progress = model.continuation(for: planID)
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progress.hasStarted && progress.pending > 0 ? "当前待办" : "今日状态").font(.headline)
                    Spacer()
                    Picker("方案", selection: Binding(get: { planID }, set: { model.selectCurrentPlan($0) })) {
                        ForEach(model.configuration.plans) { plan in Text(plan.displayName).tag(plan.id) }
                    }
                    .fixedSize()
                    .disabled(model.isWorkflowRunning)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        progressDescription(progress, planID: planID)
                        Spacer()
                        if progress.hasStarted, progress.pending > 0 { PlanRunControl(planID: planID) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        progressDescription(progress, planID: planID)
                        if progress.hasStarted, progress.pending > 0 { PlanRunControl(planID: planID) }
                    }
                }
                let recoveryIDs = Set(progress.fightRecoveryItems.map(\.id))
                let pendingItems = progress.pendingItems.filter { !recoveryIDs.contains($0.id) }
                if progress.hasStarted, !pendingItems.isEmpty {
                    Divider()
                    PendingWorkList(items: pendingItems)
                }
            }
        }
        .id(planID)
    }

    private func progressDescription(_ progress: PlanContinuation, planID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if progress.hasStarted {
                Text(progress.pending == 0 && progress.unconfirmed == 0
                     ? "今日任务已完成"
                     : "\(progress.resolved) 项已处理"
                        + (progress.pending > 0 ? " · \(progress.pending) 项可继续" : "")
                        + (progress.unconfirmed > 0 ? " · \(progress.unconfirmed) 项待确认" : ""))
                    .font(.callout).monospacedDigit()
                if progress.unconfirmed > 0 {
                    Text("继续其他任务会保留待确认作战。请先核实结果，再决定是否重新尝试。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("今日尚未运行").font(.callout)
                if let plan = model.configuration.plans.first(where: { $0.id == planID }),
                   model.isPlanScheduleCurrent(plan), let next = PlanScheduleFormatter.nextRunLabel(plan.schedule) {
                    Text("下次 \(next)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("开始运行后，这里会显示进度与剩余任务。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var currentActivity: some View {
        let entries = currentSession?.entries ?? []

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
                            Text(model.activePlanID.flatMap { id in model.configuration.plans.first { $0.id == id }?.displayName } ?? "当前运行")
                                .font(.headline)
                            Text(model.activePhase.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(model.activePhase.statusTint)
                            if let information = currentSession?.updateInformation {
                                Button("更新内容") { model.updateDetailsRequest = .maa(information) }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                        Text(model.activeStatusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if model.activePlanID != nil {
                            WorkflowProgressView(progress: model.activeProgress)
                        } else if let activity = model.maaUpdateActivity {
                            Text("已用时 \(activity.startedAt, style: .timer) · 上限 \(UpdatePolicy.durationDescription(activity.component.timeout))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)
                    if model.canCancelRun || model.isCancellingRun {
                        StopOperationButton()
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
                .tint(.maaAction)
                .controlSize(.small)
                .help("开启后，新活动只会在当前运行卡内滚动到最新位置")
            }

            if entries.isEmpty {
                Text("正在等待第一条活动…")
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

    private func sessionRow(_ session: ActivitySession) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: session.id)) {
            VStack(alignment: .leading, spacing: 12) {
                Divider().padding(.vertical, 8)
                if let information = session.updateInformation {
                    Button("更新内容") { model.updateDetailsRequest = .maa(information) }
                        .buttonStyle(.link).font(.callout)
                }
                ActivitySessionDetail(session: session, context: context(for:))
            }
            .padding(.leading, 6)
            .padding(.bottom, 6)
        } label: {
            sessionHeader(session).contentShape(Rectangle())
        }
    }

    private func sessionHeader(_ session: ActivitySession) -> some View {
        let phase = session.finalPhase
        let tint = session.hasUnfinishedActivity ? Color.secondary : sessionTint(phase: phase, level: session.finalLevel)
        return HStack(alignment: .top, spacing: 12) {
            Text(session.startedAt, format: .dateTime.hour().minute())
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(sessionTitle(session)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Label(session.historyStatusTitle,
                          systemImage: session.hasUnfinishedActivity ? "questionmark.circle" : sessionSymbol(phase: phase, level: session.finalLevel))
                        .font(.caption).foregroundStyle(tint)
                }
                if session.finalPhase == .failed, let failure = session.entries.last(where: { $0.level == .error }) {
                    Text(failure.message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(sessionSummary(session))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.trailing, 8)
    }

    private func sessionSummary(_ session: ActivitySession) -> String {
        var parts: [String] = []
        if let summary = session.runSummary {
            parts.append("\(summary.completedSteps + summary.unnecessarySteps)/\(summary.totalSteps) 项已处理")
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

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.year().month().day().weekday())
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
        if session.planID != nil { return "已移除的方案" }
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

struct ActivityEventRow: View {
    let entry: LogEntry
    let context: String?
    let drawsConnector: Bool

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

                ActivityEntryDetails(entry: entry)
            }
            .padding(.bottom, drawsConnector ? 8 : 0)

            Spacer(minLength: 0)
        }
        .id(entry.id)
    }
}
