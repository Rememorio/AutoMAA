import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Dashboard plan status")
struct DashboardPlanStatusTests {
    @Test("an empty or merely started plan is never presented as completed")
    func emptyWorkIsNotCompletion() {
        var progress = emptyProgress()
        for started in [false, true] {
            progress.hasStarted = started
            let status = DashboardPlanStatus.resolve(runState: .ready, progress: progress, readiness: ready)
            #expect(status.title == "尚未运行")
            #expect(status.tone != .success)
        }
    }

    @Test("unconfirmed results stay actionable even when configuration needs repair")
    func unconfirmedResultsRemainVisible() {
        var progress = emptyProgress()
        progress.hasStarted = true
        progress.resolved = 3
        progress.unconfirmed = 1
        let status = DashboardPlanStatus.resolve(runState: .configurationIncomplete, progress: progress, readiness: ready)
        #expect(status.title == "1 项结果待确认")
        #expect(status.destination == .activity)
        #expect(status.tone == .attention)
        let running = DashboardPlanStatus.resolve(runState: .running, progress: progress, readiness: ready)
        #expect(running.title == "正在运行")
    }

    @Test("remaining work and manual handling retain their distinct meanings")
    func unfinishedAndManualWork() {
        var progress = emptyProgress()
        progress.hasStarted = true
        progress.resolved = 3
        progress.pending = 2
        let pending = DashboardPlanStatus.resolve(runState: .ready, progress: progress, readiness: ready)
        #expect(pending.title == "还有 2 项未完成")
        #expect(pending.destination == .activity)
        progress.pending = 0
        #expect(DashboardPlanStatus.resolve(runState: .ready, progress: progress, readiness: ready).title == "今日已完成")
        progress.manuallyHandled = 1
        let handled = DashboardPlanStatus.resolve(runState: .ready, progress: progress, readiness: ready)
        #expect(handled.title == "今日已处理")
        #expect(handled.tone != .success)
    }

    @Test("nonblocking reminders retain access to readiness details")
    func warningsHaveARepairDestination() {
        let readiness = PlanReadiness(planID: UUID(), issues: [
            .init(id: "warning", severity: .warning, message: "提醒"),
        ])
        let status = DashboardPlanStatus.resolve(runState: .ready, progress: emptyProgress(), readiness: readiness)
        #expect(status.title == "1 项提醒")
        #expect(status.destination == .readiness)
        #expect(!readiness.hasBlockingErrors)
    }

    private var ready: PlanReadiness { .init(planID: UUID(), issues: []) }

    private func emptyProgress() -> PlanContinuation {
        .init(configuration: AppConfiguration(clients: []), planID: UUID(), state: .init(dateKey: ""), history: [])
    }
}
