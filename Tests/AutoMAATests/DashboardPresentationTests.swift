import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Dashboard presentation")
struct DashboardPresentationTests {
    @Test("active operation identity takes precedence over the idle selection")
    func focusUsesActualRun() {
        let first = summary(.init(name: "方案甲"))
        let second = summary(.init(name: "方案乙"))
        let plans = [first, second]
        #expect(snapshot(plans, current: second.id).focusedPlan?.id == second.id)
        #expect(snapshot(plans, current: second.id, active: first.id, running: true).focusedPlan?.id == first.id)
        #expect(snapshot(plans, current: second.id, running: true).focusedPlan == nil)
        #expect(snapshot(plans, current: UUID()).focusedPlan?.id == first.id)
        #expect(snapshot([], current: second.id).focusedPlan == nil)
    }

    @Test("recent results exclude maintenance and the active run and retain unfinished history")
    func recentPlanRuns() {
        let plan = AutomationPlan(name: "方案")
        let entries = (0..<6).map { index in
            LogEntry(timestamp: Date(timeIntervalSince1970: Double(index)), level: .info,
                     message: "记录", runID: UUID(), phase: .runningTask, planID: index == 4 ? nil : plan.id)
        }
        let value = snapshot([summary(plan)], current: plan.id, active: plan.id,
                             activeRun: entries[5].runID, running: true, entries: entries)
        #expect(value.recentRuns.map(\.runID) == [entries[3].runID, entries[2].runID, entries[1].runID])
        #expect(value.recentRuns.allSatisfy { $0.hasUnfinishedActivity })
    }

    @Test("shared configuration issues appear once and plan issues route to their owner")
    func readinessKeepsOwnership() {
        let first = AutomationPlan(name: "方案甲")
        let second = AutomationPlan(name: "方案乙")
        let issues: [ReadinessIssue] = [
            .init(id: "shared", severity: .error, message: "环境缺失"),
            .init(id: "invalid", severity: .error, message: "配置有误", scope: .plan(second.id)),
            .init(id: "warning", severity: .warning, message: "提醒"),
        ]
        let value = snapshot([summary(first, issues: issues), summary(second, issues: issues)], current: first.id)
        #expect(value.attention.count == 2)
        #expect(value.attention[0].detail == "运行前检查")
        #expect(value.attention[1].detail == "方案乙")
        #expect(value.attention[1].destination == .readiness(second.id))
    }

    @Test("unconfirmed checkpoint remains actionable with no history")
    func checkpointOutlivesHistory() {
        let plan = AutomationPlan(name: "方案")
        var progress = emptyProgress()
        progress.unconfirmed = 2
        let value = snapshot([summary(plan, progress: progress)], current: plan.id)
        #expect(value.recentRuns.isEmpty)
        #expect(value.attention.map(\.title) == ["2 项结果待确认"])
        #expect(value.attention.first?.destination == .activity(plan.id))
    }

    @Test("account scope includes only selected enabled accounts on enabled clients")
    func effectiveScope() {
        let selected = AccountConfiguration(name: "选中账号")
        let disabled = AccountConfiguration(name: "停用账号", enabled: false)
        let other = AccountConfiguration(name: "其他账号")
        let clients = [
            ClientConfiguration(name: "启用客户端", kind: .official, appPath: "/tmp/overview-fixture.app",
                address: "127.0.0.1:49261", profileName: "overview-test", bundleIdentifier: "test.overview.client",
                accounts: [selected, disabled, other]),
            ClientConfiguration(name: "停用客户端", kind: .official, appPath: "/tmp/overview-disabled.app",
                address: "127.0.0.1:49262", profileName: "overview-disabled", bundleIdentifier: "test.overview.disabled",
                enabled: false, accounts: [.init(name: "停用客户端账号")]),
        ]
        let plan = AutomationPlan(name: "方案", includesAllEnabledAccounts: false, accountIDs: [selected.id, disabled.id])
        let value = summary(plan, configuration: .init(clients: clients, plans: [plan]))
        #expect(value.accountCount == 1)
        #expect(value.clientCount == 1)
    }

