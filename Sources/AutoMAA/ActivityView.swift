import AppKit
import AutoMAAKit
import SwiftUI

enum ActivityWorkspaceSelection: Hashable {
    case plan(UUID)
    case maintenance
    case session(String)
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingClearConfirmation = false
    @State private var latestMaintenanceSessionID: String?
    @State private var recordSection = ActivityRecordSection.results

    private var sessions: [ActivitySession] {
        ActivityHistory.sessions(from: model.activityEntries)
    }

    private var currentPlan: AutomationPlan? {
        guard model.isWorkflowRunning else { return nil }
        return model.configuration.plans.first { $0.id == model.activePlanID }
    }

    private var showsCurrentMaintenance: Bool {
        model.isWorkflowRunning && currentPlan == nil
    }

    private var historicalSessions: [ActivitySession] {
        guard model.isWorkflowRunning, let runID = model.activeRunID else { return sessions }
        return sessions.filter { $0.runID != runID }
    }

    private var displayedSessions: [ActivitySession] {
        historicalSessions.filter { session in
            model.activityFilter.includes(session)
                && ActivitySearch.matches(session, query: model.activitySearch,
                    title: title(for: session), context: context(for:))
        }
    }

    private var hasActiveFilters: Bool {
        !model.activitySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.activityFilter != .all
    }

