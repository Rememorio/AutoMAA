import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Context navigation")
struct ContextNavigationTests {
    @Test("an empty execution scope opens the editor that can supply an enabled account")
    func readinessEmptyConfigurationRepair() {
        let planID = UUID()
        let issue = ReadinessIssue(id: "plan-accounts-empty", severity: .error,
                                   message: "没有可执行的账号", scope: .plan(planID))
        func repair(_ clients: [ClientConfiguration]) -> PlanReadinessDestination? {
            PlanReadiness.repairDestination(for: issue, clients: clients)
        }
        var client = ClientConfiguration(name: "测试客户端", kind: .official, appPath: "", address: "127.0.0.1:65130",
                                        profileName: "test", bundleIdentifier: "dev.automaa.tests.navigation", accounts: [])
        #expect(repair([]) == .newClient)
        #expect(repair([client]) == .newAccount(clientID: client.id, planID: planID))
        var other = client
        other.id = UUID()
        #expect(repair([client, other]) == .clients)
        client.enabled = false
        #expect(repair([client]) == .configuration(.client(client.id)))
        client.enabled = true
        var account = AccountConfiguration(name: "测试账号")
        account.enabled = false
        client.accounts = [account]
        #expect(repair([client]) == .configuration(.account(clientID: client.id, accountID: account.id)))
        client.accounts[0].enabled = true
        #expect(repair([client]) == .arrangement(planID))

        let environment = ReadinessIssue(id: "maa-cli-missing", severity: .error,
                                        message: "缺少 MAA", repairTarget: .settings)
        #expect(PlanReadiness.repairDestination(for: environment, clients: []) == .configuration(.settings))
        let unknown = ReadinessIssue(id: "unmapped", severity: .warning, message: "需要人工检查")
        #expect(PlanReadiness.repairDestination(for: unknown, clients: []) == nil)
    }

