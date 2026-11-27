import AppKit
import AutoMAAKit
import SwiftUI

enum ActivityWorkspaceSelection: Hashable {
    case plan(UUID)
    case backgroundRun
    case session(String)

    static func restored(_ selected: Self?, current: Self?, history: [String]) -> Self? {
        if case let .session(id) = selected, history.contains(id) { return selected }
        return current ?? history.first.map(Self.session)
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingClearConfirmation = false
    @State private var expandedGroups: Set<String> = []
    @State private var recordSection = ActivityRecordSection.results

    private var sessions: [ActivitySession] {
        ActivityHistory.sessions(from: model.activityEntries).filter { !$0.isStandaloneMaintenance }
    }

    private var currentPlan: AutomationPlan? {
        guard model.isWorkflowRunning else { return nil }
        return model.configuration.plans.first { $0.id == model.activePlanID }
    }

    private var showsBackgroundRun: Bool {
        model.isWorkflowRunning && !model.isMAAMaintenanceRunning && currentPlan == nil
    }

    private var historicalSessions: [ActivitySession] {
        guard model.isWorkflowRunning, let runID = model.activeRunID else { return sessions }
        return sessions.filter { $0.runID != runID }
    }

    private var displayedGroups: [ActivityHistoryGroup] {
        ActivityHistoryGroup.groups(historicalSessions).compactMap { group in
            group.matching { session in
                model.activityFilter.includes(session)
                    && ActivitySearch.matches(session, query: model.activitySearch,
                        title: title(for: session), context: context(for:))
            }
        }
    }

    private var hasActiveFilters: Bool {
        !model.activitySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.activityFilter != .all
    }

    var body: some View {
        let groups = displayedGroups
        let visibleIDs = groups.flatMap { $0.sessions.map(\.id) }
        let current = currentPlan.map { ActivityWorkspaceSelection.plan($0.id) }
            ?? (showsBackgroundRun ? .backgroundRun : nil)
        let restored = ActivityWorkspaceSelection.restored(model.activitySelection, current: current,
                                                           history: visibleIDs)
        return WorkspaceColumns {
            recordList(groups: groups)
        } detail: {
            selectedDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceToolbar(for: .activity, title: "运行记录", actions: recordActions, modes: recordModes)
        .alert("清除方案运行记录？", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                guard !model.isWorkflowRunning else { return }
                model.clearActivityHistory()
            }
            .disabled(model.isWorkflowRunning)
        } message: {
            Text("方案运行摘要会被清除，诊断日志仍可在 Finder 中查看。")
        }
        .onChange(of: [model.activitySelection, restored], initial: true) { _, _ in
            if model.activityNavigationRequest == nil, model.activitySelection != restored {
                model.activitySelection = restored
            }
        }
        .onChange(of: groups.map(\.latest.id)) { _, _ in expandGroup(containing: model.activitySelection) }
    }

    private func recordList(groups: [ActivityHistoryGroup]) -> some View {
        let count = groups.reduce(0) { $0 + 1 + $1.earlier.count }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                ActivitySearchField(text: $model.activitySearch)
                Menu {
                    Picker("历史运行筛选", selection: $model.activityFilter) {
                        ForEach(ActivityFilter.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: {
                    Image(systemName: model.activityFilter == .all
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 15)).frame(width: 28, height: 28)
                        .accessibilityLabel("筛选历史运行")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .tint(model.activityFilter == .all ? .secondary : .maaAccent)
                .accessibilityLabel("筛选历史运行")
                .accessibilityValue(model.activityFilter.title)
                .help("筛选历史运行")
            }
            .padding(12)
            Divider()

            ScrollViewReader { proxy in
                List(selection: $model.activitySelection) {
                    if let currentPlan {
                        Section("当前") {
                            planRow(currentPlan)
                                .tag(ActivityWorkspaceSelection.plan(currentPlan.id))
                                .id(ActivityWorkspaceSelection.plan(currentPlan.id))
                        }
                    } else if showsBackgroundRun {
                        Section("当前") {
                            backgroundRow.tag(ActivityWorkspaceSelection.backgroundRun)
                                .id(ActivityWorkspaceSelection.backgroundRun)
                        }
                    }

                    ForEach(ActivityDay.days(groups)) { day in
                        Section(ActivityRecordPresentation.dayTitle(day.date)) {
                            ForEach(day.groups) { group in historyGroup(group) }
                        }
                    }

                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .task(id: model.activityNavigationRequest?.id) {
                    await navigateToRequestedRun(using: proxy)
                }
                .task(id: model.activitySelection) {
                    expandGroup(containing: model.activitySelection)
                    await Task.yield()
                    guard !Task.isCancelled, model.activityNavigationRequest == nil,
                          let selected = model.activitySelection else { return }
                    proxy.scrollTo(selected)
                }
            }

            if count > 0 || hasActiveFilters {
                HStack {
                    Text("\(count) 次历史运行" + (model.activityFilter == .all ? "" : " · \(model.activityFilter.title)"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if hasActiveFilters {
                        Button("清除筛选", action: clearFilters).buttonStyle(.link).font(.caption)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
        }
    }

    private var recordActions: [WorkspaceToolbarAction] {
        [.init(id: "records.more", title: "记录操作", symbol: "ellipsis", menu: [
            .action("在 Finder 中显示诊断日志") {
                try? model.directories.prepare()
                NSWorkspace.shared.open(model.directories.logs)
            },
            .separator,
            .action("清除运行记录…", isEnabled: !sessions.isEmpty && !model.isWorkflowRunning) {
                showingClearConfirmation = true
            }
        ])]
    }

    private var recordModes: WorkspaceToolbarModes? {
        guard case .session = model.activitySelection else { return nil }
        let sections = ActivityRecordSection.allCases
        return WorkspaceToolbarModes(options: sections.map {
            .init(title: $0.title, symbol: $0.symbol, help: $0.help)
        }, selectedIndex: sections.firstIndex(of: recordSection) ?? 0) { index in
            recordSection = sections[index]
        }
    }

    private func planRow(_ plan: AutomationPlan) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "play.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18).padding(.top, 2).accessibilityHidden(true)
            Text(plan.displayName).font(.callout.weight(.medium)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .help(plan.displayName)
    }

    private var backgroundRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary).frame(width: 18).padding(.top, 2)
            Text("后台运行").font(.callout.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func historyGroup(_ group: ActivityHistoryGroup) -> some View {
        let expanded = expandedGroups.contains(group.id)
        HStack(spacing: 5) {
            if !group.earlier.isEmpty {
                Button {
                    if expanded {
                        if case let .session(id) = model.activitySelection, group.earlier.contains(where: { $0.id == id }) {
                            model.activitySelection = .session(group.latest.id)
                        }
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 18, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded ? "收起启动尝试" : "展开启动尝试")
                .accessibilityValue("\(group.sessions.count) 次，\(expanded ? "已展开" : "已收起")")
                .help(expanded ? "收起启动尝试" : "展开每次启动尝试")
            }
            historyRow(group.latest, attempts: group.earlier.count + 1)
        }
        .tag(ActivityWorkspaceSelection.session(group.latest.id))
        .id(ActivityWorkspaceSelection.session(group.latest.id))
        if expanded {
            ForEach(group.earlier) { session in
                historyRow(session, showsSeconds: true).padding(.leading, 23)
                    .tag(ActivityWorkspaceSelection.session(session.id))
                    .id(ActivityWorkspaceSelection.session(session.id))
            }
        }
    }

    private func historyRow(_ session: ActivitySession, attempts: Int = 1, showsSeconds: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title(for: session)).font(.callout.weight(.medium)).lineLimit(2)
                Spacer(minLength: 0)
                Text(session.startedAt, format: showsSeconds || attempts > 1 ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                ActivityOutcomeLabel(outcome: session.outcome, isSelected: model.activitySelection == .session(session.id))
                Text("·").accessibilityHidden(true)
                Text(ActivityRecordPresentation.listSummary(session, attempts: attempts))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 5)
        .help(title(for: session))
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch model.activitySelection {
        case let .plan(planID):
            if let currentPlan, currentPlan.id == planID {
                ActivityCurrentRunView(title: currentPlan.displayName)
            }
        case .backgroundRun:
            if showsBackgroundRun { ActivityCurrentRunView() }
        case let .session(id):
            if let session = sessions.first(where: { $0.id == id }) {
                ActivityRecordDetail(session: session, title: title(for: session), section: recordSection)
                    .id(session.id)
            } else {
                ActivityEmptyState(title: "该记录已被清除", symbol: "clock.arrow.circlepath", detail: "从左侧选择其他记录。")
            }
        case nil:
            ActivityEmptyState(title: hasActiveFilters ? "没有匹配的记录" : "还没有运行记录",
                               symbol: hasActiveFilters ? "magnifyingglass" : "clock.arrow.circlepath",
                               detail: hasActiveFilters ? "调整关键词或清除筛选。" : nil)
        }
    }

    private func expandGroup(containing selection: ActivityWorkspaceSelection?) {
        guard case let .session(id) = selection,
              let group = displayedGroups.first(where: { $0.earlier.contains(where: { $0.id == id }) }) else { return }
        expandedGroups.insert(group.id)
    }

    private func navigateToRequestedRun(using proxy: ScrollViewProxy) async {
        guard let request = model.activityNavigationRequest,
              let session = sessions.first(where: { $0.runID == request.runID }) else { return }
        let target: ActivityWorkspaceSelection
        if model.isWorkflowRunning, model.activeRunID == request.runID {
            target = currentPlan.map { .plan($0.id) } ?? .backgroundRun
        } else {
            target = .session(session.id)
        }
        expandGroup(containing: target)
        model.activitySelection = target
        await Task.yield()
        guard !Task.isCancelled, model.activityNavigationRequest == request else { return }
        proxy.scrollTo(target, anchor: .center)
        model.finishActivityNavigation(request)
    }

    private func clearFilters() {
        model.activitySearch = ""
        model.activityFilter = .all
    }

    private func title(for session: ActivitySession) -> String {
        ActivityRecordPresentation.title(session, plans: model.configuration.plans)
    }

    private func context(for entry: LogEntry) -> String? {
        ActivityRecordPresentation.context(entry, clients: model.configuration.clients)
    }
}