    var body: some View {
        WorkspaceColumns {
            recordList
        } detail: {
            selectedDetail
        }
        .navigationTitle("运行记录")
        .toolbar {
            if case .session = model.activitySelection {
                ToolbarItem(placement: .primaryAction) {
                    ActivityRecordSectionPicker(selection: $recordSection)
                }
            }
            ToolbarItem(placement: .primaryAction) { recordActions }
            if case let .plan(planID) = model.activitySelection, !model.isWorkflowRunning {
                ToolbarItem(placement: .primaryAction) {
                    PlanRunControl(planID: planID)
                }
            }
        }
        .alert("清除全部运行记录？", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                guard !model.isWorkflowRunning else { return }
                model.clearActivityHistory()
            }
            .disabled(model.isWorkflowRunning)
        } message: {
            Text("运行摘要会被清除，诊断日志文件不会受影响。")
        }
        .onAppear { restoreSelection() }
        .onChange(of: sessions.map(\.id)) { _, _ in
            rememberCurrentMaintenanceSession()
            restoreSelection()
        }
        .onChange(of: model.configuration.plans.map(\.id)) { _, _ in restoreSelection() }
        .onChange(of: model.activitySearch) { _, _ in selectFilteredResultIfNeeded() }
        .onChange(of: model.activityFilter) { _, _ in selectFilteredResultIfNeeded() }
        .onChange(of: model.activeRunID, initial: true) { _, _ in
            rememberCurrentMaintenanceSession()
        }
        .onChange(of: model.isWorkflowRunning) { _, running in
            if running {
                latestMaintenanceSessionID = nil
                rememberCurrentMaintenanceSession()
            }
            restoreSelection()
        }
    }

    private var recordList: some View {
        VStack(spacing: 0) {
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
                .help("历史运行：\(model.activityFilter.title)；当前运行和今日事项始终保留")
            }
            .padding(12)
            Divider()

            ScrollViewReader { proxy in
                List(selection: $model.activitySelection) {
                    if let currentPlan {
                        Section("当前") {
                            planRow(currentPlan, isCurrent: true)
                                .tag(ActivityWorkspaceSelection.plan(currentPlan.id))
                                .id(ActivityWorkspaceSelection.plan(currentPlan.id))
                        }
                    } else if showsCurrentMaintenance {
                        Section("当前") {
                            currentMaintenanceRow.tag(ActivityWorkspaceSelection.maintenance)
                                .id(ActivityWorkspaceSelection.maintenance)
                        }
                    }

                    let todayPlans = model.configuration.plans.filter { $0.id != currentPlan?.id }
                    if !todayPlans.isEmpty {
                        Section("今日") {
                            ForEach(todayPlans) { plan in
                                planRow(plan, isCurrent: false).tag(ActivityWorkspaceSelection.plan(plan.id))
                                    .id(ActivityWorkspaceSelection.plan(plan.id))
                            }
                        }
                    }

                    ForEach(ActivityDay.groups(displayedSessions)) { day in
                        Section(ActivityRecordPresentation.dayTitle(day.date)) {
                            ForEach(day.sessions) { session in
                                historyRow(session).tag(ActivityWorkspaceSelection.session(session.id))
                                    .id(ActivityWorkspaceSelection.session(session.id))
                            }
                        }
                    }

                    if displayedSessions.isEmpty, !model.configuration.plans.isEmpty || showsCurrentMaintenance {
                        Section("历史") {
                            Text(hasActiveFilters ? "没有匹配的记录" : "还没有运行记录")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .overlay {
                    if model.configuration.plans.isEmpty, !showsCurrentMaintenance, displayedSessions.isEmpty {
                        ActivityEmptyState(
                            title: hasActiveFilters ? "没有匹配的记录" : "还没有运行记录",
                            symbol: hasActiveFilters ? "magnifyingglass" : "clock.arrow.circlepath",
                            detail: hasActiveFilters ? "调整关键词或清除筛选。" : "运行方案或更新 MAA 后可在这里查看。"
                        )
                        .allowsHitTesting(false)
                    }
                }
                .task(id: model.activityNavigationRequest?.id) {
                    await navigateToRequestedRun(using: proxy)
                }
                .task(id: model.activitySelection) {
                    await Task.yield()
                    guard !Task.isCancelled, model.activityNavigationRequest == nil,
                          let selected = model.activitySelection else { return }
                    proxy.scrollTo(selected)
                }
            }

            HStack {
                Text("\(displayedSessions.count) 次历史运行" + (model.activityFilter == .all ? "" : " · \(model.activityFilter.title)"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if hasActiveFilters {
                    Button("清除筛选", action: clearFilters).buttonStyle(.link).font(.caption)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    private var recordActions: some View {
        Menu {
            Button {
                try? model.directories.prepare()
                NSWorkspace.shared.open(model.directories.logs)
            } label: {
                Label("在 Finder 中显示诊断日志", systemImage: "folder")
            }
            Divider()
            Button("清除运行记录…", role: .destructive) { showingClearConfirmation = true }
                .disabled(model.activityEntries.isEmpty || model.isWorkflowRunning)
        } label: {
            Label("记录操作", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.secondary).fixedSize()
        .help("记录操作").accessibilityLabel("记录操作")
    }

    private func planRow(_ plan: AutomationPlan, isCurrent: Bool) -> some View {
        let progress = model.continuation(for: plan.id)
        let needsRecovery = !progress.fightRecoveryItems.isEmpty
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCurrent ? model.activePhase.statusSymbol : needsRecovery ? "exclamationmark.circle" : "calendar")
                .foregroundStyle(isCurrent ? model.activePhase.statusTint : needsRecovery ? .orange : .secondary)
                .frame(width: 18).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.displayName).font(.callout.weight(.medium)).lineLimit(2)
                Text(isCurrent ? model.activePhase.displayName : ActivityRecordPresentation.todaySummary(progress))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .help(plan.displayName)
    }

    private var currentMaintenanceRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(model.activePhase.statusTint).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.activePlanID == nil ? "MAA 维护" : "当前运行").font(.callout.weight(.medium))
                Text(model.activePhase.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private func historyRow(_ session: ActivitySession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title(for: session)).font(.callout.weight(.medium)).lineLimit(2)
                Spacer(minLength: 0)
                Text(session.startedAt, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Label(session.historyStatusTitle, systemImage: ActivityRecordPresentation.symbol(session))
                .font(.caption).foregroundStyle(ActivityRecordPresentation.tint(session))
            Text(ActivityRecordPresentation.summary(session))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 5)
        .help(title(for: session))
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch model.activitySelection {
        case let .plan(planID):
            PlanActivityView(planID: planID, showsPlanTitle: true, showsHistoryLink: false)
                .id(planID)
        case .maintenance:
            ActivityCurrentRunView()
        case let .session(id):
            if let session = sessions.first(where: { $0.id == id }) {
                ActivityRecordDetail(session: session, title: title(for: session), section: recordSection)
                    .id(session.id)
            } else {
                ActivityEmptyState(title: "该记录已被清除", symbol: "clock.arrow.circlepath", detail: "从左侧选择其他记录。")
            }
        case nil:
            ActivityEmptyState(title: hasActiveFilters ? "没有匹配的记录" : "选择运行记录",
                               symbol: "list.bullet.rectangle", detail: "从左侧查看今日状态或历史结果。")
        }
    }

    private func restoreSelection() {
        guard model.activityNavigationRequest == nil else { return }
        if let selection = model.activitySelection {
            switch selection {
            case let .plan(id) where model.configuration.plans.contains(where: { $0.id == id }): return
            case let .session(id) where sessions.contains(where: { $0.id == id }): return
            case .maintenance where showsCurrentMaintenance: return
            case .maintenance:
                if let id = latestMaintenanceSessionID, sessions.contains(where: { $0.id == id }) {
                    model.activitySelection = .session(id)
                    return
                }
            default: break
            }
        }
        if let currentPlan { model.activitySelection = .plan(currentPlan.id) }
        else if showsCurrentMaintenance { model.activitySelection = .maintenance }
        else if hasActiveFilters { model.activitySelection = displayedSessions.first.map { .session($0.id) } }
        else if let id = model.currentPlanID, model.configuration.plans.contains(where: { $0.id == id }) {
            model.activitySelection = .plan(id)
        } else if let session = displayedSessions.first { model.activitySelection = .session(session.id) }
        else { model.activitySelection = model.configuration.plans.first.map { .plan($0.id) } }
    }

    private func rememberCurrentMaintenanceSession() {
        guard showsCurrentMaintenance else { return }
        latestMaintenanceSessionID = model.activeRunID.flatMap { runID in
            sessions.first { $0.runID == runID }?.id
        }
    }

    private func selectFilteredResultIfNeeded() {
        if case let .session(id) = model.activitySelection,
           !displayedSessions.contains(where: { $0.id == id }) {
            model.activitySelection = displayedSessions.first.map { .session($0.id) }
        } else if model.activitySelection == nil {
            model.activitySelection = displayedSessions.first.map { .session($0.id) }
        }
    }

    private func navigateToRequestedRun(using proxy: ScrollViewProxy) async {
        guard let request = model.activityNavigationRequest,
              let session = sessions.first(where: { $0.runID == request.runID }) else { return }
        let target: ActivityWorkspaceSelection
        if model.isWorkflowRunning, model.activeRunID == request.runID {
            target = currentPlan.map { .plan($0.id) } ?? .maintenance
        } else {
            target = .session(session.id)
        }
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
