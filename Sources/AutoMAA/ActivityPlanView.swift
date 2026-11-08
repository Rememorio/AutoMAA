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
    var isTodayDetail = false

    private var plan: AutomationPlan? { model.configuration.plans.first { $0.id == planID } }
    private var source: ActivityPendingSource? { isTodayDetail ? model.activityPendingSource : nil }
    private var progress: PlanContinuation { model.continuation(for: planID, continuingFrom: source?.continuationDate) }
    private var snapshot: ActivityPlanSnapshot {
        ActivityPlanSnapshot(planID: planID,
            sessions: ActivityHistory.sessions(from: model.activityEntries),
            activePlanID: model.activePlanID, activeRunID: model.activeRunID,
            isWorkflowRunning: model.isWorkflowRunning)
    }

    private var showsPendingWork: Bool { isTodayDetail && progress.hasPendingWork }

    var body: some View {
        if let plan {
            VStack(spacing: 0) {
                header(plan)
                    .padding(20)
                Divider()
                if snapshot.isCurrent { liveContent }
                else if snapshot.latestSession == nil, !progress.hasStarted, progress.fightRecoveryItems.isEmpty {
                    ActivityEmptyState(title: "还没有运行记录", symbol: "clock.arrow.circlepath",
                                       detail: "运行后会显示这份方案的结果与完整日志。")
                } else { idleContent }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ActivityEmptyState(title: "方案已被移除", symbol: "tray", detail: "历史结果仍可在运行记录中查看。")
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPendingWork {
                ScrollView {
                    pendingWork
                        .padding(.horizontal, 20).padding(.vertical, 12)
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

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if showsPendingWork {
                    pendingWork
                    if snapshot.latestSession != nil { Divider() }
                }
                if let session = snapshot.latestSession {
                    VStack(alignment: .leading, spacing: 16) {
                        ActivityRecordHeader(session: session, title: "最近运行", showFullHistory: showFullHistory)
                        ActivitySessionContents(session: session).id(session.id)
                    }
                } else {
                    ActivityEmptyState(title: "还没有运行记录", symbol: "clock.arrow.circlepath",
                                       detail: "运行后会显示这份方案的结果与完整日志。")
                        .frame(minHeight: 160)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pendingWork: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("待办").font(.subheadline.weight(.semibold))
            PendingWorkList(items: progress.hasStarted ? progress.pendingItems : [], recovery: progress.fightRecoveryItems)
        }
    }

    private func header(_ plan: AutomationPlan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if isTodayDetail || snapshot.isCurrent {
                Text(isTodayDetail ? plan.displayName : "本次运行")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            if let source {
                Text("续跑 · \(source.startedAt.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if !snapshot.isCurrent { todaySummary(plan) }
            if !isTodayDetail, progress.hasPendingWork {
                PendingWorkLinkButton { model.showPlanActivity(planID) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func todaySummary(_ plan: AutomationPlan) -> some View {
        let runState = model.planRunState(planID: planID)
        return VStack(alignment: .leading, spacing: 5) {
            if progress.hasExpiredScope, progress.pending == 0, progress.unconfirmed == 0 {
                Text("本轮续跑已结束").font(.caption).foregroundStyle(.secondary)
                ActionTextButton(title: "查看当前待办", symbol: "chevron.right", symbolAfterTitle: true) {
                    model.showPlanActivity(planID)
                }
            } else {
                PlanTodaySummary(progress: progress, runState: runState, showsGuidance: !isTodayDetail)
                if isTodayDetail, progress.hasStarted, progress.pending > 0, runState == .ready {
                    let accounts = Set(progress.pendingItems.map(\.step.accountID))
                    Text("点击顶部播放，继续 \(accounts.count) 个账号的待办。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if progress.hasExpiredScope {
                    Text("已刷新服务器的日常续跑已结束。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if progress.manuallyHandled > 0 {
                Text("\(progress.manuallyHandled) 项作战已人工处理，今天不再重试")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if source == nil, !progress.hasStarted, model.isPlanScheduleCurrent(plan),
               let next = PlanScheduleFormatter.nextRunLabel(plan.schedule) {
                Text("下次 \(next)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
            Text(model.activeStatusMessage)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(3).textSelection(.enabled).help(model.activeStatusMessage)
            if model.activePlanID == nil, let activity = model.maaUpdateActivity {
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