    @Test("only verified schedules enter the upcoming list")
    func scheduleVerification() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var plan = AutomationPlan(name: "方案")
        plan.schedule.enabled = true
        let scheduled = DashboardScheduleState.resolve(plan: plan, isCurrent: true, isInstalled: true,
                                                       isSynchronizing: false, now: now)
        guard case let .scheduled(date) = scheduled else { Issue.record("Expected a verified schedule"); return }
        #expect(date > now)
        #expect(DashboardScheduleState.resolve(plan: plan, isCurrent: false, isInstalled: true,
                                               isSynchronizing: false, now: now) == .needsAttention)
        #expect(DashboardScheduleState.resolve(plan: plan, isCurrent: false, isInstalled: true,
                                               isSynchronizing: true, now: now) == .synchronizing)
        plan.schedule.enabled = false
        #expect(DashboardScheduleState.resolve(plan: plan, isCurrent: false, isInstalled: true,
                                               isSynchronizing: false, now: now) == .needsAttention)
        #expect(DashboardScheduleState.resolve(plan: plan, isCurrent: false, isInstalled: false,
                                               isSynchronizing: false, now: now) == .unscheduled)
        let late = summary(.init(name: "较晚"), schedule: .scheduled(now.addingTimeInterval(200)))
        let early = summary(.init(name: "较早"), schedule: .scheduled(now.addingTimeInterval(100)))
        let broken = summary(.init(name: "失效"), schedule: .needsAttention)
        let value = snapshot([late, broken, early], current: late.id)
        #expect(value.upcoming.map(\.id) == [early.id, late.id])
        #expect(value.attention.last?.destination == .schedule(broken.id))
    }

    private func emptyProgress() -> PlanContinuation {
        .init(configuration: .init(clients: []), planID: UUID(), state: .init(dateKey: ""), history: [])
    }

    @Test("warnings remain available on a plan outside the current focus")
    func unfocusedPlanWarnings() {
        let first = AutomationPlan(name: "方案甲")
        let second = AutomationPlan(name: "方案乙")
        let value = snapshot([summary(first), summary(second, issues: [
            .init(id: "warning", severity: .warning, message: "检查关卡", scope: .plan(second.id)),
        ])], current: first.id)
        #expect(value.focusedPlan?.id == first.id)
        #expect(value.plans.last?.status.title == "1 项提醒")
        #expect(value.plans.last?.status.destination == .readiness)
    }

    @Test("overview date rollover does not reuse yesterday's checkpoints")
    @MainActor
    func checkpointsFollowOverviewDate() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dashboard-date-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let model = AppModel(directories: directories, launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                             managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false,
                             allowsAutomaticMAAMaintenance: false)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: root.appending(path: "Fake.app").path,
            address: "127.0.0.1:49263", profileName: "overview-date", bundleIdentifier: "test.overview.date", accounts: [account])
        let plan = AutomationPlan.lightRoutine
        let now = Date()
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: now))
        let steps = Set(plan.enabledTasks.map { WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: $0).key })
        try ExecutionStateStore(directories: directories).save(.init(dateKey: ExecutionStateStore.dateKey(for: now), completedSteps: steps))
        model.configuration = .init(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        model.reloadActivityHistory()
        #expect(model.dashboardSnapshot(at: now).focusedPlan?.progress.pending == 0)
        #expect(model.dashboardSnapshot(at: tomorrow).focusedPlan?.progress.pending == plan.enabledTasks.count)
    }

    private func summary(_ plan: AutomationPlan, configuration: AppConfiguration = .init(clients: []),
                         issues: [ReadinessIssue] = [], progress: PlanContinuation? = nil,
                         schedule: DashboardScheduleState = .unscheduled) -> DashboardPlanSummary {
        .init(plan: plan, configuration: configuration, progress: progress ?? emptyProgress(),
              readiness: .init(planID: plan.id, issues: issues), runState: .ready, schedule: schedule)
    }

    private func snapshot(_ plans: [DashboardPlanSummary], current: UUID?, active: UUID? = nil,
                          activeRun: UUID? = nil, running: Bool = false, entries: [LogEntry] = []) -> DashboardSnapshot {
        .init(plans: plans, currentPlanID: current, activePlanID: active, activeRunID: activeRun,
              isRunning: running, entries: entries)
    }
}
