import AppKit
import AutoMAAKit

enum ApplicationTerminationAction: Equatable {
    case terminate
    case stopWorkflow
    case cancelUpdate
    case waitForCleanup
    case refuse
}

enum ApplicationTerminationPolicy {
    static func action(
        isWorkflowRunning: Bool,
        canCancelRun: Bool,
        isCancellingRun: Bool,
        activePlanID: UUID?,
        applicationUpdateState: ApplicationUpdateState
    ) -> ApplicationTerminationAction {
        if case .installing = applicationUpdateState { return .terminate }
        if isWorkflowRunning {
            if isCancellingRun { return .waitForCleanup }
            guard canCancelRun else { return .refuse }
            return activePlanID == nil ? .cancelUpdate : .stopWorkflow
        }
        if case .cancelling = applicationUpdateState { return .waitForCleanup }
        if applicationUpdateState.canCancel { return .cancelUpdate }
        return applicationUpdateState.isBusy ? .refuse : .terminate
    }
}

struct ApplicationTerminationScope {
    enum Workflow: Equatable {
        case none
        case localPlan(UUID, runID: UUID?)
        case externalRun(WorkflowRunIdentity)
        case maaUpdate(Date)
        case unidentified
    }

    enum Update: Equatable {
        case none
        case running(Date?)
    }

    let workflow: Workflow
    let update: Update

    func contains(_ current: Self) -> Bool {
        let workflowMatches: Bool
        switch (workflow, current.workflow) {
        case (_, .none): workflowMatches = true
        case (.none, _): workflowMatches = false
        case (_, .unidentified): workflowMatches = true
        case let (.localPlan(plan, runID), .localPlan(currentPlan, currentRunID)):
            workflowMatches = plan == currentPlan
                && (runID == nil || currentRunID == nil || runID == currentRunID)
        default: workflowMatches = workflow == current.workflow
        }
        return workflowMatches && (current.update == .none || update == current.update)
    }

