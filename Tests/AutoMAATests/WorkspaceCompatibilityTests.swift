import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Workspace compatibility")
struct WorkspaceCompatibilityTests {
    @Test("schema 7 task values survive editor bindings, recommended mode and reordered saves", arguments: [false, true])
    @MainActor
    func existingConfigurationSurvivesWorkspaceEdits(emptyOptionalValues: Bool) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let fixture = try configurationFixture(root: root, emptyOptionalValues: emptyOptionalValues)
        try fixture.write(to: directories.configuration, options: .atomic)
        let original = try JSONDecoder().decode(AppConfiguration.self, from: fixture)
        let model = makeModel(root: root)
        #expect(model.configuration == original)
        #expect(model.configuration.schemaVersion == 7)
        let planID = try #require(original.plans.first?.id)
        let binding = try #require(model.planBinding(planID))

        var edited = binding.wrappedValue
        edited.fight.settingsMode = .maaDefault
        edited.recruit.settingsMode = .maaDefault
        edited.infrast.settingsMode = .maaDefault
        edited.mall.settingsMode = .maaDefault
        edited.award.settingsMode = .maaDefault
        edited.stepOrder = [.award, .mall, .fight, .infrast, .recruit]
        binding.wrappedValue = edited
        #expect(model.saveNow(showConfirmation: false))
        #expect(try ConfigurationStore(directories: directories).load().plans[0] == edited)

        let reopened = makeModel(root: root)
        let restoredBinding = try #require(reopened.planBinding(planID))
        var restored = restoredBinding.wrappedValue
        restored.fight.settingsMode = .custom
        restored.recruit.settingsMode = .custom
        restored.infrast.settingsMode = .custom
        restored.mall.settingsMode = .custom
        restored.award.settingsMode = .custom
        restoredBinding.wrappedValue = restored
        #expect(reopened.saveNow(showConfirmation: false))

