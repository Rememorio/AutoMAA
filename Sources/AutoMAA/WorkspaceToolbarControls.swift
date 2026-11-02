import AutoMAAKit
import Foundation

@MainActor
struct WorkspaceRunControlState {
    enum StartAction { case unavailable, run(UUID), readiness(UUID), activity(UUID) }
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
            stopHelp = "\(model.activePlanID == nil && !model.isExternalRunActive ? "取消更新" : "安全停止") · \(identity)"
        } else {
            stopHelp = "没有正在运行的操作"
        }
        let planID: UUID?
        switch model.selection {
        case let .plan(id): planID = id
        case .activity:
            if case let .plan(id) = model.activitySelection { planID = id } else { planID = nil }
        default: planID = nil
        }
        let selectedPlan = planID.flatMap { id in model.configuration.plans.first { $0.id == id } }
        presentation = selectedPlan != nil ? .plan : (model.isWorkflowRunning ? .stop : .hidden)
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
        switch model.planRunState(planID: planID) {
        case .ready:
            let progress = model.continuation(for: planID)
            if progress.pending > 0 {
                startAction = .run(planID)
                startHelp = "\(model.runTitle(for: planID)) · \(plan.displayName)\n\(model.runHelp(for: planID))"
            } else if progress.unconfirmed > 0 {
                startAction = .activity(planID)
                startHelp = "处理待确认结果 · \(plan.displayName)"
            } else {
                startAction = .unavailable
                startHelp = "\(progress.completionTitle) · \(plan.displayName)"
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
        case let .readiness(id): model.readinessRequest = PlanReadinessRequest(id: id)
        case let .activity(id): model.showPlanActivity(id)
        }
    }
}
