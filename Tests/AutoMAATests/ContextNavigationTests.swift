import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Context navigation")
struct ContextNavigationTests {
    @Test("opening an update result reveals its run while ordinary navigation retains filters")
    @MainActor
    func updateResultNavigation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let runID = UUID()
        let history = HistoryStore(directories: model.directories)
        history.append(.init(level: .success, message: "MAA 更新完成", runID: runID, phase: .completed))
        history.append(.init(level: .error, message: "其他运行失败", runID: UUID(), phase: .failed))
        model.activitySearch = "账号搜索"
        model.activityFilter = .failed

        model.showActivity(runID: runID)

        #expect(model.selection == .activity)
        #expect(model.activitySearch.isEmpty)
        #expect(model.activityFilter == .all)
        let request = try #require(model.activityNavigationRequest)
        #expect(request.runID == runID)
        #expect(ActivityHistory.sessions(from: model.activityEntries).contains { $0.runID == request.runID })
        model.finishActivityNavigation(request)
        #expect(model.activityNavigationRequest == nil)

        model.activitySearch = "账号搜索"
        model.activityFilter = .failed
        model.selection = .settings
        model.selection = .activity
        #expect(model.activitySearch == "账号搜索")
        #expect(model.activityFilter == .failed)
        #expect(model.activityNavigationRequest == nil)
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
        #expect(model.bannerMessage?.contains("记录已被清除") == true)
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
        let problems = ConfigurationValidator.readinessProblems(in: model.configuration, planID: plan.id)
        let settings = try #require(problems.first { $0.id == "maa-cli-missing" }?.repairTarget)
        #expect(settings == .settings)
        model.showConfigurationRepair(settings)
        #expect(model.selection == .settings)

        for suffix in ["name-empty", "app-missing", "bundle-missing", "address-invalid"] {
            let problem = try #require(problems.first { $0.id == "client-\(client.id)-\(suffix)" })
            #expect(problem.scope == .plan(plan.id))
            #expect(problem.repairTarget == .client(client.id))
            model.showConfigurationRepair(try #require(problem.repairTarget))
            #expect(model.selection == .client(client.id))
        }
        for suffix in ["name-empty", "selector-empty"] {
            let problem = try #require(problems.first { $0.id == "account-\(account.id)-\(suffix)" })
            #expect(problem.scope == .plan(plan.id))
            #expect(problem.repairTarget == .account(clientID: client.id, accountID: account.id))
            model.showConfigurationRepair(try #require(problem.repairTarget))
            #expect(model.selection == .account(client.id, account.id))
        }
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
