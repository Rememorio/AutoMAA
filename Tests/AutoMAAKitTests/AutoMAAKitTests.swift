import Foundation
import XCTest
@testable import AutoMAAKit

final class AutoMAAKitTests: XCTestCase {
    func testFirstLaunchUsesBlankIdentitiesAndTwoEditableRoutineTemplates() {
        let config = AppConfiguration.defaults

        XCTAssertTrue(config.clients.isEmpty)
        XCTAssertEqual(config.plans.count, 2)
        XCTAssertEqual(config.plans[0].name, "轻量日常")
        XCTAssertEqual(config.plans[0].infrast.mode, .collectOnly)
        XCTAssertFalse(config.plans[0].mall.enabled)
        XCTAssertEqual(config.plans[1].name, "完整日常")
        XCTAssertEqual(config.plans[1].infrast.mode, .fullShift)
        XCTAssertTrue(config.plans[1].mall.enabled)
    }

    func testSupportedClientMappings() {
        XCTAssertEqual(ClientKind.allCases.map(\.maaClientType), [
            "Official", "Bilibili", "Txwy", "YoStarEN", "YoStarJP", "YoStarKR",
        ])
        XCTAssertEqual(ClientKind.txwy.maaTaskClientType, "txwy")
        XCTAssertEqual(ClientKind.yoStarEN.serverCode, "US")
        XCTAssertEqual(ClientKind.txwy.resourceName, "txwy")
    }

    func testFightStagePresetsMatchMAAMacGui() {
        XCTAssertEqual(FightStagePreset.allCases.map(\.rawValue), [
            "", "1-7", "CE-6", "AP-5", "CA-5", "LS-6", "Annihilation",
        ])
    }

    func testTaskSettingsUseOneExplicitConfigurationProtocol() throws {
        let data = try JSONEncoder().encode(FightConfiguration())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["settingsMode"] as? String, "custom")
        XCTAssertEqual(Set(json.keys), ["drGrandet", "enabled", "settingsMode", "stage"])

        let incomplete = Data(#"{"enabled":true,"stage":"","drGrandet":false}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(FightConfiguration.self, from: incomplete))
    }

    func testPlanScopesAccountsDynamically() {
        let first = AccountConfiguration(name: "A")
        let second = AccountConfiguration(name: "B", enabled: false)
        var plan = AutomationPlan.lightRoutine

        XCTAssertTrue(plan.includes(first))
        XCTAssertFalse(plan.includes(second))

        plan.includesAllEnabledAccounts = false
        XCTAssertFalse(plan.includes(first))
        plan.accountIDs.insert(first.id)
        XCTAssertTrue(plan.includes(first))
    }