        var expected = original
        expected.plans[0].stepOrder = edited.stepOrder
        #expect(reopened.configuration == expected)
        #expect(try ConfigurationStore(directories: directories).load() == expected)
        #expect(!ConfigurationValidator.structuralProblems(in: reopened.configuration).contains { $0.severity == .error })
        #expect(Set(restored.stepOrder) == Set(TaskKind.allCases))
        #expect(restored.stepOrder.count == TaskKind.allCases.count)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.lastPathComponent.hasSuffix(".backup.json") })
    }

    @Test("optional parameter memory preserves explicit zero without leaking between fields or plans")
    @MainActor
    func optionalParameterMemoryKeepsPlanScope() {
        let memory = PlanOptionalParameterMemory()
        let firstPlan = UUID()
        let secondPlan = UUID()
        memory.remember(0, planID: firstPlan, field: .medicine)
        memory.remember(12, planID: secondPlan, field: .medicine)
        memory.remember(2, planID: firstPlan, field: .medicineExpireDays)

        #expect(memory.value(planID: firstPlan, field: .medicine) == 0)
        #expect(memory.value(planID: secondPlan, field: .medicine) == 12)
        #expect(memory.value(planID: firstPlan, field: .medicineExpireDays) == 2)
        #expect(memory.value(planID: firstPlan, field: .stone) == nil)
        #expect(memory.value(planID: secondPlan, field: .medicineExpireDays) == nil)
    }

    @Test("a disabled schedule can save its draft without an installed MAA and preserves task settings")
    @MainActor
    func executionArrangementWithoutMAA() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        model.configuration.cliPath = root.appending(path: "missing-maa").path
        #expect(model.saveNow(showConfirmation: false))
        let original = model.configuration
        let plan = try #require(original.plans.first)
        var schedule = plan.schedule
        schedule.rules[0].hour = 18
        schedule.rules[0].minute = 25
        var policy = plan.policy
        policy.hotUpdateBeforeRun = false
        policy.maxRetries = 3
        policy.continueAfterStepFailure = false

        #expect(model.configuration == original)
        #expect(try ConfigurationStore(directories: model.directories).load() == original)
        let error = model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: false, accountIDs: [], schedule: schedule, policy: policy
        )

        #expect(error == nil)
        var expected = original
        expected.plans[0].includesAllEnabledAccounts = false
        expected.plans[0].accountIDs = []
        expected.plans[0].schedule = schedule
        expected.plans[0].policy = policy
        #expect(model.configuration == expected)
        #expect(try ConfigurationStore(directories: model.directories).load() == expected)
        #expect(model.installedPlanIDs.isEmpty)
    }

    @Test("enabling a schedule validates the candidate account selection before changing configuration")
    @MainActor
    func executionArrangementValidatesCandidateAccounts() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        #expect(model.saveNow(showConfirmation: false))
        let original = model.configuration
        let plan = try #require(original.plans.first)
        let accountID = try #require(original.clients.first?.accounts.first?.id)
        var schedule = plan.schedule
        schedule.enabled = true

        let rejected = model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: false, accountIDs: [], schedule: schedule, policy: plan.policy
        )
        #expect(rejected?.contains("没有可执行的账号") == true)
        #expect(model.configuration == original)
        #expect(try ConfigurationStore(directories: model.directories).load() == original)

        model.configuration.plans[0].includesAllEnabledAccounts = false
        model.configuration.plans[0].accountIDs = []
        #expect(model.saveNow(showConfirmation: false))
        #expect(!model.canRun(planID: plan.id))
        let accepted = model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: false, accountIDs: [accountID], schedule: schedule, policy: plan.policy
        )
        #expect(accepted == nil)
        try await waitForScheduleSynchronization(model)
        #expect(model.configuration.plans[0].accountIDs == [accountID])
        #expect(model.isPlanScheduleCurrent(model.configuration.plans[0]))
        #expect(try ConfigurationStore(directories: model.directories).load() == model.configuration)
    }

    @Test("a conflicting draft leaves the existing schedule and policy unchanged")
    @MainActor
    func executionArrangementRejectsConflictingSchedule() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        model.configuration.plans[1].schedule.enabled = true
        try ConfigurationStore(directories: model.directories).save(model.configuration)
        let original = model.configuration
        let plan = original.plans[0]
        var policy = plan.policy
        policy.maxRetries = 4

        let error = model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: true, accountIDs: [],
            schedule: original.plans[1].schedule, policy: policy
        )

        #expect(error?.contains("冲突") == true)
        #expect(model.configuration == original)
        #expect(try ConfigurationStore(directories: model.directories).load() == original)
    }

    @Test("failed draft persistence leaves model and generated files unchanged and permits retry")
    @MainActor
    func executionArrangementSaveFailure() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        #expect(model.saveNow(showConfirmation: false))
        let original = model.configuration
        let originalData = try Data(contentsOf: model.directories.configuration)
        let manifest = try Data(contentsOf: model.directories.generatedManifest)
        let plan = original.plans[0]
        var schedule = plan.schedule
        schedule.rules[0].hour = 15
        try FileManager.default.removeItem(at: model.directories.configuration)
        try FileManager.default.createDirectory(at: model.directories.configuration, withIntermediateDirectories: false)

        let error = model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: false, accountIDs: [], schedule: schedule, policy: plan.policy
        )

        #expect(error != nil)
        #expect(model.configuration == original)
        #expect(try Data(contentsOf: model.directories.generatedManifest) == manifest)
        try FileManager.default.removeItem(at: model.directories.configuration)
        try originalData.write(to: model.directories.configuration, options: .atomic)
        #expect(model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: false, accountIDs: [], schedule: schedule, policy: plan.policy
        ) == nil)
        #expect(model.configuration.plans[0].schedule == schedule)
        #expect(try ConfigurationStore(directories: model.directories).load() == model.configuration)
    }

    @Test("execution arrangements cannot be committed during local or background runs", arguments: [false, true])
    @MainActor
    func executionArrangementDuringRun(externalRun: Bool) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let original = model.configuration
        let plan = original.plans[0]
        let lock = externalRun ? try ProcessLock(url: model.directories.lock) : nil
        defer { withExtendedLifetime(lock) {} }
        model.isRunning = !externalRun
        var schedule = plan.schedule
        schedule.rules[0].hour = 16

        let error = model.applyPlanExecutionArrangement(
            plan.id, includesAllEnabledAccounts: false, accountIDs: [], schedule: schedule, policy: plan.policy
        )

        #expect(error?.contains("运行期间") == true)
        #expect(model.configuration == original)
        #expect(try ConfigurationStore(directories: model.directories).load() == original)
    }

    @Test("opening entity drafts and failed account saves do not create partial entities or plan membership")
    @MainActor
    func entityDraftsRemainIndependentUntilSaved() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        model.configuration.plans[0].includesAllEnabledAccounts = false
        #expect(model.saveNow(showConfirmation: false))
        let original = model.configuration
        let originalData = try Data(contentsOf: model.directories.configuration)
        let clientID = original.clients[0].id
        var clientDraft = model.newClientDraft()
        clientDraft.name = "未提交客户端"
        var accountDraft = model.newAccountDraft(clientID: clientID)
        accountDraft.name = "未提交账号"
        #expect(model.configuration == original)
        #expect(!model.configuration.clients.contains { $0.id == clientDraft.id })
        #expect(try ConfigurationStore(directories: model.directories).load() == original)

        try FileManager.default.removeItem(at: model.directories.configuration)
        try FileManager.default.createDirectory(at: model.directories.configuration, withIntermediateDirectories: false)
        #expect(model.saveClientDraft(clientDraft, isNew: true) != nil)
        #expect(model.saveAccountDraft(accountDraft, clientID: clientID, isNew: true,
                                      planIDs: [original.plans[0].id]) != nil)
        #expect(model.configuration == original)

        try FileManager.default.removeItem(at: model.directories.configuration)
        try originalData.write(to: model.directories.configuration, options: .atomic)
        #expect(model.saveAccountDraft(accountDraft, clientID: clientID, isNew: true,
                                      planIDs: [original.plans[0].id]) == nil)
        #expect(model.configuration.clients[0].accounts.last == accountDraft)
        #expect(model.configuration.plans[0].accountIDs == [accountDraft.id])
        #expect(model.configuration.plans[1].accountIDs == original.plans[1].accountIDs)
        #expect(try ConfigurationStore(directories: model.directories).load() == model.configuration)
    }

    @Test("saving a client editor draft preserves accounts changed since the editor opened")
    @MainActor
    func clientDraftPreservesLatestAccounts() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        var draft = model.configuration.clients[0]
        draft.name = "修改后的客户端"
        let account = model.newAccountDraft(clientID: draft.id)
        #expect(model.saveAccountDraft(account, clientID: draft.id, isNew: true, planIDs: []) == nil)
        let currentAccounts = model.configuration.clients[0].accounts

        #expect(model.saveClientDraft(draft, isNew: false) == nil)

        #expect(model.configuration.clients[0].name == draft.name)
        #expect(model.configuration.clients[0].accounts == currentAccounts)
        #expect(try ConfigurationStore(directories: model.directories).load() == model.configuration)
    }

    @Test("entity saves detect a background run that started after the editor opened", arguments: [false, true])
    @MainActor
    func entityDraftRejectsNewBackgroundRun(clientEditor: Bool) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        #expect(model.saveNow(showConfirmation: false))
        let original = model.configuration
        var clientDraft = original.clients[0]
        clientDraft.name = "运行中修改"
        var accountDraft = clientDraft.accounts[0]
        accountDraft.name = "运行中修改"
        let lock = try ProcessLock(url: model.directories.lock)
        defer { withExtendedLifetime(lock) {} }
        #expect(!model.isExternalRunActive)

        let error = clientEditor
            ? model.saveClientDraft(clientDraft, isNew: false)
            : model.saveAccountDraft(accountDraft, clientID: clientDraft.id, isNew: false, planIDs: [])

        #expect(error?.contains("运行期间") == true)
        #expect(model.isExternalRunActive)
        #expect(model.configuration == original)
        #expect(try ConfigurationStore(directories: model.directories).load() == original)
    }

    @Test("reset detects a new background run and preserves checkpoints until the run ends")
    @MainActor
    func resetTodayRejectsNewBackgroundRun() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        configureReadyClient(model, root: root)
        let client = model.configuration.clients[0]
        let account = client.accounts[0]
        let planID = model.configuration.plans[0].id
        let completedStep = WorkflowStep(planID: planID, clientID: client.id, accountID: account.id, task: .award)
        let fightStep = WorkflowStep(planID: planID, clientID: client.id, accountID: account.id, task: .fight)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey, completedSteps: [completedStep.key])
        state.record(FightResult(status: .unconfirmed, reason: .interruptedBattle), for: fightStep.key)
        let store = ExecutionStateStore(directories: model.directories)
        try store.save(state)
        model.reloadActivityHistory()
        let savedState = model.executionState
        let savedData = try Data(contentsOf: model.directories.executionState)
        var lock: ProcessLock? = try ProcessLock(url: model.directories.lock)
        defer { withExtendedLifetime(lock) {} }
        #expect(!model.isWorkflowRunning)

        model.resetToday()

        #expect(model.isExternalRunActive)
        #expect(model.executionState == savedState)
        #expect(try Data(contentsOf: model.directories.executionState) == savedData)
        #expect(model.feedback.notice?.message.contains("运行期间不能重置今日完成记录") == true)

        lock = nil
        model.resetToday()

        #expect(!model.isWorkflowRunning)
        #expect(model.executionState.completedSteps.isEmpty)
        #expect(model.executionState.fightResults == nil)
        #expect(try store.loadForExecution() == model.executionState)
        #expect(model.feedback.notice?.message == "今日完成记录已重置")
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "automaa-workspace-\(UUID())")
    }

    @MainActor
    private func makeModel(root: URL) -> AppModel {
        AppModel(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents"),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            allowsAutomaticMAAMaintenance: false,
            runnerExecutableURL: URL(filePath: "/usr/bin/true")
        )
    }

    @MainActor
    private func configureReadyClient(_ model: AppModel, root: URL) {
        model.configuration.cliPath = "/usr/bin/true"
        model.configuration.clients = [ClientConfiguration(
            name: "测试客户端", kind: .official, appPath: root.appending(path: "Test.app").path,
            address: "127.0.0.1:61391", profileName: "workspace-test", bundleIdentifier: "dev.automaa.tests.workspace",
            accounts: [AccountConfiguration(name: "测试账号")]
        )]
    }

    @MainActor
    private func waitForScheduleSynchronization(_ model: AppModel) async throws {
        for _ in 0..<100 where model.isSynchronizingSchedules {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isSynchronizingSchedules)
    }

    private func configurationFixture(root: URL, emptyOptionalValues: Bool) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.schemaSevenConfiguration.utf8)) as? [String: Any])
        var clients = try #require(object["clients"] as? [[String: Any]])
        clients[0]["appPath"] = root.appending(path: "Fixture.app").path
        object["clients"] = clients
        if emptyOptionalValues {
            var plans = try #require(object["plans"] as? [[String: Any]])
            var fight = try #require(plans[0]["fight"] as? [String: Any])
            for field in ["medicine", "medicineExpireDays", "stone", "times", "series"] {
                fight.removeValue(forKey: field)
            }
            plans[0]["fight"] = fight
            object["plans"] = plans
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static let schemaSevenConfiguration = #"""
    {
      "schemaVersion": 7,
      "cliPath": "/usr/bin/true",
      "clients": [{
        "id": "D410442B-B919-4D75-9FE4-74C44EA6CCAA", "name": "测试客户端", "kind": "official",
        "appPath": "Fixture.app", "address": "127.0.0.1:61392", "profileName": "workspace-fixture",
        "bundleIdentifier": "dev.automaa.tests.fixture", "enabled": true,
        "accounts": [{"id": "E2734632-C9E0-4FA0-B23A-21A72BEAA833", "name": "测试账号", "accountSelector": "", "enabled": true}]
      }],
      "plans": [{
        "id": "8C5A3BD6-9329-4D8E-B7A6-650275C6BC0D", "name": "已保存方案",
        "includesAllEnabledAccounts": false, "accountIDs": ["E2734632-C9E0-4FA0-B23A-21A72BEAA833"],
        "stepOrder": ["recruit", "fight", "infrast", "mall", "award"],
        "fight": {
          "enabled": true, "settingsMode": "custom", "stageStrategy": "fixed", "stage": "CE-6", "fallbackStage": "1-7",
          "weeklyAnnihilation": {"enabled": true, "startDay": "wednesday"},
          "medicine": 0, "medicineExpireDays": 2, "stone": 0, "times": 23, "series": -1, "drGrandet": true
        },
        "recruit": {
          "enabled": true, "settingsMode": "custom", "refresh": false, "times": 7, "expedite": true,
          "autoConfirm3": false, "autoConfirm4": true, "autoConfirm5": true, "autoConfirm6": true,
          "firstTags": ["治疗", "输出"], "extraTagsMode": 2, "preserveTags": ["支援机械", "高级资深干员"]
        },
        "infrast": {
          "enabled": true, "settingsMode": "custom", "mode": 20000, "facilities": ["Trade", "Mfg", "Reception"],
          "drones": "PureGold", "threshold": 0.65, "replenish": true, "dormNotStationed": true, "dormTrust": true,
          "receptionMessageBoard": false, "receptionClueExchange": true, "receptionSendClue": false,
          "continueTraining": false, "customSchedulePath": "retained-schedule.json", "customSchedulePlanIndex": 3
        },
        "mall": {
          "enabled": false, "settingsMode": "custom", "visitFriends": false, "shopping": false,
          "buyFirst": ["龙门币", "招聘许可"], "blacklist": ["碳"], "forceShoppingIfCreditFull": false,
          "onlyBuyDiscount": true, "reserveMaxCredit": true, "creditFight": true, "formationIndex": 4
        },
        "award": {
          "enabled": true, "settingsMode": "custom", "dailyWeekly": false, "mail": true,
          "freeRecruit": true, "orundum": true, "mining": true, "specialAccess": true
        },
        "schedule": {"enabled": false, "rules": [{"id": "708B9BE4-4C29-4D61-A4DC-A456F97B6C29", "weekdays": ["monday", "friday"], "hour": 19, "minute": 35}]},
        "policy": {"hotUpdateBeforeRun": false, "maxRetries": 3, "continueAfterStepFailure": false}
      }],
      "notifications": {"importantEventsEnabled": true},
      "applicationUpdates": {"automaticallyDownloadsUpdates": false},
      "maaUpdates": {"automaticallyUpdatesCoreAndResources": false}
    }
    """#
}
