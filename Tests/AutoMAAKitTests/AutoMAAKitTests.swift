import Foundation
import XCTest
@testable import AutoMAAKit

final class AutoMAAKitTests: XCTestCase {
    func testFirstLaunchStartsWithBlankWorkflow() {
        XCTAssertTrue(AppConfiguration.defaults.clients.isEmpty)
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
        XCTAssertEqual(FightStagePreset.lmd.title, "龙门币-6/5")
        XCTAssertEqual(FightStagePreset.battleRecord.title, "经验-6/5")
    }

    func testTaskSettingsUseOneExplicitConfigurationProtocol() throws {
        let data = try JSONEncoder().encode(FightConfiguration())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["settingsMode"] as? String, "custom")
        XCTAssertEqual(Set(json.keys), [
            "drGrandet", "enabled", "settingsMode", "stage",
        ])

        let incomplete = Data(#"{"enabled":true,"stage":"","drGrandet":false}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(FightConfiguration.self, from: incomplete))
    }

    func testGeneratedFightUsesMAAOptionalParameters() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.clients[0].accounts[0].fight.stage = FightStagePreset.annihilation.rawValue
        config.clients[0].accounts[0].fight.medicine = 3
        config.clients[0].accounts[0].fight.expiringMedicine = 999
        config.clients[0].accounts[0].fight.stone = 0
        config.clients[0].accounts[0].fight.times = 5
        config.clients[0].accounts[0].fight.series = nil
        config.clients[0].accounts[0].fight.drGrandet = true
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let client = config.clients[0]
        let account = client.accounts[0]
        let name = writer.taskName(clientID: client.id, accountID: account.id, task: .fight)
        let data = try Data(contentsOf: root.appending(path: "MAA/tasks/\(name).json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        let params = try XCTUnwrap(tasks.first?["params"] as? [String: Any])
        XCTAssertEqual(params["stage"] as? String, "Annihilation")
        XCTAssertEqual(params["medicine"] as? Int, 3)
        XCTAssertEqual(params["expiring_medicine"] as? Int, 999)
        XCTAssertEqual(params["stone"] as? Int, 0)
        XCTAssertEqual(params["times"] as? Int, 5)
        XCTAssertNil(params["series"])
        XCTAssertEqual(params["DrGrandet"] as? Bool, true)
        XCTAssertNil(params["medicine_expire_days"])
    }

    func testDisablingCustomSettingsUsesMAADefaultsWithoutErasingValues() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.clients[0].accounts[0].fight.stage = "1-7"
        config.clients[0].accounts[0].fight.medicine = 3
        config.clients[0].accounts[0].fight.usesCustomSettings = false
        config.clients[0].accounts[0].recruit.usesCustomSettings = false
        config.clients[0].accounts[0].infrast.usesCustomSettings = false
        config.clients[0].accounts[0].award.usesCustomSettings = false
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let client = config.clients[0]
        let account = client.accounts[0]
        let fight = try generatedParams(.fight, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(fight["stage"] as? String, "")
        XCTAssertNil(fight["medicine"])
        XCTAssertEqual(config.clients[0].accounts[0].fight.stage, "1-7")
        XCTAssertEqual(config.clients[0].accounts[0].fight.medicine, 3)

        let recruit = try generatedParams(.recruit, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(recruit["refresh"] as? Bool, false)
        XCTAssertEqual(recruit["confirm"] as? [Int], [3, 4, 5])
        XCTAssertEqual(recruit["times"] as? Int, 4)

        let infrast = try generatedParams(.infrast, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(infrast["mode"] as? Int, 0)
        XCTAssertEqual(infrast["drones"] as? String, "_NotUse")
        XCTAssertEqual((infrast["facility"] as? [String])?.count, 9)

        let award = try generatedParams(.award, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(award["award"] as? Bool, true)
        XCTAssertEqual(award["mail"] as? Bool, false)
        XCTAssertEqual(award["specialaccess"] as? Bool, false)
    }

    func testGeneratedInfrastUsesNoShiftModeAndSeparateProfiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let config = populatedConfiguration()
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let firstProfile = try String(contentsOf: root.appending(path: "MAA/profiles/client-1.toml"), encoding: .utf8)
        let secondProfile = try String(contentsOf: root.appending(path: "MAA/profiles/client-2.toml"), encoding: .utf8)
        XCTAssertTrue(firstProfile.contains("preset = \"PlayCover\""))
        XCTAssertFalse(firstProfile.contains("global_resource"))
        XCTAssertTrue(secondProfile.contains("global_resource = \"YoStarJP\""))

        let client = config.clients[0]
        let account = client.accounts[0]
        let name = writer.taskName(clientID: client.id, accountID: account.id, task: .infrast)
        let data = try Data(contentsOf: root.appending(path: "MAA/tasks/\(name).json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        let params = try XCTUnwrap(tasks.first?["params"] as? [String: Any])
        XCTAssertEqual(params["mode"] as? Int, 20_000)
        XCTAssertEqual(params["drones"] as? String, "Money")
        XCTAssertEqual(params["facility"] as? [String], ["Mfg", "Trade"])
    }

    func testRemovedConfigurationsCleanUpGeneratedFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let writer = MAAConfigurationWriter(directories: directories)
        var config = populatedConfiguration()
        let removedClient = config.clients[1]
        let removedTask = writer.taskName(
            clientID: removedClient.id,
            accountID: removedClient.accounts[0].id,
            task: .award
        )
        try writer.prepare(config)

        config.clients.removeLast()
        try writer.prepare(config)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "MAA/profiles/client-2.toml").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "MAA/tasks/\(removedTask).json").path))
    }

