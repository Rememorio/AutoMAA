import AutoMAAKit

/// A short overview status; full reasons and recovery actions stay in their owning workspace.
struct DashboardPlanStatus: Equatable {
    enum Tone { case neutral, active, attention, success }
    enum Destination { case activity, readiness }
    let title: String
    var tone: Tone = .neutral
    var destination: Destination?

    static func resolve(runState: PlanRunState, progress: PlanContinuation, readiness: PlanReadiness) -> Self {
        if runState == .running {
            return .init(title: "正在运行", tone: .active, destination: .activity)
        }
        if progress.unconfirmed > 0 {
            return .init(title: "\(progress.unconfirmed) 项结果待确认", tone: .attention, destination: .activity)
        }
        if !progress.fightRecoveryItems.isEmpty {
            return .init(title: "作战需要处理", tone: .attention, destination: .activity)
        }
        if progress.hasStarted, progress.pending > 0 {
            return .init(title: "还有 \(progress.pending) 项未完成", destination: .activity)
        }
        if progress.hasStarted, progress.resolved > 0, progress.pending == 0 {
            return .init(title: progress.completionTitle,
                         tone: progress.manuallyHandled > 0 ? .neutral : .success, destination: .activity)
        }
        switch runState {
        case .configurationIncomplete:
            return .init(title: "需要完成配置", tone: .attention, destination: .readiness)
        case .anotherPlanRunning:
            return .init(title: "其他方案运行中")
        case .maintenanceRunning:
            return .init(title: "维护进行中")
        case .ready, .running:
            if case let .warnings(count) = readiness.state {
                return .init(title: "\(count) 项提醒", tone: .attention, destination: .readiness)
            }
            return .init(title: "尚未运行")
        }
    }
}
