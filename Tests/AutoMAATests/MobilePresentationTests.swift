import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Mobile workflow presentation")
struct MobilePresentationTests {
    @Test("revision ignores timestamps and collection storage order")
    @MainActor
    func revisionIsSemanticAndStable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        let ids = (0..<12).map { _ in UUID() }
        let completed = (0..<12).map { "completed-\($0)" }
        model.configuration.plans[0].accountIDs = Set(ids)
        let store = ExecutionStateStore(directories: model.directories)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey,
                                   completedSteps: Set(completed), updatedAt: Date(timeIntervalSince1970: 1))
        try store.save(state)
        model.reloadActivityHistory()
        let first = try model.mobileRevision()
        #expect(try model.mobileRevision() == first)
        state.updatedAt = Date(timeIntervalSince1970: 60)
        try store.save(state)
        model.reloadActivityHistory()
        #expect(try model.mobileRevision() == first)
        for _ in 0..<12 {
            model.configuration.plans[0].accountIDs = Set(ids.shuffled())
            state.completedSteps = Set(completed.shuffled())
            try store.save(state)
            model.reloadActivityHistory()
            #expect(try model.mobileRevision() == first)
        }
        model.configuration.plans[0].name += " changed"
        let renamed = try model.mobileRevision()
        #expect(renamed != first)
        state.completedSteps.insert(WorkflowStep(planID: fixture.plan.id, clientID: fixture.client.id,
                                                accountID: fixture.account.id, task: .award).key)
        try store.save(state)
        model.reloadActivityHistory()
        #expect(try model.mobileRevision() != renamed)
    }

    @Test("an empty daily state keeps the same revision when reloaded later")
    @MainActor
    func emptyStateRevisionDoesNotExpireOnEveryRefresh() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        _ = configure(model, root: root)
        let first = try model.mobileRevision()
        try await Task.sleep(for: .milliseconds(1100))
        model.reloadActivityHistory()
        #expect(try model.mobileRevision() == first)
    }

    @Test("revision tracks daily resets, weekly results and remembered fight targets")
    @MainActor
    func revisionTracksExecutionInputs() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        let stateStore = ExecutionStateStore(directories: model.directories)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey, completedSteps: ["completed"])
        try stateStore.save(state)
        model.reloadActivityHistory()
        let completed = try model.mobileRevision()
        state.dateKey = "1900-01-01"
        try stateStore.save(state)
        model.reloadActivityHistory()
        #expect(try model.mobileRevision() != completed)
        try stateStore.save(ExecutionState(dateKey: ExecutionStateStore.todayKey))
        model.reloadActivityHistory()
        let daily = try model.mobileRevision()
        var weekly = WeeklyAnnihilationState()
        weekly.record(.init(status: .completed), client: fixture.client, accountID: fixture.account.id,
                      weekStart: GameWeek(client: fixture.client.kind, at: Date()).start)
        try WeeklyAnnihilationStore(directories: model.directories).save(weekly)
        model.reloadActivityHistory()
        let weeklyRevision = try model.mobileRevision()
        #expect(weeklyRevision != daily)
        var memory = FightStageMemory()
        memory.remember("1-7", clientID: fixture.client.id, accountID: fixture.account.id)
        try FightStageMemoryStore(directories: model.directories).save(memory)
        model.reloadActivityHistory()
        #expect(try model.mobileRevision() != weeklyRevision)
    }

    @Test("snapshots expose only presentation data and redact every dynamic text field")
    @MainActor
    func snapshotWhitelistAndRedaction() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        let sensitive = "fixture-selector-42"
        let email = "test@example.invalid"
        model.configuration.clients[0].accounts[0].accountSelector = sensitive
        model.configuration.clients[0].accounts[0].name = "Account \(sensitive) \(email)"
        model.configuration.clients[0].name = "Client \(sensitive)"
        model.configuration.plans[0].name = "Plan \(sensitive)"
        model.configuration.plans[0].fight.enabled = true
        model.configuration.plans[0].fight.stageStrategy = .fixed
        model.configuration.plans[0].fight.stage = sensitive
        model.configuration.plans[0].fight.medicine = 2
        model.configuration.plans[0].fight.stone = 0
        model.statusMessage = "Status \(sensitive) \(email)"
        model.progress = .infinity
        model.activityEntries = [LogEntry(level: .error, message: "Failure \(sensitive)", planID: fixture.plan.id,
                                           clientID: fixture.client.id, accountID: fixture.account.id, task: .award)]
        let snapshot = model.mobileSnapshot(hostID: UUID(), sessionID: UUID(), hostName: "Mac \(sensitive)")
        let data = try MobileProtocol.encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(sensitive))
        #expect(!text.contains(email))
        #expect(!text.contains(fixture.client.profileName))
        #expect(!text.contains(fixture.client.bundleIdentifier))
        #expect(!text.contains(fixture.client.appPath))
        #expect(!text.contains(fixture.client.address))
        #expect(snapshot.progress == 0)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == Set(["hostID", "sessionID", "hostName", "appVersion", "updatedAt", "revision",
                                      "busy", "stopping", "phase", "message", "progress", "canStop", "plans"]))
        let plans = try #require(json["plans"] as? [[String: Any]])
        #expect(Set(try #require(plans.first).keys) == Set(["id", "name", "accounts", "tasks", "parameters", "schedule",
                                                         "action", "canRun", "pending", "warnings"]))
        #expect(!snapshot.plans[0].accounts.isEmpty)
        #expect(snapshot.plans[0].parameters.contains { $0.contains("理智药：2") && $0.contains("源石：0") })
    }

    @Test("large plan collections remain below the websocket reply limit and disclose omissions")
    @MainActor
    func largeSnapshotsStayBounded() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        _ = configure(model, root: root)
        model.configuration.clients[0].accounts[0].name = String(repeating: "测", count: 2000)
        model.configuration.plans = (0..<100).map { index in
            var plan = model.configuration.plans[0]
            plan.id = UUID()
            plan.name = "Plan \(index)"
            return plan
        }
        let value = snapshot(model)
        #expect(!value.plans.isEmpty)
        #expect(value.plans.count < 100)
        #expect(value.message.contains("更多内容请在 Mac 查看"))
        var reply = MobileReply(type: "snapshot")
        reply.snapshot = value
        #expect(try MobileProtocol.encode(reply).count < 1024 * 1024)
    }

    @Test("recommended fight settings do not present retained custom values as active")
    @MainActor
    func recommendedParametersExcludeInactiveValues() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        _ = configure(model, root: root)
        model.configuration.plans[0].fight.enabled = true
        model.configuration.plans[0].fight.stageStrategy = .fixed
        model.configuration.plans[0].fight.stage = "CE-6"
        model.configuration.plans[0].fight.medicine = 17
        model.configuration.plans[0].fight.stone = 9
        model.configuration.plans[0].fight.settingsMode = .maaDefault
        let parameters = snapshot(model).plans[0].parameters.joined(separator: "\n")
        #expect(parameters.contains("MAA 推荐参数"))
        #expect(!parameters.contains("CE-6"))
        #expect(!parameters.contains("固定关卡"))
        #expect(!parameters.contains("理智药：17"))
        #expect(!parameters.contains("源石：9"))
    }

    @Test("history list and details use bounded stable cursors and redact log content")
    @MainActor
    func historyPaginationAndRedaction() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        let secret = "fixture-selector-42"
        model.configuration.clients[0].accounts[0].accountSelector = secret
        model.configuration.plans[0].name = "Plan \(secret)"
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        model.activityEntries = (0..<45).map { index in
            LogEntry(timestamp: epoch.addingTimeInterval(Double(index)), level: .success, message: "Completed",
                     runID: UUID(), phase: .completed, planID: fixture.plan.id)
        }
        let first = try model.mobileHistory(.init(operation: .history))
        #expect(first.history?.count == 20)
        #expect(first.history?.contains { $0.title.contains(secret) } == false)
        var request = MobileRequest(operation: .history)
        let firstCursor: String = try #require(first.next)
        request.before = firstCursor
        let second = try model.mobileHistory(request)
        #expect(second.history?.count == 20)
        let secondCursor: String = try #require(second.next)
        request.before = secondCursor
        let third = try model.mobileHistory(request)
        #expect(third.history?.count == 5)
        #expect(third.next == nil)
        #expect(Set([first, second, third].flatMap { $0.history?.map(\.id) ?? [] }).count == 45)
        request.before = "missing"
        #expect(throws: MobileAccessError.self) { try model.mobileHistory(request) }

        let runID = UUID()
        model.activityEntries = (0..<65).map { index in
            LogEntry(timestamp: epoch.addingTimeInterval(Double(index)), level: .warning,
                     message: "Event \(index) \(secret) test@example.invalid",
                     details: "Details \(secret)", runID: runID, phase: .runningTask, planID: fixture.plan.id)
        }
        let summary = try model.mobileHistory(.init(operation: .history))
        let item = try #require(summary.history?.first)
        #expect(item.hasAttention)
        #expect(!item.failed)
        #expect(item.status == "未记录结束")
        request = MobileRequest(operation: .historyDetails)
        request.historyID = item.id
        var ids: [UUID] = []
        for expected in [30, 30, 5] {
            let page = try model.mobileHistory(request)
            #expect(page.events?.count == expected)
            let text = String(decoding: try MobileProtocol.encode(page), as: UTF8.self)
            #expect(!text.contains(secret))
            #expect(!text.contains("test@example.invalid"))
            ids += page.events?.map(\.id) ?? []
            request.before = page.next
        }
        #expect(request.before == nil)
        #expect(Set(ids).count == 65)
        #expect(ids == model.activityEntries.reversed().map(\.id))
        request.before = "invalid-cursor"
        #expect(throws: MobileAccessError.self) { try model.mobileHistory(request) }
        request.before = nil
        request.historyID = "missing-session"
        #expect(throws: MobileAccessError.self) { try model.mobileHistory(request) }
    }

    @Test("legacy history without an active run is not labelled as running")
    @MainActor
    func legacyHistoryHasNoFalseActiveRun() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        model.activityEntries = [LogEntry(level: .success, message: "Completed", phase: .completed, planID: fixture.plan.id)]
        let reply = try model.mobileHistory(.init(operation: .history))
        #expect(reply.history?.first?.status == "已完成")
        #expect(!snapshot(model).busy)
    }

    @Test("same-timestamp history sessions have deterministic pagination")
    @MainActor
    func equalTimestampHistoryOrderIsStable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        _ = configure(model, root: root)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        model.activityEntries = (0..<45).map { _ in
            LogEntry(timestamp: timestamp, level: .success, message: "Completed", runID: UUID(), phase: .completed)
        }
        let first = try model.mobileHistory(.init(operation: .history))
        for _ in 0..<8 {
            let repeated = try model.mobileHistory(.init(operation: .history))
            #expect(repeated.history?.map(\.id) == first.history?.map(\.id))
        }
        var request = MobileRequest(operation: .history)
        request.before = first.next
        let second = try model.mobileHistory(request)
        request.before = second.next
        let third = try model.mobileHistory(request)
        #expect(Set([first, second, third].flatMap { $0.history?.map(\.id) ?? [] }).count == 45)
    }

    @Test("invalid configuration, completed scope and stale revision never launch a workflow")
    @MainActor
    func rejectedRunsHaveNoSideEffects() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        let store = ExecutionStateStore(directories: model.directories)
        let step = WorkflowStep(planID: fixture.plan.id, clientID: fixture.client.id, accountID: fixture.account.id, task: .award)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey, completedSteps: [step.key])
        try store.save(state)
        model.reloadActivityHistory()
        #expect(model.canRun(planID: fixture.plan.id))
        #expect(model.continuation(for: fixture.plan.id).pending == 0)
        var request = MobileRequest(operation: .run)
        request.planID = fixture.plan.id
        request.revision = try model.mobileRevision()
        #expect(throws: MobileAccessError.self) { try model.performMobileCommand(request) }
        #expect(!model.isWorkflowRunning)
        #expect(!snapshot(model).plans[0].canRun)

        state.completedSteps = []
        try store.save(state)
        model.reloadActivityHistory()
        model.configuration.plans[0].name = ""
        request.revision = try model.mobileRevision()
        #expect(throws: MobileAccessError.self) { try model.performMobileCommand(request) }
        #expect(!model.isWorkflowRunning)
        #expect(!snapshot(model).plans[0].canRun)

        model.configuration.plans[0].name = "Mobile test plan"
        #expect(model.canRun(planID: fixture.plan.id))
        #expect(model.continuation(for: fixture.plan.id).pending == 1)
        request.revision = "stale-revision"
        #expect(throws: MobileAccessError.self) { try model.performMobileCommand(request) }
        #expect(!model.isRunning)
        #expect(model.runningPlanID == nil)
        #expect(model.activeRunID == nil)
        #expect(!FileManager.default.fileExists(atPath: model.directories.lock.path))
        #expect(model.activityEntries.isEmpty)
    }

    @Test("safe stop requires the exact active run and does not stop a later execution")
    @MainActor
    func safeStopMatchesAllIdentityFields() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = configure(model, root: root)
        let lock = try ProcessLock(url: model.directories.lock)
        let control = WorkflowRunControl(directories: model.directories)
        let current = WorkflowRunIdentity(runID: UUID(), planID: fixture.plan.id, lockID: lock.identity)
        try control.activate(current)
        defer { control.finish(current); withExtendedLifetime(lock) {} }
        model.reloadActivityHistory()
        #expect(snapshot(model).canStop)
        var request = MobileRequest(operation: .stop)
        for wrong in [WorkflowRunIdentity(runID: UUID(), planID: current.planID, lockID: current.lockID),
                      WorkflowRunIdentity(runID: current.runID, planID: UUID(), lockID: current.lockID),
                      WorkflowRunIdentity(runID: current.runID, planID: current.planID, lockID: UUID())] {
            request.run = wrong
            #expect(throws: WorkflowRunControlError.self) { try model.performMobileCommand(request) }
            #expect(!control.isStopRequested(for: current))
        }
        request.run = current
        _ = try model.performMobileCommand(request)
        #expect(control.isStopRequested(for: current))
        #expect(snapshot(model).stopping)
        #expect(!snapshot(model).canStop)
        control.finish(current)
        let later = WorkflowRunIdentity(runID: UUID(), planID: current.planID, lockID: current.lockID)
        try control.activate(later)
        defer { control.finish(later) }
        #expect(throws: WorkflowRunControlError.self) { try model.performMobileCommand(request) }
        #expect(!control.isStopRequested(for: later))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "automaa-mobile-presentation-\(UUID())")
    }

    @MainActor
    private func makeModel(root: URL) -> AppModel {
        AppModel(directories: AppDirectories(root: root), launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                 managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false, allowsAutomaticMAAMaintenance: false)
    }

    @MainActor
    private func configure(_ model: AppModel, root: URL) -> (client: ClientConfiguration, account: AccountConfiguration, plan: AutomationPlan) {
        let account = AccountConfiguration(name: "Mobile test account")
        let client = ClientConfiguration(name: "Mobile test client", kind: .yoStarJP,
                                         appPath: root.appending(path: "Fake.app").path, address: "127.0.0.1:65521",
                                         profileName: "mobile-presentation-test", bundleIdentifier: "dev.automaa.tests.mobile-presentation",
                                         accounts: [account])
        var plan = AutomationPlan(name: "Mobile test plan")
        plan.fight.enabled = false
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        return (client, account, plan)
    }

    @MainActor
    private func snapshot(_ model: AppModel) -> MobileSnapshot {
        model.mobileSnapshot(hostID: UUID(), sessionID: UUID(), hostName: "Test Mac")
    }
}