    func testOrphanedAutoMAATasksAreCleanedWithoutManifestEntry() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let orphanName = "\(UUID().uuidString.lowercased())-\(UUID().uuidString.lowercased())-fight.json"
        let orphan = directories.maaConfig.appending(path: "tasks/\(orphanName)")
        try Data("{}".utf8).write(to: orphan)

        try MAAConfigurationWriter(directories: directories).prepare(.defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testConfigurationRoundTrip() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(directories: AppDirectories(root: root))
        var config = populatedConfiguration()
        config.clients[0].accounts[0].accountSelector = "unique-fragment"
        config.clients[0].accounts[0].infrast.drones = .combatRecord

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testMismatchedSchemaResetsToBlankWorkflow() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let mismatched: [String: Any] = [
            "schemaVersion": AppConfiguration.currentSchemaVersion - 1,
            "cliPath": "/opt/homebrew/bin/maa",
            "clients": [[
                "id": UUID().uuidString,
                "name": "旧占位客户端",
                "kind": "official",
                "appPath": "/Applications/Placeholder.app",
                "address": "localhost:1717",
                "profileName": "old-schema",
                "enabled": true,
                "accounts": [],
            ]],
            "schedule": [
                "enabled": false,
                "hour": 8,
                "minute": 0,
                "hotUpdateBeforeRun": true,
                "maxRetries": 1,
                "continueAfterStepFailure": true,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: mismatched)
        try data.write(to: directories.configuration)

        let reset = try ConfigurationStore(directories: directories).load()

        XCTAssertEqual(reset.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertTrue(reset.clients.isEmpty)
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
        let result = try await CommandRunner().run(
            executable: "/usr/bin/true",
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testCommandRunnerStopsCancelledProcess() async throws {
        let startedAt = Date()
        let task = Task {
            try await CommandRunner().run(
                executable: "/bin/sleep",
                arguments: ["10"],
                timeout: 20
            )
        }

        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
    }

    func testStartupFailureClassifierRecognizesForcedUpdate() {
        let result = StartupFailureClassifier.diagnose(
            output: "Client version mismatch. Update required.",
            hasAccountSelector: false
        )

        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("更新游戏包体"))
    }

    func testStartupFailureClassifierRecognizesGameDataDownload() {
        let result = StartupFailureClassifier.diagnose(
            output: "执行超时：游戏仍在下载资源",
            hasAccountSelector: false
        )

        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("下载或解压更新数据"))
        XCTAssertTrue(result.guidance.contains("跳过该客户端"))
    }

    func testStartupFailureClassifierKeepsAccountMismatchLocal() {
        let result = StartupFailureClassifier.diagnose(
            output: "No matching account name was found",
            hasAccountSelector: true
        )

        XCTAssertEqual(result.scope, .account)
        XCTAssertTrue(result.guidance.contains("其他账号仍会继续"))
    }

    func testStartupFailureClassifierRecognizesNetworkFailure() {
        let result = StartupFailureClassifier.diagnose(
            output: "执行超时：Network error: failed to lookup address information",
            hasAccountSelector: false
        )

        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("网络"))
    }

    func testWorkflowReportRequiresAttentionIsNotSuccess() {
        let report = WorkflowReport(attentionMessages: ["请手动更新游戏"])
        XCTAssertFalse(report.isSuccess)
    }

    func testCancelledWorkflowReportIsNotSuccess() {
        XCTAssertFalse(WorkflowReport(cancelled: true).isSuccess)
    }

    @MainActor
    func testCompletedClientIsNotLaunchedAgainToday() async throws {
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
        var schedule = ScheduleConfiguration()
        schedule.hotUpdateBeforeRun = false
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], schedule: schedule)
        let completedSteps = Set(TaskKind.allCases.map {
            "\(client.id.uuidString)/\(account.id.uuidString)/\($0.rawValue)"
        })
        try ExecutionStateStore(directories: directories).save(
            ExecutionState(dateKey: ExecutionStateStore.todayKey, completedSteps: completedSteps)
        )