    @Test("overview schedule links open the owning plan at its schedule")
    @MainActor
    func scheduleNavigation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let plan = try #require(model.configuration.plans.last)
        model.showArrangement(for: plan.id, opensAtSchedule: true)
        #expect(model.selection == .plan(plan.id))
        #expect(model.arrangementRequest?.id == plan.id)
        #expect(model.arrangementRequest?.opensAtSchedule == true)
        model.showArrangement(for: plan.id)
        #expect(model.arrangementRequest?.opensAtSchedule == false)
    }

    @Test("standalone maintenance opens its settings history and preserves workspace filters")
    @MainActor
    func updateResultNavigation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let maintenanceID = UUID(), planRunID = UUID()
        let plan = try #require(model.configuration.plans.first)
        let history = HistoryStore(directories: model.directories)
        history.append(.init(level: .info, message: "维护", runID: maintenanceID, phase: .updating))
        history.append(.init(level: .success, message: "已完成", runID: maintenanceID, phase: .completed))
        history.append(.init(level: .info, message: "运行前更新", runID: planRunID, phase: .updating, planID: plan.id))
        model.activitySearch = "账号搜索"
        model.activityFilter = .failed
        model.selection = .clients
        model.showActivity(runID: maintenanceID)
        #expect(model.selection == .clients)
        #expect(model.settingsSection == .environment)
        #expect(model.showsMaintenanceHistory)
        #expect(model.maintenanceHistorySelection == model.maintenanceSessions.first?.id)
        #expect(model.maintenanceSessions.map(\.runID) == [maintenanceID])
        #expect(model.activitySearch == "账号搜索")
        #expect(model.activityFilter == .failed)
        #expect(model.activityNavigationRequest == nil)

        model.showSettings(.general)
        #expect(!model.showsMaintenanceHistory)
        model.showActivity(runID: planRunID)
        #expect(model.selection == .activity)
        #expect(model.activitySearch.isEmpty)
        #expect(model.activityFilter == .all)
        #expect(model.activityNavigationRequest?.runID == planRunID)
    }

    @Test("history clearing preserves the other scope, logs and active work", arguments: [false, true])
    @MainActor
    func clearsOnlySelectedHistory(maintenance: Bool) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let store = HistoryStore(directories: model.directories)
        let maintenanceID = UUID(), runID = UUID(), planID = UUID()
        store.append(.init(level: .info, message: "更新", runID: maintenanceID, phase: .updating))
        store.append(.init(level: .error, message: "失败", runID: maintenanceID, phase: .failed))
        store.append(.init(level: .success, message: "方案内更新", runID: runID, phase: .updating, planID: planID))
        let logStore = DiagnosticLogStore(directories: model.directories)
        logStore.begin(runID: maintenanceID)
        model.reloadActivityHistory()
        let scope: HistoryStore.Scope = maintenance ? .maintenance : .runs
        try withExtendedLifetime(ProcessLock(url: model.directories.lock)) {
            #expect(throws: RuntimeError.self) { _ = try store.clear(scope) }
            #expect(store.load().count == 3)
        }
        if maintenance { model.clearMaintenanceHistory() }
        else { model.clearActivityHistory() }
        #expect(Set(model.activityEntries.compactMap(\.runID)) == [maintenance ? runID : maintenanceID])
        #expect(model.activityEntries == store.load())
        #expect(FileManager.default.fileExists(atPath: logStore.url(for: maintenanceID).path))
    }

    @Test("a removed context record explains the missing destination without replacing filters")
    @MainActor
    func missingRecordNavigation() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        model.activitySearch = "已有条件"
        model.activityFilter = .attention

        model.showActivity(runID: UUID())

        #expect(model.activityNavigationRequest == nil)
        #expect(model.activitySearch == "已有条件")
        #expect(model.activityFilter == .attention)
        #expect(model.feedback.notice(for: .workspace, style: .toast)?.message.contains("记录已被清除") == true)
    }

    @Test("readiness repairs target the owning settings, client or account without changing plan scope")
    @MainActor
    func readinessRepairTargets() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let account = AccountConfiguration(name: "", accountSelector: "")
        let second = AccountConfiguration(name: "测试账号", accountSelector: "")
        let client = ClientConfiguration(name: "", kind: .official, appPath: root.appending(path: "Missing.app").path,
                                         address: "invalid", profileName: "navigation-test", bundleIdentifier: "",
                                         accounts: [account, second])
        let plan = AutomationPlan.lightRoutine
        model.configuration = AppConfiguration(cliPath: root.appending(path: "missing-cli").path,
                                               clients: [client], plans: [plan])
        model.selection = .plan(plan.id)
        let problems = ConfigurationValidator.readinessProblems(in: model.configuration, planID: plan.id)
        let settings = try #require(problems.first { $0.id == "maa-cli-missing" }?.repairTarget)
        #expect(settings == .settings)
        model.showConfigurationRepair(settings)
        #expect(model.selection == .plan(plan.id))
        #expect(model.settingsSection == .environment)
        #expect(model.currentPlanID == plan.id)

        for suffix in ["name-empty", "app-missing", "bundle-missing", "address-invalid"] {
            let problem = try #require(problems.first { $0.id == "client-\(client.id)-\(suffix)" })
            #expect(problem.scope == .plan(plan.id))
            #expect(problem.repairTarget == .client(client.id))
            model.showConfigurationRepair(try #require(problem.repairTarget))
            #expect(model.selection == .clients)
            #expect(model.entityEditor == .client(client.id))
            #expect(model.clientsSelection == .client(client.id))
            #expect(model.currentPlanID == plan.id)
        }
        for suffix in ["name-empty", "selector-empty"] {
            let problem = try #require(problems.first { $0.id == "account-\(account.id)-\(suffix)" })
            #expect(problem.scope == .plan(plan.id))
            #expect(problem.repairTarget == .account(clientID: client.id, accountID: account.id))
            model.showConfigurationRepair(try #require(problem.repairTarget))
            #expect(model.selection == .clients)
            #expect(model.entityEditor == .account(client.id, account.id))
            #expect(model.clientsSelection == .account(clientID: client.id, accountID: account.id))
            #expect(model.currentPlanID == plan.id)
        }
        model.showConfigurationRepair(.account(clientID: client.id, accountID: UUID()))
        #expect(model.clientsSelection == .client(client.id))
        model.showConfigurationRepair(.client(UUID()))
        #expect(model.clientsSelection == .client(client.id))
        let planProblem = ConfigurationProblem(id: "plan-problem", severity: .error,
                                                message: "方案参数错误", scope: .plan(plan.id))
        model.showConfigurationRepair(try #require(planProblem.repairTarget))
        #expect(model.selection == .plan(plan.id))
        #expect(model.currentPlanID == plan.id)
    }

    @Test("unsupported account switching repairs point to the client and affected account")
    func unsupportedSwitchingRepairTargets() throws {
        let root = temporaryRoot()
        let first = AccountConfiguration(name: "测试一", accountSelector: "first")
        let second = AccountConfiguration(name: "测试二")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP,
                                         appPath: root.appending(path: "Missing.app").path,
                                         address: "127.0.0.1:65514", profileName: "navigation-test",
                                         bundleIdentifier: "dev.automaa.tests.navigation", accounts: [first, second])
        let plan = AutomationPlan.lightRoutine
        let configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let problems = ConfigurationValidator.readinessProblems(in: configuration, planID: plan.id)
        #expect(problems.first { $0.id.hasSuffix("account-switch-unsupported") }?.repairTarget == .client(client.id))
        #expect(problems.first { $0.id == "account-\(first.id)-selector-unsupported" }?.repairTarget
                == .account(clientID: client.id, accountID: first.id))
    }

    @Test("stage settings navigation requires a current failure recorded before combat")
    @MainActor
    func fightStageSettingsNavigation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP,
                                         appPath: root.appending(path: "Missing.app").path,
                                         address: "127.0.0.1:65514", profileName: "navigation-test",
                                         bundleIdentifier: "dev.automaa.tests.navigation", accounts: [account])
        let plan = AutomationPlan.lightRoutine
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        model.selection = .activity
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        let store = ExecutionStateStore(directories: model.directories)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        var progress = FightProgress(regularStage: "1-7")
        let failure = FightResult(status: .failed, stage: "1-7", reason: .stageUnavailable)
        progress.regular = failure
        state.record(failure, for: step.key)
        state.fightProgress = [step.key: progress]
        try store.save(state)
        model.reloadActivityHistory()
        #expect(model.canOpenFightStageSettings(for: step))

        let interrupted = FightResult(status: .unconfirmed, stage: "1-7", times: 1, reason: .interruptedBattle)
        progress.regular = interrupted
        state.record(interrupted, for: step.key)
        state.fightProgress = [step.key: progress]
        try store.save(state)
        model.openFightStageSettings(for: step)
        #expect(model.selection == .activity)
        #expect(model.fightSettingsPlanID == nil)
        #expect(!model.canOpenFightStageSettings(for: step))

        progress.regular = failure
        state.record(failure, for: step.key)
        state.fightProgress = [step.key: progress]
        try store.save(state)
        model.openFightStageSettings(for: step)
        #expect(model.selection == .plan(plan.id))
        #expect(model.fightSettingsPlanID == plan.id)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "automaa-navigation-\(UUID())")
    }

    @MainActor
    private func makeModel(root: URL) -> AppModel {
        AppModel(directories: AppDirectories(root: root),
                 launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                 managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false,
                 allowsAutomaticMAAMaintenance: false)
    }
}