    @MainActor
    static func capture(_ model: AppModel) -> Self {
        let workflow: Workflow
        let identity = WorkflowRunControl(directories: model.directories).activeRun()
        if model.isRunning, let planID = model.activePlanID {
            workflow = .localPlan(planID, runID: identity?.runID)
        } else if model.isRunning, let activity = model.maaUpdateActivity {
            workflow = .maaUpdate(activity.startedAt)
        } else if model.isWorkflowRunning, let identity {
            workflow = .externalRun(identity)
        } else {
            workflow = model.isWorkflowRunning ? .unidentified : .none
        }
        return Self(workflow: workflow, update: model.applicationUpdateState.isBusy
                    ? .running(model.applicationUpdateStartedAt) : .none)
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel? {
        didSet {
            if NSApplication.shared.isActive { startActivityMonitoring() }
        }
    }
    private var terminationTask: Task<Void, Never>?
    private var activityMonitoringTask: Task<Void, Never>?

    deinit {
        activityMonitoringTask?.cancel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        startActivityMonitoring()
    }

    func applicationDidResignActive(_ notification: Notification) {
        activityMonitoringTask?.cancel()
        activityMonitoringTask = nil
    }

    private func startActivityMonitoring() {
        guard activityMonitoringTask == nil, let model else { return }
        activityMonitoringTask = Task { [weak model] in
            await model?.monitorExternalActivity()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if case .installing = model.applicationUpdateState { return .terminateNow }
        if terminationTask != nil { return .terminateLater }
        guard model.saveNow(showConfirmation: false) else { return .terminateCancel }

        let action = terminationAction(for: model)
        switch action {
        case .terminate:
            return .terminateNow
        case .refuse:
            let message = "后台任务尚未提供可用的安全停止入口。请等待任务结束，再退出 AutoMAA。"
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "当前无法安全退出"
            alert.informativeText = message
            alert.addButton(withTitle: "返回 AutoMAA")
            alert.runModal()
            return .terminateCancel
        case .stopWorkflow, .cancelUpdate, .waitForCleanup:
            let scope = ApplicationTerminationScope.capture(model)
            guard confirmTermination(action) else { return .terminateCancel }
            waitForTermination(sender, model: model, scope: scope)
            return .terminateLater
        }
    }

    private func terminationAction(for model: AppModel) -> ApplicationTerminationAction {
        ApplicationTerminationPolicy.action(
            isWorkflowRunning: model.isWorkflowRunning,
            canCancelRun: model.canCancelRun,
            isCancellingRun: model.isCancellingRun,
            activePlanID: model.activePlanID,
            applicationUpdateState: model.applicationUpdateState
        )
    }

    private func confirmTermination(_ action: ApplicationTerminationAction) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let buttonTitle: String
        switch action {
        case .stopWorkflow:
            alert.messageText = "安全停止并退出 AutoMAA？"
            alert.informativeText = "退出前会停止当前 MAA 命令、关闭当前客户端并释放连接。清理完成后退出。"
            buttonTitle = "安全停止并退出"
        case .cancelUpdate:
            alert.messageText = "取消更新并退出 AutoMAA？"
            alert.informativeText = "退出前会取消当前更新并等待清理完成，保留当前安装。"
            buttonTitle = "取消更新后退出"
        default:
            alert.messageText = "等待清理后退出 AutoMAA？"
            alert.informativeText = "当前操作正在停止。AutoMAA 会等待清理完成后退出。"
            buttonTitle = "清理完成后退出"
        }
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: buttonTitle)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func waitForTermination(_ sender: NSApplication, model: AppModel, scope: ApplicationTerminationScope) {
        let localWorkflow: Bool
        let runID: UUID?
        switch scope.workflow {
        case let .localPlan(_, id):
            localWorkflow = true
            runID = id
        case let .externalRun(identity):
            localWorkflow = false
            runID = identity.runID
        default:
            localWorkflow = false
            runID = nil
        }
        model.showFeedback("正在停止当前操作，清理完成后退出…", tone: .warning)
        terminationTask = Task { [weak self, weak model] in
            guard let self, let model else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            defer { self.terminationTask = nil }
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            var requestedCancellation = false
            while !Task.isCancelled {
                model.reloadActivityHistory()
                if case .installing = model.applicationUpdateState {
                    sender.reply(toApplicationShouldTerminate: true)
                    return
                }
                guard scope.contains(.capture(model)) else {
                    model.showFeedback("当前操作已变化，已取消本次退出。请确认新的任务或更新后重试。", tone: .warning)
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                if self.terminationAction(for: model) == .terminate {
                    if let failure = self.cleanupFailure(model, localWorkflow: localWorkflow, runID: runID) {
                        model.showFeedback("尚未退出：\(failure)。请查看运行记录后重试。", tone: .warning)
                        sender.reply(toApplicationShouldTerminate: false)
                        return
                    }
                    let saved = model.saveNow(showConfirmation: false)
                    sender.reply(toApplicationShouldTerminate: saved)
                    return
                }
                guard ContinuousClock.now < deadline else {
                    model.showFeedback("停止操作超过 2 分钟，已取消本次退出。请等待清理完成，或在运行记录中检查原因。", tone: .warning)
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                if !requestedCancellation {
                    if model.canCancelRun {
                        model.cancelCurrentOperation()
                        if model.isWorkflowRunning && !model.isCancellingRun {
                            sender.reply(toApplicationShouldTerminate: false)
                            return
                        }
                    }
                    if model.applicationUpdateState.canCancel {
                        model.cancelCurrentOperation()
                    }
                    requestedCancellation = true
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            sender.reply(toApplicationShouldTerminate: false)
        }
    }

    private func cleanupFailure(_ model: AppModel, localWorkflow: Bool, runID: UUID?) -> String? {
        if localWorkflow, let failure = model.lastReport?.fatalError { return failure }
        if let runID,
           let terminal = model.activityEntries.last(where: { $0.runID == runID }),
           terminal.phase == .failed {
            return terminal.message
        }
        return nil
    }
}