        let report = await WorkflowRunner(directories: directories).run(config)

        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(report.skippedSteps, TaskKind.allCases.count)
        XCTAssertTrue(report.attentionMessages.isEmpty)
        XCTAssertNil(report.fatalError)
    }

    @MainActor
    func testUnavailableClientDoesNotStopFollowingClients() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var schedule = ScheduleConfiguration()
        schedule.hotUpdateBeforeRun = false
        let config = AppConfiguration(
            cliPath: "/usr/bin/true",
            clients: [
                ClientConfiguration(
                    name: "缺失客户端 1",
                    kind: .official,
                    appPath: "/Applications/Definitely-Missing-One.app",
                    address: "localhost:65534",
                    profileName: "missing-1",
                    bundleIdentifier: "dev.automaa.tests.missing-one",
                    accounts: [AccountConfiguration(name: "账号 1")]
                ),
                ClientConfiguration(
                    name: "缺失客户端 2",
                    kind: .yoStarJP,
                    appPath: "/Applications/Definitely-Missing-Two.app",
                    address: "localhost:65533",
                    profileName: "missing-2",
                    bundleIdentifier: "dev.automaa.tests.missing-two",
                    accounts: [AccountConfiguration(name: "账号 2")]
                ),
            ],
            schedule: schedule
        )

        let report = await WorkflowRunner(directories: AppDirectories(root: root)).run(
            config,
            resumeToday: false
        )

        XCTAssertNil(report.fatalError)
        XCTAssertEqual(report.attentionMessages.count, 2)
        XCTAssertEqual(report.skippedSteps, 8)
        XCTAssertEqual(report.failedSteps, 0)
    }

    @MainActor
    func testMissingCLIStopsBeforeOpeningClients() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var schedule = ScheduleConfiguration()
        schedule.hotUpdateBeforeRun = false
        let config = AppConfiguration(
            cliPath: "/Applications/Definitely-Missing-maa-cli",
            clients: [
                ClientConfiguration(
                    name: "不应启动",
                    kind: .official,
                    appPath: "/Applications/Definitely-Missing-Game.app",
                    profileName: "missing-cli",
                    accounts: [AccountConfiguration(name: "账号")]
                ),
            ],
            schedule: schedule
        )

        let report = await WorkflowRunner(directories: AppDirectories(root: root)).run(
            config,
            resumeToday: false
        )

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

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "automaa-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func generatedParams(
        _ task: TaskKind,
        client: ClientConfiguration,
        account: AccountConfiguration,
        writer: MAAConfigurationWriter,
        root: URL
    ) throws -> [String: Any] {
        let name = writer.taskName(clientID: client.id, accountID: account.id, task: task)
        let data = try Data(contentsOf: root.appending(path: "MAA/tasks/\(name).json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        return try XCTUnwrap(tasks.first?["params"] as? [String: Any])
    }
}
