import Foundation
import XCTest
@testable import AutoMAAKit

private extension ClientShutdownPolicy {
    static let immediate = ClientShutdownPolicy(
        maaGracePeriod: 0,
        systemGracePeriod: 0,
        forcedGracePeriod: 0
    )
}

@MainActor
private final class StubClientRuntime: PortProbing, GameProcessControlling {
    var isClientRunning = true
    var isPortOpen = true
    let closesOnForce: Bool
    let opensOnWait: Bool
    var runningClientIDs: Set<UUID>?
    private(set) var terminationRequests: [Bool] = []
    private(set) var events: [RunnerEvent] = []

    init(
        closesOnForce: Bool,
        opensOnWait: Bool = false,
        runningClientIDs: Set<UUID>? = nil
    ) {
        self.closesOnForce = closesOnForce
        self.opensOnWait = opensOnWait
        self.runningClientIDs = runningClientIDs
    }

    func isOpen(_ value: String, observeCancellation: Bool) async -> Bool {
        isPortOpen
    }

    func wait(
        forOpen shouldBeOpen: Bool,
        address: String,
        timeout: TimeInterval,
        observeCancellation: Bool
    ) async -> Bool {
        if shouldBeOpen, opensOnWait, !isPortOpen {
            isClientRunning = true
            isPortOpen = true
        }
        return isPortOpen == shouldBeOpen
    }

    func isRunning(_ client: ClientConfiguration) -> Bool {
        runningClientIDs?.contains(client.id) ?? isClientRunning
    }

    func terminate(_ client: ClientConfiguration, force: Bool) -> Bool {
        terminationRequests.append(force)
        if force, closesOnForce {
            isClientRunning = false
            runningClientIDs?.remove(client.id)
            isPortOpen = false
        }
        return true
    }

    func record(_ event: RunnerEvent) {
        events.append(event)
    }
}

final class AutoMAAKitTests: XCTestCase {
    func testFirstLaunchUsesBlankIdentitiesAndTwoEditableRoutineTemplates() {
        let config = AppConfiguration.defaults

        XCTAssertTrue(config.clients.isEmpty)
        XCTAssertEqual(config.plans.count, 2)
        XCTAssertEqual(config.plans[0].name, "轻量日常")
        XCTAssertEqual(config.plans[0].infrast.mode, .collectOnly)
        XCTAssertFalse(config.plans[0].mall.enabled)
        XCTAssertEqual(config.plans[0].schedule.rules.count, 1)
        XCTAssertEqual(config.plans[0].schedule.rules[0].weekdays, ScheduleWeekday.everyDay)
        XCTAssertEqual(config.plans[0].schedule.rules[0].hour, 9)
        XCTAssertEqual(config.plans[0].schedule.rules[0].minute, 0)
        XCTAssertEqual(config.plans[1].name, "完整日常")
        XCTAssertEqual(config.plans[1].infrast.mode, .fullShift)
        XCTAssertEqual(config.plans[1].infrast.threshold, 0.9)
        XCTAssertTrue(config.plans[1].mall.enabled)
        XCTAssertEqual(config.plans[1].schedule.rules.count, 1)
        XCTAssertEqual(config.plans[1].schedule.rules[0].weekdays, ScheduleWeekday.everyDay)
        XCTAssertEqual(config.plans[1].schedule.rules[0].hour, 21)
        XCTAssertEqual(config.plans[1].schedule.rules[0].minute, 0)
        XCTAssertFalse(config.notifications.importantEventsEnabled)
        XCTAssertFalse(config.applicationUpdates.automaticallyDownloadsUpdates)
        XCTAssertFalse(config.maaUpdates.automaticallyUpdatesCoreAndResources)
    }

