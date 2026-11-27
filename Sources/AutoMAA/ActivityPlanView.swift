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
    private var snapshot: ActivityPlanSnapshot {
        ActivityPlanSnapshot(planID: planID,
            sessions: ActivityHistory.sessions(from: model.activityEntries),
            activePlanID: model.activePlanID, activeRunID: model.activeRunID,
            isWorkflowRunning: model.isWorkflowRunning)
    }

    var body: some View {
        if let plan = model.configuration.plans.first(where: { $0.id == planID }) {
            let activity = snapshot
            if activity.isCurrent {
                ActivityLiveLog(entries: activity.displayedSession?.entries ?? [])
                    .id(model.activeRunID)
                    .padding(16)
            } else {
                overview(plan: plan, progress: model.continuation(for: planID), latest: activity.displayedSession)
            }
        } else {
            ActivityEmptyState(title: "方案已被移除", symbol: "tray", detail: "历史结果仍可在运行记录中查看。")
        }
    }

    private func overview(plan: AutomationPlan, progress: PlanContinuation, latest: ActivitySession?) -> some View {
        let runState = model.planRunState(planID: plan.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if progress.hasPendingWork {
                    HStack(alignment: .firstTextBaseline) {
                        Text("需要处理").font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        if let roundID = progress.resumableRoundID {
                            if runState == .configurationIncomplete {
                                ActionTextButton(title: "检查配置", symbol: "exclamationmark.circle") {
                                    model.readinessRequest = .init(id: planID)
                                }
                            } else {
                                ActionTextButton(title: "继续本轮", symbol: "play.fill",
                                                 help: model.runHelp(for: planID, request: .resume(roundID: roundID))) {
                                    model.runPlan(planID, request: .resume(roundID: roundID))
                                }
                                .disabled(runState != .ready)
                            }
                        }
                    }
                    PendingWorkList(items: progress.resumableRoundID == nil ? [] : progress.pendingItems,
                                    recovery: progress.fightRecoveryItems)
                    if progress.hasExpiredScope, progress.resumableRoundID != nil {
                        Text("仅续跑仍在当前游戏日的账号。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let latest {
                        Divider()
                        let date = latest.startedAt.formatted(.dateTime.year().month().day().hour().minute())
                        ActionTextButton(title: "最近运行 · \(date)", symbol: "clock.arrow.circlepath",
                                         help: "在运行记录中查看该次结果和日志") { openRecord(latest) }
                    }
                } else {
                    PlanRoundSummary(progress: progress, runState: runState)
                    if !progress.hasStarted, model.isPlanScheduleCurrent(plan),
                       let next = PlanScheduleFormatter.nextRunLabel(plan.schedule) {
                        Text("下次 \(next)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let latest {
                        Divider()
                        ActivityRecordHeader(session: latest, title: "最近运行") { openRecord(latest) }
                        ActivitySessionContents(session: latest).id(latest.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func openRecord(_ session: ActivitySession) {
        if let runID = session.runID {
            model.showActivity(runID: runID)
        } else {
            model.activitySearch = ""
            model.activityFilter = .all
            model.activitySelection = .session(session.id)
            model.selection = .activity
        }
    }
}

struct ActivityCurrentRunView: View {
    @EnvironmentObject private var model: AppModel
    var title = "后台运行"

    private var session: ActivitySession? {
        guard model.isWorkflowRunning, let runID = model.activeRunID else { return nil }
        return ActivityHistory.sessions(from: model.activityEntries).first {
            $0.runID == runID && !$0.isStandaloneMaintenance && (model.activePlanID == nil || $0.planID == model.activePlanID)
        }
    }

    var body: some View {
        let session = self.session
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if session?.entries.last?.message != model.activeStatusMessage {
                    Text(model.activeStatusMessage)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if model.isExternalRunActive, !model.canCancelRun, !model.isCancellingRun {
                    Text(WorkspaceRunControlState(model: model).stopHelp)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            ActivityLiveLog(entries: session?.entries ?? [])
                .id(model.activeRunID)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