    func testGeneratedFightUsesPlanParameters() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.plans[0].fight.stage = FightStagePreset.annihilation.rawValue
        config.plans[0].fight.medicine = 3
        config.plans[0].fight.expiringMedicine = 999
        config.plans[0].fight.stone = 0
        config.plans[0].fight.times = 5
        config.plans[0].fight.drGrandet = true
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let params = try generatedParams(.fight, plan: config.plans[0], client: config.clients[0], account: config.clients[0].accounts[0], writer: writer, root: root)
        XCTAssertEqual(params["stage"] as? String, "Annihilation")
        XCTAssertEqual(params["medicine"] as? Int, 3)
        XCTAssertEqual(params["expiring_medicine"] as? Int, 999)
        XCTAssertEqual(params["stone"] as? Int, 0)
        XCTAssertEqual(params["times"] as? Int, 5)
        XCTAssertEqual(params["DrGrandet"] as? Bool, true)
        XCTAssertNil(params["series"])
    }

    func testDisablingCustomSettingsUsesMAADefaultsWithoutErasingPlanValues() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.plans[0].fight.stage = "1-7"
        config.plans[0].fight.medicine = 3
        config.plans[0].fight.usesCustomSettings = false
        config.plans[0].recruit.usesCustomSettings = false
        config.plans[0].infrast.usesCustomSettings = false
        config.plans[0].mall.usesCustomSettings = false
        config.plans[0].award.usesCustomSettings = false
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let plan = config.plans[0]
        let client = config.clients[0]
        let account = client.accounts[0]
        let fight = try generatedParams(.fight, plan: plan, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(fight["stage"] as? String, "")
        XCTAssertNil(fight["medicine"])
        XCTAssertEqual(config.plans[0].fight.stage, "1-7")
        XCTAssertEqual(config.plans[0].fight.medicine, 3)

        let infrast = try generatedParams(.infrast, plan: plan, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(infrast["mode"] as? Int, 0)
        XCTAssertEqual((infrast["facility"] as? [String])?.count, 9)

        let mall = try generatedParams(.mall, plan: plan, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(mall["visit_friends"] as? Bool, true)
        XCTAssertEqual(mall["buy_first"] as? [String], ["招聘许可", "龙门币"])
    }

    func testLightAndCompleteRoutinesGenerateDifferentInfrastModes() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let config = populatedConfiguration()
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let client = config.clients[0]
        let account = client.accounts[0]
        let light = try generatedParams(.infrast, plan: config.plans[0], client: client, account: account, writer: writer, root: root)
        let complete = try generatedParams(.infrast, plan: config.plans[1], client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(light["mode"] as? Int, 20_000)
        XCTAssertEqual(light["drones"] as? String, "Money")
        XCTAssertEqual(complete["mode"] as? Int, 0)
        XCTAssertEqual((complete["facility"] as? [String])?.count, 9)
    }

    func testMallParametersMatchCurrentMAAProtocol() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.plans[1].mall.creditFight = true
        config.plans[1].mall.formationIndex = 2
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let params = try generatedParams(.mall, plan: config.plans[1], client: config.clients[0], account: config.clients[0].accounts[0], writer: writer, root: root)
        XCTAssertEqual(params["visit_friends"] as? Bool, true)
        XCTAssertEqual(params["shopping"] as? Bool, true)
        XCTAssertEqual(params["buy_first"] as? [String], ["招聘许可", "龙门币"])
        XCTAssertEqual(params["blacklist"] as? [String], ["加急许可", "家具零件"])
        XCTAssertEqual(params["credit_fight"] as? Bool, true)
        XCTAssertEqual(params["formation_index"] as? Int, 2)
    }

    func testGeneratedTasksAreScopedByPlan() throws {
        let config = populatedConfiguration()
        let writer = MAAConfigurationWriter(directories: AppDirectories(root: temporaryRoot()))
        let client = config.clients[0]
        let account = client.accounts[0]

        let light = writer.taskName(planID: config.plans[0].id, clientID: client.id, accountID: account.id, task: .fight)
        let complete = writer.taskName(planID: config.plans[1].id, clientID: client.id, accountID: account.id, task: .fight)

        XCTAssertNotEqual(light, complete)
    }

    func testLaunchAgentTargetsExactlyOnePlanAndTime() throws {
        let root = temporaryRoot()
        var plan = AutomationPlan.completeRoutine
        plan.schedule = PlanSchedule(enabled: true, hour: 21, minute: 35)
        let manager = LaunchAgentManager(directories: AppDirectories(root: root))
        let runnerURL = URL(filePath: "/Applications/AutoMAA.app/Contents/MacOS/AutoMAARunner")

        let payload = manager.propertyList(runnerURL: runnerURL, plan: plan)

        XCTAssertEqual(payload["Label"] as? String, manager.label(planID: plan.id))
        XCTAssertEqual(payload["ProgramArguments"] as? [String], [
            runnerURL.path, "--plan", plan.id.uuidString.lowercased(),
        ])
        let interval = try XCTUnwrap(payload["StartCalendarInterval"] as? [String: Int])
        XCTAssertEqual(interval["Hour"], 21)
        XCTAssertEqual(interval["Minute"], 35)
    }

    func testGeneratedProfilesUseServerResources() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = populatedConfiguration()

        try MAAConfigurationWriter(directories: AppDirectories(root: root)).prepare(config)

        let first = try String(contentsOf: root.appending(path: "MAA/profiles/client-1.toml"), encoding: .utf8)
        let second = try String(contentsOf: root.appending(path: "MAA/profiles/client-2.toml"), encoding: .utf8)
        XCTAssertTrue(first.contains("preset = \"PlayCover\""))
        XCTAssertFalse(first.contains("global_resource"))
        XCTAssertTrue(second.contains("global_resource = \"YoStarJP\""))
    }

    func testRemovedPlansCleanUpGeneratedFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let writer = MAAConfigurationWriter(directories: directories)
        var config = populatedConfiguration()
        let plan = config.plans[1]
        let client = config.clients[0]
        let account = client.accounts[0]
        let removedTask = writer.taskName(planID: plan.id, clientID: client.id, accountID: account.id, task: .mall)
        try writer.prepare(config)

        config.plans.removeLast()
        try writer.prepare(config)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "MAA/tasks/\(removedTask).json").path))
    }

    func testDuplicateProfileNamesAreRejectedBeforeGeneratingFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = populatedConfiguration()
        config.clients[1].profileName = config.clients[0].profileName

        XCTAssertThrowsError(try MAAConfigurationWriter(directories: AppDirectories(root: root)).prepare(config)) { error in
            XCTAssertEqual(error as? MAAConfigurationWriterError, .duplicateProfileName)
        }
    }

    func testConfigurationRoundTrip() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(directories: AppDirectories(root: root))
        var config = populatedConfiguration()
        config.clients[0].accounts[0].accountSelector = "unique-fragment"
        config.plans[0].infrast.drones = .combatRecord
        config.plans[1].schedule.enabled = true

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testMismatchedSchemaResetsToCleanDefaults() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let mismatched: [String: Any] = [
            "schemaVersion": AppConfiguration.currentSchemaVersion - 1,
            "cliPath": "/opt/homebrew/bin/maa",
            "clients": [],
            "plans": [],
        ]
        try JSONSerialization.data(withJSONObject: mismatched).write(to: directories.configuration)

        let reset = try ConfigurationStore(directories: directories).load()

        XCTAssertEqual(reset.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertTrue(reset.clients.isEmpty)
        XCTAssertEqual(reset.plans.count, 2)
    }

    func testPortAddressParsing() throws {
        let address = try PortAddress("localhost:1717")
        XCTAssertEqual(address.host, "localhost")
        XCTAssertEqual(address.port, "1717")
        XCTAssertThrowsError(try PortAddress("localhost"))
        XCTAssertThrowsError(try PortAddress(":1717"))
    }

    func testCommandRunnerReturnsAfterSuccessfulExit() async throws {
        let startedAt = Date()
        let result = try await CommandRunner().run(executable: "/usr/bin/true", timeout: 5)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testCommandRunnerStopsCancelledProcess() async throws {
        let startedAt = Date()
        let task = Task {
            try await CommandRunner().run(executable: "/bin/sleep", arguments: ["10"], timeout: 20)
        }

        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testStartupFailureClassifierRecognizesForcedUpdate() {
        let result = StartupFailureClassifier.diagnose(output: "Client version mismatch. Update required.", hasAccountSelector: false)
        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("更新游戏包体"))
    }

    func testStartupFailureClassifierRecognizesGameDataDownload() {
        let result = StartupFailureClassifier.diagnose(output: "执行超时：游戏仍在下载资源", hasAccountSelector: false)
        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("下载或解压更新数据"))
        XCTAssertTrue(result.guidance.contains("跳过该客户端"))
    }

    func testWorkflowReportRequiresAttentionIsNotSuccess() {
        XCTAssertFalse(WorkflowReport(attentionMessages: ["请手动更新游戏"]).isSuccess)
        XCTAssertFalse(WorkflowReport(cancelled: true).isSuccess)
    }

    @MainActor
    func testCompletedPlanIsNotLaunchedAgainToday() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let account = AccountConfiguration(name: "已完成账号")
        let client = ClientConfiguration(
            name: "应用路径故意不存在",
            kind: .official,
            appPath: "/Applications/Definitely-Missing-Completed-Game.app",
            profileName: "completed-client",
            accounts: [account]
        )
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let completedSteps = Set(plan.enabledTasks.map {
            "\(plan.id.uuidString)/\(client.id.uuidString)/\(account.id.uuidString)/\($0.rawValue)"
        })
        try ExecutionStateStore(directories: directories).save(
            ExecutionState(dateKey: ExecutionStateStore.todayKey, completedSteps: completedSteps)
        )

        let report = await WorkflowRunner(directories: directories).run(config, planID: plan.id)

        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(report.skippedSteps, plan.enabledTasks.count)
        XCTAssertTrue(report.attentionMessages.isEmpty)
    }

    @MainActor
    func testCheckpointsAreIsolatedBetweenPlans() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let account = AccountConfiguration(name: "账号")
        let client = ClientConfiguration(
            name: "缺失客户端",
            kind: .official,
            appPath: "/Applications/Definitely-Missing-Plan-Isolation.app",
            profileName: "plan-isolation",
            accounts: [account]
        )
        var light = AutomationPlan.lightRoutine
        var complete = AutomationPlan.completeRoutine
        light.policy.hotUpdateBeforeRun = false
        complete.policy.hotUpdateBeforeRun = false
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [light, complete])
        let completedSteps = Set(light.enabledTasks.map {
            "\(light.id.uuidString)/\(client.id.uuidString)/\(account.id.uuidString)/\($0.rawValue)"
        })
        try ExecutionStateStore(directories: directories).save(
            ExecutionState(dateKey: ExecutionStateStore.todayKey, completedSteps: completedSteps)
        )

        let report = await WorkflowRunner(directories: directories).run(config, planID: complete.id)

        XCTAssertEqual(report.attentionMessages.count, 1)
        XCTAssertEqual(report.skippedSteps, complete.enabledTasks.count)
    }

    @MainActor
    func testUnavailableClientDoesNotStopFollowingClients() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let config = AppConfiguration(
            cliPath: "/usr/bin/true",
            clients: [
                missingClient(name: "缺失客户端 1", path: "/Applications/Definitely-Missing-One.app", port: 65534),
                missingClient(name: "缺失客户端 2", path: "/Applications/Definitely-Missing-Two.app", port: 65533),
            ],
            plans: [plan]
        )

        let report = await WorkflowRunner(directories: AppDirectories(root: root)).run(config, planID: plan.id, resumeToday: false)

        XCTAssertNil(report.fatalError)
        XCTAssertEqual(report.attentionMessages.count, 2)
        XCTAssertEqual(report.skippedSteps, plan.enabledTasks.count * 2)
        XCTAssertEqual(report.failedSteps, 0)
    }

    @MainActor
    func testMissingCLIStopsBeforeOpeningClients() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let config = AppConfiguration(
            cliPath: "/Applications/Definitely-Missing-maa-cli",
            clients: [missingClient(name: "不应启动", path: "/Applications/Definitely-Missing-Game.app", port: 65534)],
            plans: [plan]
        )

        let report = await WorkflowRunner(directories: AppDirectories(root: root)).run(config, planID: plan.id, resumeToday: false)

        XCTAssertNotNil(report.fatalError)
        XCTAssertTrue(report.attentionMessages.isEmpty)
        XCTAssertEqual(report.skippedSteps, 0)
    }

    private func populatedConfiguration() -> AppConfiguration {
        AppConfiguration(clients: [
            ClientConfiguration(
                name: "测试客户端 1",
                kind: .official,
                appPath: "/Applications/GameOne.app",
                profileName: "client-1",
                accounts: [AccountConfiguration(name: "测试账号 1")]
            ),
            ClientConfiguration(
                name: "测试客户端 2",
                kind: .yoStarJP,
                appPath: "/Applications/GameTwo.app",
                profileName: "client-2",
                accounts: [AccountConfiguration(name: "测试账号 2")]
            ),
        ])
    }

    private func missingClient(name: String, path: String, port: Int) -> ClientConfiguration {
        ClientConfiguration(
            name: name,
            kind: .official,
            appPath: path,
            address: "localhost:\(port)",
            profileName: "missing-\(port)",
            bundleIdentifier: "dev.automaa.tests.missing-\(port)",
            accounts: [AccountConfiguration(name: "账号 \(port)")]
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "automaa-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func generatedParams(
        _ task: TaskKind,
        plan: AutomationPlan,
        client: ClientConfiguration,
        account: AccountConfiguration,
        writer: MAAConfigurationWriter,
        root: URL
    ) throws -> [String: Any] {
        let name = writer.taskName(planID: plan.id, clientID: client.id, accountID: account.id, task: task)
        let data = try Data(contentsOf: root.appending(path: "MAA/tasks/\(name).json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        return try XCTUnwrap(tasks.first?["params"] as? [String: Any])
    }
}
