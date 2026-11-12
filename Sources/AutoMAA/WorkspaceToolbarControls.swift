import AutoMAAKit
import Foundation

@MainActor
struct WorkspaceRunControlState {
    enum StartAction { case unavailable, run(UUID), resume(UUID, UUID), readiness(UUID), activity(UUID) }
    enum Presentation { case hidden, plan, stop }
    let presentation: Presentation
    let startAction: StartAction
    let startHelp: String
    let canStop: Bool
    let stopHelp: String

    var canStart: Bool {
        if case .unavailable = startAction { return false }
        return true
    }

    init(model: AppModel) {
        let identity = model.activePlanID.flatMap { id in
            model.configuration.plans.first { $0.id == id }?.displayName
        } ?? (model.isExternalRunActive ? "后台任务" : "MAA 维护")
        canStop = model.isWorkflowRunning && model.canCancelRun && !model.isCancellingRun
        if model.isCancellingRun {
            stopHelp = "正在停止并清理 · \(identity)"
        } else if model.isWorkflowRunning {
            stopHelp = "\(model.isMAAMaintenanceRunning ? "取消更新" : "安全停止") · \(identity)"
        } else {
            stopHelp = "没有正在运行的操作"
        }
        let planID: UUID?
        let isPending: Bool
        switch (model.selection, model.activitySelection) {
        case let (.plan(id), _):
            planID = id
            isPending = false
        case let (.activity, .plan(id)):
            planID = id
            isPending = true
        default:
            planID = nil
            isPending = false
        }
        let selectedPlan = planID.flatMap { id in model.configuration.plans.first { $0.id == id } }
        let roundID = planID.flatMap { model.activityRoundID(for: $0) }
        presentation = model.selection == .overview ? .hidden
            : selectedPlan != nil ? .plan : (model.isWorkflowRunning ? .stop : .hidden)
        guard !model.isWorkflowRunning else {
            startAction = .unavailable
            startHelp = "运行结束后可开始其他任务"
            return
        }
        guard let planID, let plan = selectedPlan else {
            startAction = .unavailable
            startHelp = "选择方案后运行"
            return
        }
        let progress = model.continuation(for: planID, roundID: roundID)
        if isPending, progress.pending == 0, progress.unconfirmed > 0 {
            startAction = .unavailable
            startHelp = "请先核实待办中的作战结果 · \(plan.displayName)"
            return
        }
        if isPending, progress.pending == 0, progress.hasExpiredScope {
            startAction = .unavailable
            startHelp = "本轮续跑已结束 · \(plan.displayName)"
            return
        }
        switch model.planRunState(planID: planID) {
        case .ready:
            if isPending, progress.hasStarted, progress.pending > 0, let roundID = progress.roundID {
                startAction = .resume(planID, roundID)
                let request = WorkflowRunRequest.resume(roundID: roundID)
                startHelp = "\(model.runTitle(for: planID, request: request)) · \(plan.displayName) · \(progress.pending) 项待办\n\(model.runHelp(for: planID, request: request))"
            } else if !isPending, progress.newRoundTasks > 0 {
                startAction = .run(planID)
                startHelp = "运行一轮 · \(plan.displayName)\n\(model.runHelp(for: planID))"
            } else if progress.unconfirmed > 0 {
                startAction = .activity(planID)
                startHelp = "处理待确认结果 · \(plan.displayName)"
            } else {
                startAction = .unavailable
                startHelp = "\(progress.roundID == nil ? "请从方案页开启新一轮" : progress.completionTitle) · \(plan.displayName)"
            }
        case .configurationIncomplete:
            startAction = .readiness(planID)
            startHelp = "检查配置 · \(plan.displayName)"
        default:
            startAction = .unavailable
            startHelp = "当前无法运行 · \(plan.displayName)"
        }
    }

    func start(in model: AppModel) {
        switch startAction {
        case .unavailable: break
        case let .run(id): model.runPlan(id)
        case let .resume(id, roundID): model.runPlan(id, request: .resume(roundID: roundID))
        case let .readiness(id): model.readinessRequest = PlanReadinessRequest(id: id)
        case let .activity(id): model.showPlanActivity(id)
        }
    }

    func openOperation(in model: AppModel) {
        if model.isMAAMaintenanceRunning { model.showSettings(.environment) }
        else { model.showCurrentActivity() }
    }

    func stopWorkflow(in model: AppModel) {
        guard canStop, !model.isMAAMaintenanceRunning else { return }
        model.cancelRun()
    }
}
