import AutoMAAKit
import Foundation

@MainActor
struct WorkspaceRunControlState {
    enum Presentation { case hidden, plan, stop }
    let presentation: Presentation
    let canStart: Bool
    let startHelp: String
    let canStop: Bool
    let stopHelp: String

    var startLabel: String { String(startHelp.prefix { $0 != "\n" }) }

    init(model: AppModel) {
        let identity = model.activePlanID.flatMap { id in
            model.configuration.plans.first { $0.id == id }?.displayName
        } ?? (model.isExternalRunActive ? "后台任务" : "MAA 维护")
        let hasGameWorkflow = model.isWorkflowRunning && !model.isMAAMaintenanceRunning
        canStop = OperationCommandScope.workspace.canCancel(in: model)
        if model.isMAAMaintenanceRunning {
            stopHelp = "MAA 维护中，可在 MAA 环境设置中查看进度"
        } else if model.isCancellingRun {
            stopHelp = "正在停止并清理 · \(identity)"
        } else if model.isExternalRunActive && !canStop {
            stopHelp = "后台任务尚未提供安全停止入口"
        } else if hasGameWorkflow {
            stopHelp = "安全停止 · \(identity)"
        } else {
            stopHelp = "没有正在运行的游戏任务"
        }
        guard case let .plan(planID) = model.selection,
              let plan = model.configuration.plans.first(where: { $0.id == planID }) else {
            presentation = hasGameWorkflow && model.selection != .overview ? .stop : .hidden
            canStart = false
            startHelp = "选择方案后运行"
            return
        }
        presentation = .plan
        canStart = model.commandRunRequest == .newRound
        let title = "运行新一轮 · \(plan.displayName)"
        if canStart {
            startHelp = title + "\n" + model.runHelp(for: planID)
        } else if model.isMAAMaintenanceRunning {
            startHelp = title + "\nMAA 维护结束后可运行方案"
        } else if model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow {
            startHelp = title + "\n当前操作结束后可运行方案"
        } else if model.planReadiness(for: planID).hasBlockingErrors {
            startHelp = title + "\n请先检查配置"
        } else {
            startHelp = title + "\n当前没有可执行任务"
        }
    }

    func openOperation(in model: AppModel) {
        if model.isMAAMaintenanceRunning { model.showSettings(.environment) }
        else { model.showCurrentActivity() }
    }

    func stopWorkflow(in model: AppModel) {
        guard canStop else { return }
        OperationCommandScope.workspace.cancel(in: model)
    }
}

enum OperationCommandScope {
    case workspace, maaEnvironment, applicationUpdate, unavailable

    static func resolve(focusedScope: Self?, workspaceActive: Bool, hasSheet: Bool) -> Self {
        guard !hasSheet else { return .unavailable }
        return focusedScope ?? (workspaceActive ? .workspace : .unavailable)
    }

    var cancelTitle: String {
        switch self {
        case .workspace, .unavailable: "安全停止当前流程"
        case .maaEnvironment: "取消 MAA 更新"
        case .applicationUpdate: "取消软件更新"
        }
    }

    @MainActor func canCancel(in model: AppModel) -> Bool {
        switch self {
        case .workspace: model.canCancelRun && !model.isMAAMaintenanceRunning
        case .maaEnvironment: model.canCancelRun && model.isMAAMaintenanceRunning
        case .applicationUpdate: model.applicationUpdateState.canCancel
        case .unavailable: false
        }
    }

    @MainActor func cancel(in model: AppModel) {
        guard canCancel(in: model) else { return }
        switch self {
        case .workspace, .maaEnvironment: model.cancelRun()
        case .applicationUpdate: model.cancelApplicationUpdate()
        case .unavailable: break
        }
    }
}