    func testWeeklyScheduleSummaryAndNextRunAreDeterministic() throws {
        let schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(weekdays: ScheduleWeekday.weekdays, hour: 9),
            WeeklyScheduleRule(weekdays: ScheduleWeekday.weekend, hour: 21),
        ])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let mondayAtNoon = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2024,
            month: 1,
            day: 1,
            hour: 12
        )))

        XCTAssertEqual(PlanScheduleFormatter.summary(schedule), "工作日 09:00；周末 21:00")
        XCTAssertEqual(
            PlanScheduleFormatter.nextRunLabel(schedule, after: mondayAtNoon, calendar: calendar),
            "周二 09:00"
        )
        XCTAssertEqual(
            PlanScheduleFormatter.nextRunDate(schedule, after: mondayAtNoon, calendar: calendar),
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 9))
        )
    }

    func testCurrentConfigurationRequiresNotificationSettings() throws {
        let data = try JSONEncoder().encode(populatedConfiguration())
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "notifications")

        let invalidData = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfiguration.self, from: invalidData))
    }

    func testCurrentConfigurationRequiresApplicationUpdateSettings() throws {
        var config = populatedConfiguration()
        config.applicationUpdates.automaticallyDownloadsUpdates = true
        let data = try JSONEncoder().encode(config)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "applicationUpdates")

        let invalidData = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfiguration.self, from: invalidData))
    }

    func testCurrentConfigurationDefaultsMissingMAAUpdateSettingsToDisabled() throws {
        var config = populatedConfiguration()
        config.maaUpdates.automaticallyUpdatesCoreAndResources = true
        let data = try JSONEncoder().encode(config)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "maaUpdates")

        let compatibleData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: compatibleData)

        XCTAssertEqual(decoded.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertFalse(decoded.maaUpdates.automaticallyUpdatesCoreAndResources)
    }

    func testAutomaticMAAUpdatePolicyThrottlesAndProtectsUpcomingSchedules() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(AutomaticMAAUpdatePolicy.canStart(
            enabled: true,
            lastAttempt: nil,
            nextScheduledRun: nil,
            now: now
        ))
        XCTAssertFalse(AutomaticMAAUpdatePolicy.canStart(
            enabled: false,
            lastAttempt: nil,
            nextScheduledRun: nil,
            now: now
        ))
        XCTAssertFalse(AutomaticMAAUpdatePolicy.canStart(
            enabled: true,
            lastAttempt: now.addingTimeInterval(-60 * 60),
            nextScheduledRun: nil,
            now: now
        ))
        XCTAssertFalse(AutomaticMAAUpdatePolicy.canStart(
            enabled: true,
            lastAttempt: nil,
            nextScheduledRun: now.addingTimeInterval(60 * 60),
            now: now
        ))
        XCTAssertTrue(AutomaticMAAUpdatePolicy.canStart(
            enabled: true,
            lastAttempt: now.addingTimeInterval(-AutomaticMAAUpdatePolicy.checkInterval),
            nextScheduledRun: now.addingTimeInterval(2 * 60 * 60),
            now: now
        ))
    }

    func testMAAMaintenanceStoreRoundTripsInIsolatedDirectory() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MAAMaintenanceStore(directories: AppDirectories(root: root))
        let state = MAAMaintenanceState(lastCoreUpdateAttempt: Date(timeIntervalSince1970: 1_700_000_000))

        try store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testDisplayNamesTrimWhitespaceAndProvideContextualFallbacks() {
        let account = AccountConfiguration(name: "  主账号  ")
        let unnamedAccount = AccountConfiguration(name: " \n ")
        let client = ClientConfiguration(
            name: "  工作日官服  ",
            kind: .official,
            appPath: "",
            profileName: "test",
            accounts: []
        )
        let unnamedClient = ClientConfiguration(
            name: "",
            kind: .yoStarJP,
            appPath: "",
            profileName: "test-jp",
            accounts: []
        )
        let plan = AutomationPlan(name: "  睡前日常  ")
        let unnamedPlan = AutomationPlan(name: "")

        XCTAssertEqual(account.displayName, "主账号")
        XCTAssertEqual(unnamedAccount.displayName, "未命名账号")
        XCTAssertEqual(client.displayName, "工作日官服")
        XCTAssertEqual(unnamedClient.displayName, "日服")
        XCTAssertEqual(plan.displayName, "睡前日常")
        XCTAssertEqual(unnamedPlan.displayName, "未命名方案")
    }

    func testRenamingKeepsStableIdentifiersAndPlanMembership() throws {
        let accountID = UUID()
        let clientID = UUID()
        let planID = UUID()
        let account = AccountConfiguration(id: accountID, name: "旧账号")
        let client = ClientConfiguration(
            id: clientID,
            name: "旧客户端",
            kind: .official,
            appPath: "",
            profileName: "test",
            accounts: [account]
        )
        var plan = AutomationPlan(
            id: planID,
            name: "旧方案",
            includesAllEnabledAccounts: false,
            accountIDs: [accountID]
        )
        var configuration = AppConfiguration(clients: [client], plans: [plan])

        configuration.clients[0].name = "工作日官服"
        configuration.clients[0].accounts[0].name = "主账号"
        configuration.plans[0].name = "睡前日常"
        plan = configuration.plans[0]

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.clients[0].id, clientID)
        XCTAssertEqual(decoded.clients[0].accounts[0].id, accountID)
        XCTAssertEqual(decoded.plans[0].id, planID)
        XCTAssertTrue(decoded.plans[0].includes(decoded.clients[0].accounts[0]))
        XCTAssertEqual(decoded.clients[0].displayName, "工作日官服")
        XCTAssertEqual(decoded.clients[0].accounts[0].displayName, "主账号")
        XCTAssertEqual(decoded.plans[0].displayName, "睡前日常")
    }

    func testSupportedClientMappings() {
        XCTAssertEqual(ClientKind.allCases.map(\.title), [
            "简中服 · 官服", "简中服 · Bilibili", "繁中服", "国际服", "日服", "韩服",
        ])
        XCTAssertEqual(ClientKind.allCases.map(\.maaClientType), [
            "Official", "Bilibili", "Txwy", "YoStarEN", "YoStarJP", "YoStarKR",
        ])
        XCTAssertEqual(ClientKind.allCases.map(\.supportsAccountSwitching), [
            true, true, true, false, false, true,
        ])
        XCTAssertEqual(ClientKind.txwy.maaTaskClientType, "txwy")
        XCTAssertEqual(ClientKind.yoStarEN.serverCode, "US")
        XCTAssertEqual(ClientKind.official.maaAccountSelector(from: " 1234 "), "1234")
        XCTAssertEqual(ClientKind.yoStarKR.maaAccountSelector(from: " 01@gmail "), "01@gmail")
        XCTAssertNil(ClientKind.yoStarJP.maaAccountSelector(from: "private-fragment"))
    }

    @MainActor
    func testGameProcessMatchingFollowsPlayCoverExecutableSymlinks() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let actualBundle = root.appending(path: "Applications/dev.automaa.tests.game.app", directoryHint: .isDirectory)
        let linkedBundle = root.appending(path: "Games/Test Game.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: actualBundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedBundle, withIntermediateDirectories: true)

        let executable = actualBundle.appending(path: "TestGame")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        let info: [String: Any] = [
            "CFBundleExecutable": "TestGame",
            "CFBundleIdentifier": "dev.automaa.tests.game",
            "CFBundlePackageType": "APPL",
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: actualBundle.appending(path: "Info.plist"))
        try FileManager.default.createSymbolicLink(
            at: linkedBundle.appending(path: "Info.plist"),
            withDestinationURL: actualBundle.appending(path: "Info.plist")
        )
        try FileManager.default.createSymbolicLink(
            at: linkedBundle.appending(path: "TestGame"),
            withDestinationURL: executable
        )

        let client = ClientConfiguration(
            name: "测试客户端",
            kind: .official,
            appPath: linkedBundle.path,
            profileName: "test",
            bundleIdentifier: "dev.automaa.tests.game",
            accounts: [AccountConfiguration(name: "测试账号")]
        )

        XCTAssertTrue(GameProcessController.matchesApplication(
            client,
            bundleURL: actualBundle,
            executableURL: executable
        ))
        XCTAssertFalse(GameProcessController.matchesApplication(
            client,
            bundleURL: root.appending(path: "Applications/other.app"),
            executableURL: root.appending(path: "Applications/other.app/Other")
        ))
    }

    @MainActor
    func testConfirmedFallbackShutdownIsReportedAsSuccess() async throws {
        let (report, runtime) = try await runShutdownScenario(
            closesOnForce: true,
            address: "127.0.0.1:65490",
            clientName: "测试客户端"
        )

        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(runtime.terminationRequests, [false, true])
        let closingEvents = runtime.events.filter { $0.phase == .closing }
        let completion = try XCTUnwrap(closingEvents.last)
        XCTAssertEqual(completion.log.level, .success)
        XCTAssertEqual(completion.message, "客户端「测试客户端」已关闭，MaaTools 连接已释放")
        XCTAssertEqual(completion.log.details, "客户端未响应常规退出请求，已由 macOS 完成进程清理。")
        XCTAssertFalse(closingEvents.contains { $0.log.level == .warning })
    }

    @MainActor
    func testSharedPortOwnedByAnotherConfiguredClientStopsWithoutClosingEitherClient() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let officialApp = root.appending(path: "Applications/Official.app", directoryHint: .isDirectory)
        let japaneseApp = root.appending(path: "Applications/Japanese.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: officialApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: japaneseApp, withIntermediateDirectories: true)
        let address = "127.0.0.1:65492"
        let official = ClientConfiguration(
            name: "官服测试",
            kind: .official,
            appPath: officialApp.path,
            address: address,
            profileName: "official-conflict-test",
            bundleIdentifier: "dev.automaa.tests.official-conflict",
            accounts: [AccountConfiguration(name: "官服账号")]
        )
        let japanese = ClientConfiguration(
            name: "日服测试",
            kind: .yoStarJP,
            appPath: japaneseApp.path,
            address: address,
            profileName: "japanese-conflict-test",
            bundleIdentifier: "dev.automaa.tests.japanese-conflict",
            accounts: [AccountConfiguration(name: "日服账号")]
        )
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let configuration = AppConfiguration(
            cliPath: "/usr/bin/true",
            clients: [official, japanese],
            plans: [plan]
        )
        let runtime = StubClientRuntime(
            closesOnForce: true,
            runningClientIDs: [official.id, japanese.id]
        )
        let runner = WorkflowRunner(
            directories: AppDirectories(root: root),
            portProbe: runtime,
            gameController: runtime,
            shutdownPolicy: .immediate,
            eventSink: runtime.record
        )

        let report = await runner.run(configuration, planID: plan.id, resumeToday: false)

        let message = "客户端「日服测试」仍在运行并占用 MaaTools 端口 \(address)。为避免连接错误客户端，请关闭该客户端及其他 MAA 后重新运行"
        XCTAssertEqual(report.fatalError, message)
        XCTAssertEqual(report.succeededSteps, 0)
        XCTAssertTrue(runtime.terminationRequests.isEmpty)
        XCTAssertTrue(runtime.events.contains {
            $0.phase == .failed && $0.message == message && $0.log.level == .error
        })
    }

    func testUnknownPortOwnerProvidesActionableSafetyGuidance() {
        XCTAssertEqual(
            RuntimeError.portOccupied("127.0.0.1:65493").localizedDescription,
            "MaaTools 端口 127.0.0.1:65493 已被未知程序占用。为避免连接错误客户端，请关闭相关游戏和 MAA 后重新运行"
        )
    }

    @MainActor
    func testShutdownStillFailsWhenProcessOrPortCannotBeReleased() async throws {
        let (report, runtime) = try await runShutdownScenario(
            closesOnForce: false,
            address: "127.0.0.1:65491",
            clientName: "无法关闭的客户端"
        )

        XCTAssertEqual(runtime.terminationRequests, [false, true])
        XCTAssertEqual(report.fatalError, "客户端关闭后端口 127.0.0.1:65491 仍未释放")
        XCTAssertTrue(runtime.events.contains { $0.phase == .failed && $0.log.level == .error })
    }

    @MainActor
    private func runShutdownScenario(
        closesOnForce: Bool,
        address: String,
        clientName: String
    ) async throws -> (WorkflowReport, StubClientRuntime) {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Applications/Test Game.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(
            name: clientName,
            kind: .official,
            appPath: app.path,
            address: address,
            profileName: "shutdown-test",
            bundleIdentifier: "dev.automaa.tests.shutdown",
            accounts: [account]
        )
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let runtime = StubClientRuntime(closesOnForce: closesOnForce)
        let runner = WorkflowRunner(
            directories: AppDirectories(root: root),
            portProbe: runtime,
            gameController: runtime,
            shutdownPolicy: .immediate,
            eventSink: runtime.record
        )

        let report = await runner.run(configuration, planID: plan.id, resumeToday: false)
        return (report, runtime)
    }

    func testFightStagePresetsMatchCurrentMAANavigationProtocol() {
        XCTAssertEqual(FightStagePreset.allCases.map(\.rawValue), [
            "", "1-7", "CE-6", "LS-6", "AP-5", "CA-5", "SK-5", "Annihilation",
            "Chernobog@Annihilation", "LungmenOutskirts@Annihilation",
            "LungmenDowntown@Annihilation", "OF-1", "OF-F3",
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
        config.plans[0].fight.medicineExpireDays = 2
        config.plans[0].fight.stone = 0
        config.plans[0].fight.times = 5
        config.plans[0].fight.drGrandet = true
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let params = try generatedParams(.fight, plan: config.plans[0], client: config.clients[0], account: config.clients[0].accounts[0], writer: writer, root: root)
        XCTAssertEqual(params["stage"] as? String, "Annihilation")
        XCTAssertEqual(params["medicine"] as? Int, 3)
        XCTAssertEqual(params["medicine_expire_days"] as? Int, 2)
        XCTAssertNil(params["expiring_medicine"])
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
        XCTAssertNil(fight["stage"])
        XCTAssertNil(fight["medicine"])
        XCTAssertEqual(config.plans[0].fight.stage, "1-7")
        XCTAssertEqual(config.plans[0].fight.medicine, 3)

        let infrast = try generatedParams(.infrast, plan: plan, client: client, account: account, writer: writer, root: root)
        XCTAssertEqual(infrast["mode"] as? Int, 0)
        XCTAssertEqual((infrast["facility"] as? [String])?.count, 9)
        XCTAssertEqual(infrast["threshold"] as? Double, 0.3)

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
        XCTAssertEqual(complete["threshold"] as? Double, 0.9)
    }

    func testLowFullShiftThresholdProducesNonBlockingFatigueWarning() {
        var config = populatedConfiguration()
        config.plans[1].infrast.threshold = 0.3

        let problems = ConfigurationValidator.structuralProblems(in: config)
        let warning = problems.first { $0.id.contains("threshold-fatigue-risk") }

        XCTAssertEqual(warning?.severity, .warning)
        XCTAssertTrue(warning?.message.contains("上岗最低心情为 30%") == true)
        XCTAssertFalse(problems.contains { $0.severity == .error && $0.id.contains("threshold") })

        config.plans[1].infrast.threshold = 0.9
        XCTAssertFalse(ConfigurationValidator.structuralProblems(in: config).contains {
            $0.id.contains("threshold-fatigue-risk")
        })
    }

    func testReadinessOmitsWarningsFromOtherPlansButKeepsTheirStructuralErrors() {
        var config = populatedConfiguration()
        let selectedPlanID = config.plans[0].id
        let otherPlanID = config.plans[1].id
        config.plans[1].infrast.threshold = 0.3

        var problems = ConfigurationValidator.readinessProblems(in: config, planID: selectedPlanID)

        XCTAssertFalse(problems.contains { $0.id.contains("threshold-fatigue-risk") })

        config.plans[1].infrast.threshold = -0.1
        problems = ConfigurationValidator.readinessProblems(in: config, planID: selectedPlanID)
        let blocker = problems.first { $0.id.contains("infrast-threshold") }

        XCTAssertEqual(blocker?.severity, .error)
        XCTAssertEqual(blocker?.scope, .plan(otherPlanID))
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

    func testRecruitUsesCurrentPreserveTagsProtocol() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.plans[0].recruit.firstTags = ["高级资深干员"]
        config.plans[0].recruit.extraTagsMode = .moreHighRarity
        config.plans[0].recruit.preserveTags = ["支援机械", "资深干员"]
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let params = try generatedParams(
            .recruit,
            plan: config.plans[0],
            client: config.clients[0],
            account: config.clients[0].accounts[0],
            writer: writer,
            root: root
        )
        XCTAssertEqual(params["first_tags"] as? [String], ["高级资深干员"])
        XCTAssertEqual(params["extra_tags_mode"] as? Int, 2)
        XCTAssertEqual(params["preserve_tags"] as? [String], ["支援机械", "资深干员"])
        XCTAssertNil(params["skip_robot"])
    }

    func testCustomInfrastScheduleUsesModeAndFile() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        var config = populatedConfiguration()
        config.plans[0].infrast.mode = .customSchedule
        config.plans[0].infrast.customSchedulePath = "/tmp/automaa-test-schedule.json"
        config.plans[0].infrast.customSchedulePlanIndex = 3
        let writer = MAAConfigurationWriter(directories: directories)

        try writer.prepare(config)

        let params = try generatedParams(
            .infrast,
            plan: config.plans[0],
            client: config.clients[0],
            account: config.clients[0].accounts[0],
            writer: writer,
            root: root
        )
        XCTAssertEqual(params["mode"] as? Int, 10_000)
        XCTAssertEqual(params["filename"] as? String, "/tmp/automaa-test-schedule.json")
        XCTAssertEqual(params["plan_index"] as? Int, 3)
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

    func testLaunchAgentTargetsExactlyOnePlanAndWeeklySchedule() throws {
        let root = temporaryRoot()
        var plan = AutomationPlan.completeRoutine
        plan.schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(weekdays: [.monday, .saturday], hour: 9, minute: 15),
            WeeklyScheduleRule(weekdays: [.sunday], hour: 21, minute: 35),
        ])
        let manager = LaunchAgentManager(directories: AppDirectories(root: root))
        let runnerURL = URL(filePath: "/Applications/AutoMAA.app/Contents/MacOS/AutoMAARunner")

        let payload = manager.propertyList(runnerURL: runnerURL, plan: plan)

        XCTAssertEqual(payload["Label"] as? String, manager.label(planID: plan.id))
        XCTAssertEqual(payload["ProgramArguments"] as? [String], [
            runnerURL.path, "--plan", plan.id.uuidString.lowercased(),
        ])
        XCTAssertEqual(
            payload["EnvironmentVariables"] as? [String: String],
            ["AUTOMAA_RUNNER_IDENTITY": "development"]
        )
        let intervals = try XCTUnwrap(payload["StartCalendarInterval"] as? [[String: Int]])
        XCTAssertEqual(intervals, [
            ["Weekday": 1, "Hour": 9, "Minute": 15],
            ["Weekday": 6, "Hour": 9, "Minute": 15],
            ["Weekday": 0, "Hour": 21, "Minute": 35],
        ])
    }

    func testLaunchAgentInspectionUsesInjectedDirectory() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        var plan = AutomationPlan.lightRoutine
        plan.schedule = PlanSchedule(enabled: true, hour: 8, minute: 15)
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents
        )
        let runnerURL = root.appending(path: "AutoMAARunner")
        let data = try PropertyListSerialization.data(
            fromPropertyList: manager.propertyList(runnerURL: runnerURL, plan: plan),
            format: .xml,
            options: 0
        )
        try data.write(to: manager.plistURL(planID: plan.id), options: .atomic)

        XCTAssertEqual(manager.installedPlanIDs, Set([plan.id]))
        XCTAssertTrue(manager.isCurrent(runnerURL: runnerURL, plan: plan))
        XCTAssertFalse(manager.isCurrent(runnerURL: root.appending(path: "MovedRunner"), plan: plan))
        plan.schedule.rules[0].minute = 16
        XCTAssertFalse(manager.isCurrent(runnerURL: runnerURL, plan: plan))
    }

    func testLaunchAgentSynchronizationRejectsDuplicateTimesBeforeWritingFiles() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var light = AutomationPlan.lightRoutine
        light.schedule.enabled = true
        var complete = AutomationPlan.completeRoutine
        complete.schedule = light.schedule
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false
        )

        do {
            try await manager.synchronize(
                runnerURL: root.appending(path: "AutoMAARunner"),
                plans: [light, complete]
            )
            XCTFail("Expected duplicate schedule rejection")
        } catch let error as LaunchAgentError {
            XCTAssertEqual(error, .duplicateSchedule(
                first: "轻量日常",
                second: "完整日常",
                slot: WeeklyScheduleSlot(weekday: .monday, hour: 9, minute: 0)
            ))
        }
        XCTAssertTrue(manager.installedPlanIDs.isEmpty)
    }

    func testLaunchAgentAllowsSameTimeOnDifferentWeekdays() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var light = AutomationPlan.lightRoutine
        light.schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(weekdays: [.monday], hour: 9),
        ])
        var complete = AutomationPlan.completeRoutine
        complete.schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(weekdays: [.sunday], hour: 9),
        ])
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false
        )

        try await manager.synchronize(
            runnerURL: root.appending(path: "AutoMAARunner"),
            plans: [light, complete]
        )

        XCTAssertEqual(manager.installedPlanIDs, Set([light.id, complete.id]))
    }

    func testWeeklyOrchestrationDryRunCreatesOnlyExpectedTemporaryAgents() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var routine = AutomationPlan.completeRoutine
        routine.name = "正常计划"
        routine.schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
                hour: 9
            ),
            WeeklyScheduleRule(weekdays: [.sunday], hour: 21),
        ])
        var annihilation = AutomationPlan.lightRoutine
        annihilation.name = "周日剿灭"
        annihilation.fight.stage = FightStagePreset.annihilation.rawValue
        annihilation.schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(weekdays: [.sunday], hour: 9),
        ])
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false
        )

        try await manager.synchronize(
            runnerURL: URL(filePath: "/usr/bin/true"),
            plans: [routine, annihilation]
        )

        XCTAssertEqual(manager.installedPlanIDs, Set([routine.id, annihilation.id]))
        XCTAssertEqual(manager.installedSlots(planID: routine.id), Set(routine.schedule.slots))
        XCTAssertEqual(manager.installedSlots(planID: annihilation.id), Set(annihilation.schedule.slots))
        XCTAssertEqual(annihilation.fight.stage, "Annihilation")
        let files = try FileManager.default.contentsOfDirectory(at: launchAgents, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        let resolvedDirectory = launchAgents.resolvingSymlinksInPath().standardizedFileURL
        XCTAssertTrue(files.allSatisfy {
            $0.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == resolvedDirectory
        })
    }

    func testLaunchAgentRejectsMultipleTimesForOnePlanOnSameWeekday() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var plan = AutomationPlan.lightRoutine
        plan.schedule = PlanSchedule(enabled: true, rules: [
            WeeklyScheduleRule(weekdays: [.sunday], hour: 9),
            WeeklyScheduleRule(weekdays: [.sunday], hour: 21),
        ])
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false
        )

        do {
            try await manager.synchronize(
                runnerURL: root.appending(path: "AutoMAARunner"),
                plans: [plan]
            )
            XCTFail("Expected repeated weekday rejection")
        } catch {
            XCTAssertEqual(
                error as? LaunchAgentError,
                .invalidSchedule(plan: "轻量日常", problem: .repeatedWeekday(.sunday))
            )
        }
        XCTAssertTrue(manager.installedPlanIDs.isEmpty)
    }

    func testLaunchAgentSynchronizationCanRunWithoutSystemIntegration() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var plan = AutomationPlan.lightRoutine
        plan.schedule.enabled = true
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false
        )
        let runnerURL = root.appending(path: "AutoMAARunner")

        try await manager.synchronize(runnerURL: runnerURL, plans: [plan])
        XCTAssertTrue(manager.isInstalled(planID: plan.id))

        plan.schedule.enabled = false
        try await manager.synchronize(runnerURL: runnerURL, plans: [plan])
        XCTAssertFalse(manager.isInstalled(planID: plan.id))
    }

    func testSystemLaunchAgentRejectsRunnerInTemporaryDirectoryBeforeWritingFiles() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var plan = AutomationPlan.lightRoutine
        plan.schedule.enabled = true
        let manager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: true
        )
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let existingData = Data("existing production schedule".utf8)
        try existingData.write(to: manager.plistURL(planID: plan.id))
        let runnerURL = FileManager.default.temporaryDirectory
            .appending(path: "automaa-qa-\(UUID().uuidString)/AutoMAA.app/Contents/MacOS/AutoMAARunner")

        do {
            try await manager.synchronize(runnerURL: runnerURL, plans: [plan])
            XCTFail("Expected transient runner rejection")
        } catch {
            XCTAssertEqual(error as? LaunchAgentError, .transientRunner)
        }
        XCTAssertEqual(try Data(contentsOf: manager.plistURL(planID: plan.id)), existingData)
    }

    func testLaunchAgentRunnerIdentityChangeInvalidatesInstalledSchedule() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let launchAgents = root.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        var plan = AutomationPlan.lightRoutine
        plan.schedule.enabled = true
        let runnerURL = root.appending(path: "AutoMAARunner")
        let oldManager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false,
            runnerIdentity: "0.7.4-build-1"
        )

        try await oldManager.synchronize(runnerURL: runnerURL, plans: [plan])

        let updatedManager = LaunchAgentManager(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: launchAgents,
            systemIntegrationEnabled: false,
            runnerIdentity: "0.7.5-build-2"
        )
        XCTAssertFalse(updatedManager.isCurrent(runnerURL: runnerURL, plan: plan))

        try await updatedManager.synchronize(runnerURL: runnerURL, plans: [plan])

        XCTAssertTrue(updatedManager.isCurrent(runnerURL: runnerURL, plan: plan))
    }

    func testGeneratedTasksSelectServerResources() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = populatedConfiguration()
        let writer = MAAConfigurationWriter(directories: AppDirectories(root: root))

        try writer.prepare(config)

        let first = try String(contentsOf: root.appending(path: "MAA/profiles/client-1.toml"), encoding: .utf8)
        let second = try String(contentsOf: root.appending(path: "MAA/profiles/client-2.toml"), encoding: .utf8)
        XCTAssertTrue(first.contains("preset = \"PlayCover\""))
        XCTAssertFalse(first.contains("global_resource"))
        XCTAssertFalse(second.contains("global_resource"))

        for (client, expectedClientType) in zip(config.clients, ["Official", "YoStarJP"]) {
            for plan in config.plans {
                for account in client.accounts {
                    for task in TaskKind.allCases {
                        let name = writer.taskName(
                            planID: plan.id,
                            clientID: client.id,
                            accountID: account.id,
                            task: task
                        )
                        let data = try Data(contentsOf: root.appending(path: "MAA/tasks/\(name).json"))
                        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                        XCTAssertEqual(payload["client_type"] as? String, expectedClientType)
                    }
                }
            }
        }
    }

    func testGeneratedProfileEscapesTOMLControlCharacters() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var config = populatedConfiguration()
        config.clients[0].address = "127.0.0.1:61234\n[resource]\nglobal_resource = \"Injected\"\u{1B}"

        try MAAConfigurationWriter(directories: AppDirectories(root: root)).prepare(config)

        let profile = try String(contentsOf: root.appending(path: "MAA/profiles/client-1.toml"), encoding: .utf8)
        XCTAssertTrue(profile.contains(#"address = "127.0.0.1:61234\n[resource]\nglobal_resource = \"Injected\"\u001B""#))
        XCTAssertEqual(profile.components(separatedBy: "\n[resource]\n").count, 1)
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
            XCTAssertEqual(error.localizedDescription, "每个客户端需要使用不同的 MAA Profile 名称")
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

    func testPreviousSchemaRequiresExplicitBackupAndReset() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(populatedConfiguration())) as? [String: Any]
        )
        payload["schemaVersion"] = 4
        var plans = try XCTUnwrap(payload["plans"] as? [[String: Any]])
        plans[0]["schedule"] = ["enabled": true, "hour": 7, "minute": 45]
        plans[1]["schedule"] = ["enabled": false, "hour": 21, "minute": 10]
        payload["plans"] = plans
        try JSONSerialization.data(withJSONObject: payload).write(to: directories.configuration)

        let store = ConfigurationStore(directories: directories)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ConfigurationStoreError, .unsupportedSchema(4))
        }
        let recovery = try store.backupAndReset()

        XCTAssertEqual(recovery.configuration.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertTrue(recovery.configuration.clients.isEmpty)
        XCTAssertEqual(recovery.configuration.plans.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.backupURL.path))
        let backup = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: recovery.backupURL)) as? [String: Any]
        )
        XCTAssertEqual(backup["schemaVersion"] as? Int, 4)
        XCTAssertEqual(try store.load(), recovery.configuration)
    }

    func testCurrentSchemaRejectsLegacyDailyScheduleShape() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(populatedConfiguration())) as? [String: Any]
        )
        var plans = try XCTUnwrap(payload["plans"] as? [[String: Any]])
        plans[0]["schedule"] = ["enabled": true, "hour": 7, "minute": 45]
        payload["plans"] = plans
        try JSONSerialization.data(withJSONObject: payload).write(to: directories.configuration)

        XCTAssertThrowsError(try ConfigurationStore(directories: directories).load())
    }

    func testPortAddressParsing() throws {
        let address = try PortAddress("127.0.0.1:61234")
        XCTAssertEqual(address.host, "127.0.0.1")
        XCTAssertEqual(address.port, "61234")
        let ipv6 = try PortAddress(" [::1]:61234 ")
        XCTAssertEqual(ipv6.host, "::1")
        XCTAssertEqual(ipv6.port, "61234")
        XCTAssertThrowsError(try PortAddress("127.0.0.1"))
        XCTAssertThrowsError(try PortAddress(":61234"))
        XCTAssertThrowsError(try PortAddress("127.0.0.1:0"))
        XCTAssertThrowsError(try PortAddress("127.0.0.1:65536"))
    }

    func testSensitiveDataRedactorMasksConfiguredSelectorsAndIdentifiers() {
        let output = "account user@example.com phone 12345678901 selector ABC-1234 path /Users/private-user/Applications/Game.app"
        let redacted = SensitiveDataRedactor.redact(output, sensitiveValues: ["abc-1234"])

        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("12345678901"))
        XCTAssertFalse(redacted.contains("ABC-1234"))
        XCTAssertFalse(redacted.contains("private-user"))
        XCTAssertTrue(redacted.contains("[已隐藏邮箱]"))
        XCTAssertTrue(redacted.contains("[用户目录]/Applications/Game.app"))
    }

    func testActivityHistoryGroupsRunsAndKeepsLegacyEntriesReadable() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let firstRunID = UUID()
        let secondRunID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            LogEntry(timestamp: base, level: .info, message: "旧记录"),
            LogEntry(
                timestamp: base.addingTimeInterval(100),
                level: .info,
                message: "开始第一轮",
                runID: firstRunID,
                phase: .preparing,
                progress: 0
            ),
            LogEntry(
                timestamp: base.addingTimeInterval(120),
                level: .success,
                message: "第一轮完成",
                runID: firstRunID,
                phase: .completed,
                progress: 1,
                task: .award
            ),
            LogEntry(
                timestamp: base.addingTimeInterval(200),
                level: .error,
                message: "第二轮失败",
                runID: secondRunID,
                phase: .failed,
                progress: 0.5
            ),
        ]

        let sessions = ActivityHistory.sessions(from: entries, calendar: calendar)

        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions[0].runID, secondRunID)
        XCTAssertEqual(sessions[0].errorCount, 1)
        XCTAssertEqual(sessions[1].runID, firstRunID)
        XCTAssertEqual(sessions[1].entries.map(\.message), ["开始第一轮", "第一轮完成"])
        XCTAssertEqual(sessions[1].completedTaskCount, 1)
        XCTAssertNil(sessions[2].runID)
        XCTAssertEqual(sessions[2].entries.count, 1)
        XCTAssertEqual(sessions[2].entries.first?.message, "旧记录")
    }

    func testHistoryStoreDecodesEntriesWrittenBeforeActivitySessions() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let id = UUID()
        let json = """
        [{
          "id": "\(id.uuidString)",
          "timestamp": "2026-08-02T08:00:00Z",
          "level": "success",
          "message": "旧版运行完成"
        }]
        """
        try Data(json.utf8).write(to: directories.history)

        let loaded = HistoryStore(directories: directories).load()
        XCTAssertEqual(loaded.count, 1)
        let entry = try XCTUnwrap(loaded.first)

        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.message, "旧版运行完成")
        XCTAssertNil(entry.runID)
        XCTAssertNil(entry.phase)
        XCTAssertNil(entry.details)
    }

    func testDiagnosticLogStoreRedactsOutputAndKeepsItOutsideActivityHistory() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let store = DiagnosticLogStore(directories: directories)
        let runID = UUID()
        store.begin(runID: runID)
        store.append(
            CommandResult(
                exitCode: 1,
                standardOutput: "selector private-fragment",
                standardError: "user@example.com 13800138000",
                timedOut: false
            ),
            command: "/Users/private-user/Applications/Game.app",
            runID: runID,
            sensitiveValues: ["private-fragment"]
        )

        let contents = try String(contentsOf: store.url(for: runID), encoding: .utf8)

        XCTAssertTrue(contents.contains("[用户目录]/Applications/Game.app · exit 1"))
        XCTAssertFalse(contents.contains("private-fragment"))
        XCTAssertFalse(contents.contains("private-user"))
        XCTAssertFalse(contents.contains("user@example.com"))
        XCTAssertFalse(contents.contains("13800138000"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.history.path))
    }

    @MainActor
    func testNotificationCenterWithoutApplicationBundleDegradesSafely() async throws {
        let center = ImportantNotificationCenter(canUseSystemCenter: false)
        let current = await center.authorizationState()
        let requested = try await center.requestAuthorization()
        let delivery = await center.postTestNotification()

        XCTAssertEqual(current, .denied)
        XCTAssertEqual(requested, .denied)
        XCTAssertEqual(delivery, .unavailable)
    }

    @MainActor
    func testWorkflowEventsShareOneRunIdentityAndStructuredPhase() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let client = missingClient(
            name: "缺失的测试客户端",
            path: "/Applications/Definitely-Missing-Activity-Test.app",
            port: 65528
        )
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let directories = AppDirectories(root: root)

        _ = await WorkflowRunner(directories: directories).run(config, planID: plan.id, resumeToday: false)
        let entries = HistoryStore(directories: directories).load()

        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.compactMap(\.runID)).count, 1)
        XCTAssertTrue(entries.allSatisfy { $0.runID != nil && $0.phase != nil && $0.progress != nil })
        XCTAssertEqual(ActivityHistory.sessions(from: entries).count, 1)
    }

    func testWorkflowProgressDoesNotMoveBackwardAcrossContextEvents() {
        var progress = MonotonicProgress()

        XCTAssertEqual(progress.advance(to: -1), 0)
        XCTAssertEqual(progress.advance(to: 0.4), 0.4)
        XCTAssertEqual(progress.advance(to: 0), 0.4)
        XCTAssertEqual(progress.advance(to: 0.75), 0.75)
        XCTAssertEqual(progress.advance(to: 2), 1)
        XCTAssertEqual(progress.advance(to: .nan), 1)

        progress.reset()
        XCTAssertEqual(progress.value, 0)
    }

    @MainActor
    func testCoreUpdateUsesTheSameActivityAndDiagnosticPipeline() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let cli = root.appending(path: "maa-cli")
        try Data("""
        #!/bin/sh
        printf '%s\\n' "$@" > "$MAA_CONFIG_DIR/update-arguments.txt"
        """.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)

        let succeeded = await WorkflowRunner(directories: directories).updateCore(cliPath: cli.path)
        let entries = HistoryStore(directories: directories).load()
        let runID = try XCTUnwrap(entries.first?.runID)
        let arguments = try String(contentsOf: directories.maaConfig.appending(path: "update-arguments.txt"), encoding: .utf8)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(arguments, "update\nstable\n--test-time\n10\n--batch\n")
        XCTAssertEqual(entries.map(\.phase), [.updating, .completed])
        XCTAssertTrue(entries.allSatisfy { $0.runID == runID })
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: DiagnosticLogStore(directories: directories).url(for: runID).path
        ))
    }

    @MainActor
    func testMaintenanceUpdateRetriesOneTransientNetworkFailure() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let cli = root.appending(path: "maa-cli")
        try Data("""
        #!/bin/sh
        attempts="$MAA_CONFIG_DIR/update-attempts.txt"
        count=0
        if [ -f "$attempts" ]; then
          count="$(/bin/cat "$attempts")"
        fi
        count=$((count + 1))
        printf '%s\\n' "$count" > "$attempts"
        if [ "$count" -eq 1 ]; then
          printf '%s\\n' "fatal: Failed to connect to github.com: Couldn't connect to server" >&2
          exit 1
        fi
        """.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let runtime = StubClientRuntime(closesOnForce: true)
        let runner = WorkflowRunner(
            directories: directories,
            portProbe: runtime,
            gameController: runtime,
            shutdownPolicy: .immediate,
            maintenanceRetryDelay: .zero,
            eventSink: runtime.record
        )

        let succeeded = await runner.updateCore(cliPath: cli.path)
        let attempts = try String(
            contentsOf: directories.maaConfig.appending(path: "update-attempts.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = HistoryStore(directories: directories).load()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(attempts, "2")
        XCTAssertEqual(entries.map(\.phase), [.updating, .updating, .completed])
        XCTAssertEqual(entries[1].level, .info)
        XCTAssertTrue(entries[1].message.contains("临时网络问题"))
        XCTAssertEqual(entries.last?.message, "MAA 核心与基础资源重试后已更新")
    }

    func testMaintenanceRetryClassifierRejectsNonNetworkFailuresAndCancellation() {
        XCTAssertTrue(MAAMaintenanceFailureClassifier.isTransientNetworkFailure(.init(
            exitCode: 1,
            standardOutput: "",
            standardError: "Could not resolve host: github.com",
            timedOut: false
        )))
        XCTAssertFalse(MAAMaintenanceFailureClassifier.isTransientNetworkFailure(.init(
            exitCode: 1,
            standardOutput: "",
            standardError: "checksum mismatch",
            timedOut: false
        )))
        XCTAssertFalse(MAAMaintenanceFailureClassifier.isTransientNetworkFailure(.init(
            exitCode: 1,
            standardOutput: "",
            standardError: "Failed to connect",
            timedOut: false,
            cancelled: true
        )))
    }

    @MainActor
    func testCoreUpdateDoesNotRaceWithAWorkflowLock() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        var lock: ProcessLock? = try ProcessLock(url: directories.lock)
        XCTAssertNotNil(lock)

        let succeeded = await WorkflowRunner(directories: directories).updateCore(cliPath: "/usr/bin/true")
        let entries = HistoryStore(directories: directories).load()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(entries.map(\.phase), [.failed])
        XCTAssertTrue(entries[0].message.contains("已有一个 AutoMAA 流程正在运行"))
        lock = nil
        XCTAssertFalse(ProcessLock.isHeld(at: directories.lock))
    }

    func testStructuralValidationRejectsDamagedStepOrderAndInvalidSeries() {
        var config = populatedConfiguration()
        config.plans[0].stepOrder = [.fight, .fight]
        config.plans[0].fight.series = 11

        let messages = ConfigurationValidator.structuralProblems(in: config).map(\.message)

        XCTAssertTrue(messages.contains { $0.contains("步骤顺序已损坏") })
        XCTAssertTrue(messages.contains { $0.contains("连战次数") })
    }

    func testDormantCustomValuesDoNotBlockRecommendedOrDisabledTasks() {
        var config = populatedConfiguration()
        config.plans[0].fight.series = 11
        config.plans[0].fight.usesCustomSettings = false
        config.plans[0].infrast.facilities = []
        config.plans[0].infrast.enabled = false
        config.plans[0].mall.formationIndex = 99
        config.plans[0].mall.enabled = false

        let problems = ConfigurationValidator.structuralProblems(in: config)

        XCTAssertFalse(problems.contains { $0.id.contains("fight-series") })
        XCTAssertFalse(problems.contains { $0.id.contains("infrast-facilities") })
        XCTAssertFalse(problems.contains { $0.id.contains("mall-formation") })
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

    func testStartupFailureClassifierRecognizesScreenshotConnectionFailure() {
        let result = StartupFailureClassifier.diagnose(output: "ScreencapFailed", hasAccountSelector: true)

        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("MaaTools 连接异常"))
    }

    func testStartupFailureClassifierRecognizesGameOffline() {
        let output = "GameOffline: Auto reconnect disabled, stopping"
        let result = StartupFailureClassifier.diagnose(output: output, hasAccountSelector: false)

        XCTAssertTrue(StartupFailureClassifier.isGameOffline(output))
        XCTAssertEqual(result.scope, .client)
        XCTAssertTrue(result.guidance.contains("重启客户端后仍未恢复"))
    }

    func testWorkflowReportRequiresAttentionIsNotSuccess() {
        XCTAssertFalse(WorkflowReport(attentionMessages: ["请手动更新游戏"]).isSuccess)
        XCTAssertFalse(WorkflowReport(cancelled: true).isSuccess)
    }

    func testWorkflowReportNoticeDoesNotTurnCompletedRunIntoFailure() {
        let notice = WorkflowNotice(message: "公招发现 6★ 组合")

        XCTAssertTrue(WorkflowReport(notices: [notice]).isSuccess)
    }

    func testImportantNotificationComposerKeepsAlertsRareAndPrivate() {
        XCTAssertNil(WorkflowNotificationComposer.notification(for: WorkflowReport()))
        XCTAssertNil(WorkflowNotificationComposer.notification(for: WorkflowReport(cancelled: true)))

        let recruit = WorkflowReport(notices: [WorkflowNotice(
            message: "账号「测试账号」：公招发现 6★ 组合，请前往游戏确认",
            details: "识别标签：高级资深干员、输出",
            kind: .highRarityRecruit(level: 6)
        )])
        let recruitNotification = WorkflowNotificationComposer.notification(for: recruit)

        XCTAssertEqual(recruitNotification?.title, "公开招募发现 6★ 组合")
        XCTAssertFalse(recruitNotification?.body.contains("测试账号") == true)
        XCTAssertFalse(recruitNotification?.body.contains("高级资深干员") == true)

        let failed = WorkflowNotificationComposer.notification(for: WorkflowReport(failedSteps: 2))
        XCTAssertEqual(failed?.title, "自动化流程有步骤失败")
        XCTAssertEqual(failed?.body, "有 2 个步骤未完成，请打开 AutoMAA 查看活动记录。")
    }

    func testImportantNotificationComposerDoesNotRepeatDeliveredRecruitNotice() {
        let notice = WorkflowNotice(
            message: "公招发现 6★ 组合",
            kind: .highRarityRecruit(level: 6)
        )
        let completed = WorkflowReport(
            notices: [notice],
            pendingNotificationNotices: []
        )
        let failed = WorkflowReport(
            failedSteps: 1,
            notices: [notice],
            pendingNotificationNotices: []
        )

        XCTAssertNil(WorkflowNotificationComposer.notification(for: completed))
        XCTAssertEqual(
            WorkflowNotificationComposer.notification(for: failed)?.title,
            "自动化流程有步骤失败"
        )
    }

    @MainActor
    func testWorkflowDeliversRecruitNoticeBeforeFinalReport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Applications/Test Game.app", directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        let cli = bin.appending(path: "fake-maa")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = """
        #!/bin/zsh
        if [[ "$1" == "run" ]]; then
          printf '%s\\n' \
            'Detected tags:' \
            '1. ★★★★★★ 高级资深干员, 远程位, 输出, 生存, 狙击干员'
        fi
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)

        let account = AccountConfiguration(name: "测试账号", accountSelector: "fixture-selector")
        let client = ClientConfiguration(
            name: "测试客户端",
            kind: .official,
            appPath: app.path,
            address: "127.0.0.1:65494",
            profileName: "notification-test",
            bundleIdentifier: "dev.automaa.tests.notification",
            accounts: [account]
        )
        var plan = AutomationPlan.lightRoutine
        plan.fight.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = false
        plan.policy.hotUpdateBeforeRun = false
        plan.policy.maxRetries = 0
        let configuration = AppConfiguration(cliPath: cli.path, clients: [client], plans: [plan])
        let runtime = StubClientRuntime(closesOnForce: true)
        var delivered: [[WorkflowNotice]] = []
        let runner = WorkflowRunner(
            directories: AppDirectories(root: root),
            portProbe: runtime,
            gameController: runtime,
            shutdownPolicy: .immediate,
            noticeSink: { notices, _ in
                delivered.append(notices)
                return .delivered
            },
            eventSink: runtime.record
        )

        let report = await runner.run(configuration, planID: plan.id, resumeToday: false)

        XCTAssertTrue(report.isSuccess, report.fatalError ?? report.attentionMessages.joined(separator: " / "))
        XCTAssertEqual(delivered, [report.notices])
        XCTAssertEqual(report.notices.count, 1)
        XCTAssertTrue(report.pendingNotificationNotices.isEmpty)
        XCTAssertNil(WorkflowNotificationComposer.notification(for: report))
    }

    func testImportantNotificationComposerCombinesRecruitAndWorkflowAttention() {
        let report = WorkflowReport(
            attentionMessages: ["客户端需要更新"],
            notices: [WorkflowNotice(message: "公招命中保留标签", kind: .preservedRecruitTag)]
        )

        let notification = WorkflowNotificationComposer.notification(for: report)

        XCTAssertEqual(notification?.title, "公开招募需要确认")
        XCTAssertTrue(notification?.body.contains("1 项稀有或保留标签结果") == true)
        XCTAssertTrue(notification?.body.contains("另有情况需要手动处理") == true)
        XCTAssertFalse(notification?.body.contains("客户端需要更新") == true)
    }

    func testActivityWarningCountDoesNotCountCompletionSummaryTwice() {
        let runID = UUID()
        let session = ActivitySession(
            id: "run-\(runID.uuidString)",
            runID: runID,
            entries: [
                LogEntry(level: .warning, message: "公招发现 6★ 组合", runID: runID, phase: .runningTask),
                LogEntry(level: .warning, message: "流程完成，有 1 项需要确认", runID: runID, phase: .completed),
            ]
        )

        XCTAssertEqual(session.warningCount, 1)
    }

    func testActivitySessionExposesStructuredPartialCompletion() {
        let runID = UUID()
        let summary = WorkflowRunSummary(completedSteps: 8, failedSteps: 0, unexecutedSteps: 4, totalSteps: 12)
        let session = ActivitySession(
            id: "run-\(runID.uuidString)",
            runID: runID,
            entries: [
                LogEntry(
                    level: .warning,
                    message: "流程部分完成",
                    runID: runID,
                    phase: .completed,
                    progress: 1,
                    runSummary: summary
                ),
            ]
        )

        XCTAssertEqual(session.runSummary, summary)
        XCTAssertEqual(session.completedTaskCount, 8)
        XCTAssertEqual(session.unexecutedTaskCount, 4)
        XCTAssertTrue(session.runSummary?.isPartial == true)
    }

    func testMAAOutputNoticeParserElevatesHighRarityRecruitResultWithoutDuplicateTip() {
        let output = """
        [2026-08-03 09:00:00.000][INFO] RecruitingTips: 高级资深干员
        [2026-08-03 09:00:00.100][INFO] RecruitResult: ★★★★★★ 高级资深干员, 远程位, 输出, 生存, 狙击干员
        """

        XCTAssertEqual(
            MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: ["支援机械"]),
            [.highRarity(
                level: 6,
                tags: ["高级资深干员", "远程位", "输出", "生存", "狙击干员"]
            )]
        )
    }

    func testMAAOutputNoticeParserElevatesFiveStarDetectedTagsSummary() {
        let output = """
        Summary
        ----------------------------------------
        [公开招募] 21:34:23 - 21:35:07 (44s) Completed
        Detected tags:
        1. ★★★★★ 牽制, エリート, ロボット, 先鋒タイプ, 減速
        2. ★★★ 重装タイプ, 初期, COST回復, 前衛タイプ, 範囲攻撃, Refreshed
        Recruited 1 times
        Refreshed 1 times
        """

        XCTAssertEqual(
            MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: []),
            [.highRarity(
                level: 5,
                tags: ["牽制", "エリート", "ロボット", "先鋒タイプ", "減速"]
            )]
        )
    }

    func testMAAOutputNoticeParserElevatesSixStarDetectedTagsSummary() {
        let output = """
        Detected tags:
        1. ★★★★★★ 高级资深干员, 远程位, 输出, 生存, 狙击干员
        2. ★ 支援机械, 近战位, 费用回复, 治疗, 先锋干员, Refreshed
        Refreshed 1 times
        """

        XCTAssertEqual(
            MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: ["支援机械"]),
            [
                .highRarity(
                    level: 6,
                    tags: ["高级资深干员", "远程位", "输出", "生存", "狙击干员"]
                ),
                .preservedTag(
                    tag: "支援机械",
                    tags: ["支援机械", "近战位", "费用回复", "治疗", "先锋干员"]
                ),
            ]
        )
    }

    func testMAAOutputNoticeParserDeduplicatesDetailedAndSummarizedResult() {
        let output = """
        RecruitResult: ★★★★★★ 高级资深干员, 远程位, 输出, 生存, 狙击干员
        Detected tags:
        1. ★★★★★★ 高级资深干员, 远程位, 输出, 生存, 狙击干员
        """

        XCTAssertEqual(
            MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: []),
            [.highRarity(
                level: 6,
                tags: ["高级资深干员", "远程位", "输出", "生存", "狙击干员"]
            )]
        )
    }

    func testMAAOutputNoticeParserElevatesConfiguredPreservedTag() {
        let output = "\u{001B}[32mRecruitResult: ★ 支援机械, 近战位, 费用回复, 治疗, 先锋干员\u{001B}[0m"

        XCTAssertEqual(
            MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: [" 支援机械 "]),
            [.preservedTag(
                tag: "支援机械",
                tags: ["支援机械", "近战位", "费用回复", "治疗", "先锋干员"]
            )]
        )
    }

    func testMAAOutputNoticeParserKeepsSpecialTipWhenNoResultIsAvailable() {
        let output = "[INFO] RecruitingTips: 资深干员"

        XCTAssertEqual(
            MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: []),
            [.specialTag("资深干员")]
        )
    }

    func testMAAOutputNoticeParserIgnoresOrdinaryAndMalformedRecruitLines() {
        let output = """
        RecruitResult: ★★★ 近战位, 输出, 生存, 防护, 重装干员
        RecruitResult: ★★★★★★★ invalid
        RecruitingTips:
        """

        XCTAssertTrue(MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: []).isEmpty)
    }

    func testMAAOutputSummaryParserReadsFightStageCountAndLocalizedDrops() {
        let output = """
        Summary
        ----------------------------------------
        [理智作战] 09:01:09 - 09:06:23 (5m 14s) Completed
        \u{001B}[32mFight TO-5 2 times, drops:\u{001B}[0m
        1. 沿途的点滴 × 120, 装置 × 7, 酮凝集 × 4, 龙门币 × 1440
        2. 沿途的点滴 × 36, 装置 × 3, 龙门币 × 432
        total drops: 沿途的点滴 × 156, 装置 × 10, 酮凝集 × 4, 龙门币 × 1872
        """

        XCTAssertEqual(
            MAAOutputSummaryParser.fightSummary(in: output),
            MAAFightSummary(
                stage: "TO-5",
                times: 2,
                totalDrops: "沿途的点滴 × 156, 装置 × 10, 酮凝集 × 4, 龙门币 × 1872"
            )
        )
    }

    func testMAAOutputSummaryParserPreservesOtherLocalesAndAllowsMissingDrops() {
        XCTAssertEqual(
            MAAOutputSummaryParser.fightSummary(in: """
            Fight AP-5 4 times, drops:
            total drops: 購買資格証 × 84, 龍門幣 × 1440
            """),
            MAAFightSummary(stage: "AP-5", times: 4, totalDrops: "購買資格証 × 84, 龍門幣 × 1440")
        )
        XCTAssertEqual(
            MAAOutputSummaryParser.fightSummary(in: "Fight Annihilation 0 times"),
            MAAFightSummary(stage: "Annihilation", times: 0, totalDrops: nil)
        )
    }

    func testMAAOutputSummaryParserIgnoresMalformedOrUnrelatedOutput() {
        XCTAssertNil(MAAOutputSummaryParser.fightSummary(in: "Fight TO-5 twice, drops:"))
        XCTAssertNil(MAAOutputSummaryParser.fightSummary(in: "total drops: 龙门币 × 1440"))
        XCTAssertNil(MAAOutputSummaryParser.fightSummary(in: "BeforeFight TO-5 2 times, drops:"))
    }

    @MainActor
    func testWorkflowCompletionRecordsFightSummaryAndTotalDrops() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Applications/Test Game.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let cli = root.appending(path: "maa-cli")
        let script = """
        #!/bin/sh
        if [ "$1" = "run" ]; then
          printf '%s\\n' \
            'Fight TO-5 2 times, drops:' \
            'total drops: 沿途的点滴 × 156, 装置 × 10, 酮凝集 × 4, 龙门币 × 1872'
        fi
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)

        let account = AccountConfiguration(name: "测试账号")
        let client = ClientConfiguration(
            name: "测试客户端",
            kind: .official,
            appPath: app.path,
            address: "127.0.0.1:65492",
            profileName: "fight-summary",
            bundleIdentifier: "dev.automaa.tests.fight-summary",
            accounts: [account]
        )
        var plan = AutomationPlan.lightRoutine
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = false
        plan.policy.hotUpdateBeforeRun = false
        plan.policy.maxRetries = 0
        let configuration = AppConfiguration(cliPath: cli.path, clients: [client], plans: [plan])
        let runtime = StubClientRuntime(closesOnForce: true)
        let runner = WorkflowRunner(
            directories: AppDirectories(root: root),
            portProbe: runtime,
            gameController: runtime,
            shutdownPolicy: .immediate,
            eventSink: runtime.record
        )

        let report = await runner.run(configuration, planID: plan.id, resumeToday: false)
        let completion = try XCTUnwrap(runtime.events.first {
            $0.log.task == .fight && $0.log.level == .success && $0.message.contains("已完成")
        })

        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(completion.message, "账号「测试账号」：理智作战已完成（TO-5 × 2）")
        XCTAssertEqual(
            completion.log.details,
            "总掉落：沿途的点滴 × 156, 装置 × 10, 酮凝集 × 4, 龙门币 × 1872"
        )
    }

    @MainActor
    func testRecoveredRetriesRemainVisibleWithoutCreatingWarnings() async throws {
        let (report, runtime) = try await runRetryScenario(startupFailures: 1, taskFailures: 1)
        let entries = runtime.events.map(\.log)

        XCTAssertTrue(report.isSuccess)
        XCTAssertTrue(report.attentionMessages.isEmpty)
        XCTAssertEqual(ActivitySession(id: "test", runID: entries.first?.runID, entries: entries).warningCount, 0)
        XCTAssertTrue(entries.contains {
            $0.level == .info
                && $0.message == "账号「测试账号」准备暂未完成，正在自动重试（1/1）"
                && $0.details?.contains("ScreencapFailed") == true
        })
        XCTAssertTrue(entries.contains {
            $0.level == .success && $0.message == "账号「测试账号」重试后已就绪"
        })
        XCTAssertTrue(entries.contains {
            $0.level == .info && $0.message == "账号「测试账号」：理智作战未完成，正在自动重试（1/1）"
        })
        XCTAssertTrue(entries.contains {
            $0.level == .success && $0.message == "账号「测试账号」：理智作战重试后已完成"
        })
    }

    @MainActor
    func testExhaustedAccountRetriesCreateOneActionableWarning() async throws {
        let (report, runtime) = try await runRetryScenario(startupFailures: 2, taskFailures: 0)
        let entries = runtime.events.map(\.log)
        let warnings = entries.filter { $0.level == .warning && $0.phase != .completed }

        XCTAssertFalse(report.isSuccess)
        XCTAssertEqual(report.attentionMessages.count, 1)
        XCTAssertEqual(report.skippedSteps, 1)
        XCTAssertEqual(report.unexecutedSteps, 1)
        XCTAssertEqual(report.runSummary, WorkflowRunSummary(
            completedSteps: 0,
            failedSteps: 0,
            unexecutedSteps: 1,
            totalSteps: 1
        ))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].phase, .attention)
        XCTAssertTrue(warnings[0].message.contains("账号「测试账号」准备失败"))
        XCTAssertTrue(warnings[0].details?.contains("ScreencapFailed") == true)
        XCTAssertFalse(entries.contains { $0.task != nil })
        XCTAssertEqual(entries.last?.runSummary, report.runSummary)
        XCTAssertEqual(entries.last?.message, "流程部分完成：0/1 个步骤完成，1 个未执行；需要手动处理：账号「测试账号」准备失败。网络或 MaaTools 连接异常，自动重试仍未恢复；请手动检查游戏和网络，本次将跳过该客户端")
    }

    @MainActor
    func testGameOfflineRestartsClientOnceBeforePreparingAccountAgain() async throws {
        let (report, runtime) = try await runRetryScenario(
            startupFailures: 1,
            taskFailures: 0,
            startupFailureOutput: "GameOffline: Auto reconnect disabled, stopping",
            maxRetries: 0,
            opensOnWait: true
        )

        XCTAssertTrue(report.isSuccess)
        XCTAssertTrue(runtime.events.contains {
            $0.log.level == .info && $0.message.contains("检测到游戏连接离线，正在重启客户端")
        })
        XCTAssertTrue(runtime.events.contains {
            $0.log.level == .success && $0.message == "账号「测试账号」恢复后已就绪"
        })
        XCTAssertEqual(runtime.events.count {
            $0.log.level == .info && $0.message.contains("检测到游戏连接离线，正在重启客户端")
        }, 1)
        XCTAssertGreaterThanOrEqual(runtime.terminationRequests.filter { $0 }.count, 2)
    }

    @MainActor
    func testRepeatedGameOfflineDoesNotRestartTheSameClientTwice() async throws {
        let (report, runtime) = try await runRetryScenario(
            startupFailures: 2,
            taskFailures: 0,
            startupFailureOutput: "GameOffline: Auto reconnect disabled, stopping",
            maxRetries: 0,
            opensOnWait: true
        )

        XCTAssertFalse(report.isSuccess)
        XCTAssertEqual(report.unexecutedSteps, 1)
        XCTAssertEqual(runtime.events.count {
            $0.log.level == .info && $0.message.contains("检测到游戏连接离线，正在重启客户端")
        }, 1)
        XCTAssertTrue(runtime.events.last?.message.contains("重启客户端后仍未恢复") == true)
    }

    @MainActor
    private func runRetryScenario(
        startupFailures: Int,
        taskFailures: Int,
        startupFailureOutput: String = "ScreencapFailed",
        maxRetries: Int = 1,
        opensOnWait: Bool = false
    ) async throws -> (WorkflowReport, StubClientRuntime) {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Applications/Test Game.app", directoryHint: .isDirectory)
        try createTestApplication(at: app)
        let cli = root.appending(path: "maa-cli")
        let startupCounter = root.appending(path: "startup-count").path
        let taskCounter = root.appending(path: "task-count").path
        let script = """
        #!/bin/sh
        if [ "$1" = "startup" ]; then
          count=0
          [ ! -f "\(startupCounter)" ] || count=$(sed -n '1p' "\(startupCounter)")
          count=$((count + 1))
          printf '%s\n' "$count" > "\(startupCounter)"
          if [ "$count" -le "\(startupFailures)" ]; then
            printf '%s\n' '\(startupFailureOutput)' >&2
            exit 1
          fi
        elif [ "$1" = "run" ]; then
          count=0
          [ ! -f "\(taskCounter)" ] || count=$(sed -n '1p' "\(taskCounter)")
          count=$((count + 1))
          printf '%s\n' "$count" > "\(taskCounter)"
          if [ "$count" -le "\(taskFailures)" ]; then
            printf '%s\n' 'temporary task failure' >&2
            exit 1
          fi
        fi
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)

        let account = AccountConfiguration(name: "测试账号", accountSelector: "fixture-selector")
        let client = ClientConfiguration(
            name: "测试客户端",
            kind: .official,
            appPath: app.path,
            address: "127.0.0.1:65493",
            profileName: "retry-severity",
            bundleIdentifier: "dev.automaa.tests.retry-severity",
            accounts: [account]
        )
        var plan = AutomationPlan.lightRoutine
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = false
        plan.policy.hotUpdateBeforeRun = false
        plan.policy.maxRetries = maxRetries
        let configuration = AppConfiguration(cliPath: cli.path, clients: [client], plans: [plan])
        let runtime = StubClientRuntime(closesOnForce: true, opensOnWait: opensOnWait)
        let runner = WorkflowRunner(
            directories: AppDirectories(root: root),
            portProbe: runtime,
            gameController: runtime,
            shutdownPolicy: .immediate,
            eventSink: runtime.record
        )

        let report = await runner.run(configuration, planID: plan.id, resumeToday: false)
        return (report, runtime)
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
            bundleIdentifier: "dev.automaa.tests.completed",
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
            bundleIdentifier: "dev.automaa.tests.plan-isolation",
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

    @MainActor
    func testDuplicateAccountSelectorsStopBeforeOpeningClient() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = AutomationPlan.lightRoutine
        plan.policy.hotUpdateBeforeRun = false
        let first = AccountConfiguration(name: "测试账号一", accountSelector: "same")
        let second = AccountConfiguration(name: "测试账号二", accountSelector: "same")
        let client = ClientConfiguration(
            name: "不应启动",
            kind: .official,
            appPath: "/Applications/Definitely-Missing-Duplicate-Selector.app",
            address: "127.0.0.1:65530",
            profileName: "duplicate-selector",
            bundleIdentifier: "dev.automaa.tests.duplicate-selector",
            accounts: [first, second]
        )
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])

        let report = await WorkflowRunner(directories: AppDirectories(root: root)).run(
            config,
            planID: plan.id,
            resumeToday: false
        )

        XCTAssertTrue(report.fatalError?.contains("账号片段不能重复") == true)
        XCTAssertTrue(report.attentionMessages.isEmpty)
        XCTAssertEqual(report.skippedSteps, 0)
    }

    func testUnsupportedClientAccountSwitchingIsRejectedBeforeRunning() {
        let first = AccountConfiguration(name: "测试账号一", accountSelector: "first")
        let second = AccountConfiguration(name: "测试账号二", accountSelector: "second")
        let client = ClientConfiguration(
            name: "日服测试客户端",
            kind: .yoStarJP,
            appPath: "/Applications/Definitely-Missing-YoStarJP.app",
            address: "127.0.0.1:65529",
            profileName: "unsupported-account-switch",
            bundleIdentifier: "dev.automaa.tests.yostar-jp",
            accounts: [first, second]
        )
        let plan = AutomationPlan.lightRoutine
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])

        let problems = ConfigurationValidator.readinessProblems(in: config, planID: plan.id)

        XCTAssertTrue(problems.contains {
            $0.severity == .error && $0.message.contains("日服不支持自动切换账号")
        })
        XCTAssertTrue(problems.contains {
            $0.severity == .error && $0.message.contains("账号片段必须留空")
        })
    }

    func testYoStarKRAccountSwitchingUsesTheSameUniqueSelectorRules() {
        let first = AccountConfiguration(name: "韩服账号一", accountSelector: "01@gmail")
        let second = AccountConfiguration(name: "韩服账号二", accountSelector: "02@gmail")
        let client = ClientConfiguration(
            name: "韩服测试客户端",
            kind: .yoStarKR,
            appPath: "/Applications/Definitely-Missing-YoStarKR.app",
            address: "127.0.0.1:65528",
            profileName: "supported-account-switch",
            bundleIdentifier: "dev.automaa.tests.yostar-kr",
            accounts: [first, second]
        )
        let plan = AutomationPlan.lightRoutine
        let config = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])

        let problems = ConfigurationValidator.readinessProblems(in: config, planID: plan.id)

        XCTAssertFalse(problems.contains { $0.id.contains("account-switch-unsupported") })
        XCTAssertFalse(problems.contains { $0.id.contains("selector-unsupported") })
        XCTAssertFalse(problems.contains { $0.id.contains("selector-empty") })
        XCTAssertFalse(problems.contains { $0.id.contains("selector-duplicate") })
    }

    private func populatedConfiguration() -> AppConfiguration {
        AppConfiguration(clients: [
            ClientConfiguration(
                name: "测试客户端 1",
                kind: .official,
                appPath: "/tmp/automaa-fixtures/never-exists-game-one.app",
                profileName: "client-1",
                bundleIdentifier: "dev.automaa.tests.game-one",
                accounts: [AccountConfiguration(name: "测试账号 1")]
            ),
            ClientConfiguration(
                name: "测试客户端 2",
                kind: .yoStarJP,
                appPath: "/tmp/automaa-fixtures/never-exists-game-two.app",
                profileName: "client-2",
                bundleIdentifier: "dev.automaa.tests.game-two",
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

    private func createTestApplication(at app: URL) throws {
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let executables = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: executables.appending(path: "TestGame"),
            withDestinationURL: URL(filePath: "/usr/bin/true")
        )
        let payload: [String: Any] = [
            "CFBundleExecutable": "TestGame",
            "CFBundleIdentifier": "dev.automaa.tests.retry-game",
            "CFBundleName": "AutoMAA Test Game",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appending(path: "Info.plist"), options: .atomic)
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
