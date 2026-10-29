import AutoMAAKit
import SwiftUI

struct ActivityPlanSnapshot {
    let isCurrent: Bool
    let currentSession: ActivitySession?
    let latestSession: ActivitySession?

    var displayedSession: ActivitySession? { isCurrent ? currentSession : latestSession }

    init(planID: UUID, sessions: [ActivitySession], activePlanID: UUID?, activeRunID: UUID?, isWorkflowRunning: Bool) {
        let current = isWorkflowRunning && activePlanID == planID
        isCurrent = current
        currentSession = current ? sessions.first { session in
            activeRunID != nil && session.runID == activeRunID && session.planID == planID
        } : nil
        latestSession = sessions.filter { session in
            session.planID == planID && !(current && activeRunID != nil && session.runID == activeRunID)
        }.max { $0.startedAt < $1.startedAt }
    }
}

struct PlanActivityView: View {
    @EnvironmentObject private var model: AppModel
    let planID: UUID
    var showsPlanTitle = false
    var showsHistoryLink = true

    private var plan: AutomationPlan? { model.configuration.plans.first { $0.id == planID } }
    private var progress: PlanContinuation { model.continuation(for: planID) }
    private var snapshot: ActivityPlanSnapshot {
        ActivityPlanSnapshot(planID: planID,
            sessions: ActivityHistory.sessions(from: model.activityEntries),
            activePlanID: model.activePlanID, activeRunID: model.activeRunID,
            isWorkflowRunning: model.isWorkflowRunning)
    }

    private var pendingItems: [PendingWorkflowItem] {
        let recoveryIDs = Set(progress.fightRecoveryItems.map(\.id))
        return progress.pendingItems.filter { !recoveryIDs.contains($0.id) }
    }

    var body: some View {
        if let plan {
            VStack(spacing: 0) {
                header(plan)
                    .padding(20)
                Divider()
                if snapshot.isCurrent { liveContent }
                else if snapshot.latestSession == nil, !progress.hasStarted, progress.fightRecoveryItems.isEmpty {
                    ActivityEmptyState(title: "今日尚未运行", symbol: "clock.arrow.circlepath",
                                       detail: emptyHistoryDescription(plan))
                } else { idleContent(plan) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ActivityEmptyState(title: "方案已被移除", symbol: "tray", detail: "历史结果仍可在运行记录中查看。")
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActivityOperationSummary()
                .padding(.horizontal, 20).padding(.vertical, 14)
            if !progress.fightRecoveryItems.isEmpty || (progress.hasStarted && !pendingItems.isEmpty) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !progress.fightRecoveryItems.isEmpty { recovery }
                        if progress.hasStarted, !pendingItems.isEmpty { pendingWork }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                Divider()
            }
            ActivityLiveLog(entries: snapshot.currentSession?.entries ?? [])
                .id(model.activeRunID)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func idleContent(_ plan: AutomationPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !progress.fightRecoveryItems.isEmpty { recovery }
                if let session = snapshot.latestSession {
                    VStack(alignment: .leading, spacing: 16) {
                        ActivityRecordHeader(session: session, title: "最近运行",
                                             showFullHistory: showsHistoryLink ? nil : { showFullHistory() })
                        ActivitySessionContents(session: session).id(session.id)
                    }
                } else {
                    ActivityEmptyState(title: "还没有运行记录", symbol: "clock.arrow.circlepath",
                                       detail: "运行后会显示这份方案的结果与完整过程。")
                        .frame(minHeight: 160)
                }
                if progress.hasStarted, !pendingItems.isEmpty {
                    Divider()
                    pendingWork
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pendingWork: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日待办").font(.subheadline.weight(.semibold))
            PendingWorkList(items: pendingItems)
        }
    }

    private func header(_ plan: AutomationPlan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(showsPlanTitle ? plan.displayName : snapshot.isCurrent ? "本次运行" : "今日状态")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if !snapshot.isCurrent, snapshot.latestSession != nil || progress.hasStarted || !progress.fightRecoveryItems.isEmpty {
                    todaySummary(plan)
                }
            }
            Spacer(minLength: 8)
            if showsHistoryLink { historyButton }
        }
    }

    private var historyButton: some View {
        ActionTextButton(title: "完整记录", symbol: "clock.arrow.circlepath", help: "查看本方案的完整运行记录",
                         action: showFullHistory)
    }

    private func todaySummary(_ plan: AutomationPlan) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ActivityRecordPresentation.todaySummary(progress))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if progress.manuallyHandled > 0 {
                Text("\(progress.manuallyHandled) 项作战已人工处理，今天不再重试")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if progress.unconfirmed > 0 {
                Text("继续其他任务会保留待确认作战。请先核实结果，再决定是否重新尝试。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !progress.hasStarted, model.isPlanScheduleCurrent(plan),
               let next = PlanScheduleFormatter.nextRunLabel(plan.schedule) {
                Text("下次 \(next)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func emptyHistoryDescription(_ plan: AutomationPlan) -> String {
        let detail = "运行后会显示这份方案的结果与完整过程。"
        if model.isPlanScheduleCurrent(plan), let next = PlanScheduleFormatter.nextRunLabel(plan.schedule) {
            return "下次 \(next)\n\(detail)"
        }
        return detail
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("需要处理", systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            ForEach(progress.fightRecoveryItems) { item in
                FightRecoveryRow(item: item, context: model.pendingWorkContext(item.step),
                    pendingTitle: progress.pendingItems.first { $0.id == item.id }?.title)
                if item.id != progress.fightRecoveryItems.last?.id { Divider() }
            }
        }
    }

    private func showFullHistory() {
        if let runID = snapshot.displayedSession?.runID {
            model.showActivity(runID: runID)
        } else if let session = snapshot.displayedSession {
            model.activitySearch = ""
            model.activityFilter = .all
            model.activitySelection = .session(session.id)
            model.selection = .activity
        } else {
            model.activitySelection = .plan(planID)
            model.selection = .activity
        }
    }
}

struct ActivityCurrentRunView: View {
    @EnvironmentObject private var model: AppModel

    private var session: ActivitySession? {
        guard model.isWorkflowRunning, let runID = model.activeRunID else { return nil }
        return ActivityHistory.sessions(from: model.activityEntries).first { $0.runID == runID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.activePlanID == nil ? "MAA 维护" : "当前运行").font(.headline)
                Spacer()
                if let information = session?.updateInformation {
                    ActionTextButton(title: "更新内容", symbol: "doc.text", help: "查看本次 MAA 更新内容") {
                        model.updateDetailsRequest = .maa(information)
                    }
                }
            }
            .padding(20)
            Divider()
            ActivityOperationSummary()
                .padding(.horizontal, 20).padding(.vertical, 14)
            ActivityLiveLog(entries: session?.entries ?? [])
                .id(model.activeRunID)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActivityOperationSummary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.activePhase.displayName, systemImage: model.activePhase.statusSymbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(model.activePhase.statusTint)
            Text(model.activeStatusMessage)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(3).textSelection(.enabled).help(model.activeStatusMessage)
            if model.activePlanID != nil {
                WorkflowProgressView(progress: model.activeProgress).frame(maxWidth: 260)
            } else if let activity = model.maaUpdateActivity {
                Text("已用时 \(activity.startedAt, style: .timer) · 上限 \(UpdatePolicy.durationDescription(activity.timeout))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.isExternalRunActive, !model.canCancelRun, !model.isCancellingRun {
                Label("定时任务在后台运行", systemImage: "clock.badge.checkmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
