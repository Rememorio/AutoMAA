import AutoMAAKit
import Combine
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity workspace")
struct ActivityWorkspaceTests {
    @Test("opening a plan's current round preserves the selected historical record and its filters")
    @MainActor
    func pendingWorkNavigationReplacesHistoricalSelection() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-activity-navigation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let planID = try #require(model.configuration.plans.last?.id)
        model.activitySelection = .session("previous-record")
        model.activitySearch = "保留的搜索"
        model.activityFilter = .failed

        model.showPlanActivity(planID)

        #expect(model.selection == .plan(planID))
        #expect(model.planActivityRequest == planID)
        #expect(model.activitySelection == .session("previous-record"))
        #expect(model.currentPlanID == planID)
        #expect(model.activitySearch == "保留的搜索")
        #expect(model.activityFilter == .failed)
        #expect(model.activityNavigationRequest == nil)
    }

    @Test("a local run starts without an old identity, adopts its first event and clears its identity on completion", arguments: [false, true])
    @MainActor
    func localRunIdentityFollowsItsOwnEvents(maintenance: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-activity-workspace-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let planID = try #require(model.configuration.plans.first?.id)
        let previousRunID = UUID()
        HistoryStore(directories: model.directories).append(LogEntry(
            timestamp: Date().addingTimeInterval(-60), level: .success, message: "上次运行完成",
            runID: previousRunID, phase: .completed, progress: 1, planID: planID
        ))
        model.reloadActivityHistory()
        #expect(model.activityEntries.last?.runID == previousRunID)
        #expect(model.canRun(planID: planID))

        var observedEvents: [(runID: UUID, activeRunID: UUID?, phase: RunnerPhase)] = []
        let observation = model.$activityEntries.sink { entries in
            guard model.isRunning, let entry = entries.last,
                  let runID = entry.runID, runID != previousRunID
            else { return }
            observedEvents.append((runID, model.activeRunID, model.activePhase))
        }
        defer { observation.cancel(); model.cancelRun() }

        if maintenance { model.hotUpdate() }
        else { model.runPlan(planID) }

        #expect(model.isRunning)
        #expect(model.activeRunID == nil)
        #expect(model.activePhase == .preparing)
        #expect(model.activeProgress == 0)
        #expect(model.activePlanID == (maintenance ? nil : planID))
        #expect(observedEvents.isEmpty)

        model.activitySelection = .session("previous-selection")
        model.activitySearch = "old record"
        model.activityFilter = .failed
        let selectedPlan = model.currentPlanID
        model.showCurrentActivity()
        if maintenance {
            #expect(model.settingsSection == .environment)
            #expect(model.activitySelection == .session("previous-selection"))
            #expect(model.activitySearch == "old record")
            #expect(model.activityFilter == .failed)
        } else {
            #expect(model.selection == .activity)
            #expect(model.activitySelection == .plan(planID))
            #expect(model.activitySearch.isEmpty)
            #expect(model.activityFilter == .all)
        }
        #expect(model.currentPlanID == selectedPlan)
        #expect(model.activityNavigationRequest == nil)

        // Cancel before yielding the main actor so no client or MAA command can start.
        model.cancelRun()
        for _ in 0..<500 where model.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!model.isRunning)

        let newRunID = try #require(observedEvents.first?.runID)
        #expect(newRunID != previousRunID)
        #expect(observedEvents.allSatisfy { $0.runID == newRunID && $0.activeRunID == newRunID })
        #expect(observedEvents.first?.phase == (maintenance ? .updating : .preparing))
        #expect(model.runningRunID == nil)
        #expect(model.activeRunID == nil)
        #expect(model.activePlanID == nil)
        #expect(model.activePhase == .cancelled)
        #expect(!ProcessLock.isHeld(at: model.directories.lock))
        #expect(!model.activityEntries.contains { $0.runID == newRunID && $0.phase == .launching })
        if !maintenance { #expect(model.lastReport?.cancelled == true) }
    }

    @Test("overview reviews a single account in place and opens the plan for multiple accounts")
    @MainActor
    func reviewOpensAtTheCorrectScope() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-review-scope-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        model.configuration.clients[0].accounts.append(.init(name: "第二个示例账号"))
        let client = model.configuration.clients[0]
        let plan = model.configuration.plans[0]
        let steps = client.accounts.map { WorkflowStep(planID: plan.id, clientID: client.id, accountID: $0.id, task: .fight) }
        let store = ExecutionStateStore(directories: model.directories)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        _ = state.startRound(for: plan.id, at: Date())
        let result = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle, kind: .regular)
        state.record(result, for: steps[0].key)
        try store.save(state)
        model.reviewFight(in: plan.id)
        guard case let .review(item) = model.fightRecoveryDestination else {
            Issue.record("应直接打开已选账号的核实窗口")
            return
        }
        #expect(item.step == steps[0])
        #expect(model.selection == .overview)
        #expect(!model.isWorkflowRunning)
        model.fightRecoveryDestination = nil
        state.record(result, for: steps[1].key)
        try store.save(state)
        model.reviewFight(in: plan.id)
        #expect(model.fightRecoveryDestination == nil)
        #expect(model.selection == .plan(plan.id))
        #expect(model.planActivityRequest == plan.id)
    }

    @Test("supplying a missing stage turns the prompt into ordinary resumable work")
    @MainActor
    func savedTargetClearsOnlyTheRepairPrompt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-recovery-target-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        model.configuration.plans[0].fight.usesCustomSettings = true
        model.configuration.plans[0].fight.stageStrategy = .rememberedRegular
        model.configuration.plans[0].fight.fallbackStage = ""
        let client = model.configuration.clients[0]
        let plan = model.configuration.plans[0]
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: client.accounts[0].id, task: .fight)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        let round = state.startRound(for: plan.id, at: Date())
        let failure = FightResult(status: .failed, reason: .missingRegularTarget, kind: .regular)
        state.record(failure, for: step.key)
        try ExecutionStateStore(directories: model.directories).save(state)
        model.reviewFight(in: plan.id)
        guard case let .stage(context) = model.fightRecoveryDestination else {
            Issue.record("应直接打开缺少关卡的账号表单")
            return
        }
        #expect(context.accountID == step.accountID)
        #expect(model.saveFightRecoveryStage("1-7", clientID: step.clientID, accountID: step.accountID) == nil)
        let progress = model.continuation(for: plan.id)
        #expect(progress.fightRecoveryItems.isEmpty)
        #expect(progress.resumableRoundID == round.id)
        #expect(progress.pendingItems.contains { $0.step == step && $0.reason == nil })
        #expect(model.executionState.fightResults?[step.key] == failure)
        #expect(!model.isWorkflowRunning)
    }

    @Test("a missing plan-fixed target opens the plan's fight settings")
    @MainActor
    func repairFixedTarget() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-fixed-target-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        model.configuration.plans[0].fight.usesCustomSettings = true
        model.configuration.plans[0].fight.stageStrategy = .fixed
        model.configuration.plans[0].fight.stage = "Annihilation"
        model.configuration.plans[0].fight.fallbackStage = ""
        model.configuration.plans[0].fight.weeklyAnnihilation.enabled = true
        let plan = model.configuration.plans[0], client = model.configuration.clients[0]
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: client.accounts[0].id, task: .fight)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        _ = state.startRound(for: plan.id, at: Date())
        let failure = FightResult(status: .failed, reason: .missingRegularTarget, kind: .regular)
        var progress = FightProgress(regularStage: "")
        progress.regular = failure
        state.fightProgress = [step.key: progress]
        state.record(failure, for: step.key)
        try ExecutionStateStore(directories: model.directories).save(state)

        model.reviewFight(in: plan.id)

        #expect(model.fightRecoveryDestination == nil)
        #expect(model.selection == .plan(plan.id))
        #expect(model.fightSettingsPlanID == plan.id)
        model.configuration.plans[0].fight.stage = "1-7"
        #expect(model.continuation(for: plan.id).fightRecoveryItems.isEmpty)
    }

    @Test("the plan inspector uses the matching active run instead of newer foreign history")
    func activeSnapshotKeepsPlanAndRunScope() {
        let planID = UUID()
        let current = session(planID: planID, at: 200, phase: .runningTask)
        let previous = session(planID: planID, at: 100)
        let foreign = session(planID: UUID(), at: 300, phase: .runningTask)
        let snapshot = ActivityPlanSnapshot(
            planID: planID, sessions: [foreign, current, previous], activePlanID: planID,
            activeRunID: current.runID, isWorkflowRunning: true
        )

        #expect(snapshot.isCurrent)
        #expect(snapshot.currentSession == current)
        #expect(snapshot.latestSession == previous)
        #expect(snapshot.displayedSession == current)
    }

    @Test("a different running plan leaves this plan on its own latest result")
    func anotherPlanRunningDoesNotReplaceHistory() {
        let planID = UUID()
        let previous = session(planID: planID, at: 100)
        let foreign = session(planID: UUID(), at: 200, phase: .runningTask)
        let snapshot = ActivityPlanSnapshot(
            planID: planID, sessions: [foreign, previous], activePlanID: foreign.planID,
            activeRunID: foreign.runID, isWorkflowRunning: true
        )

        #expect(!snapshot.isCurrent)
        #expect(snapshot.currentSession == nil)
        #expect(snapshot.latestSession == previous)
        #expect(snapshot.displayedSession == previous)
    }

    @Test("starting a plan never uses its previous result while waiting for the first event", arguments: [false, true])
    func startingSnapshotDoesNotFallBackToOldSession(hasAssignedRunID: Bool) {
        let planID = UUID()
        let previous = session(planID: planID, at: 100)
        let snapshot = ActivityPlanSnapshot(
            planID: planID, sessions: [previous], activePlanID: planID,
            activeRunID: hasAssignedRunID ? UUID() : nil, isWorkflowRunning: true
        )

        #expect(snapshot.isCurrent)
        #expect(snapshot.currentSession == nil)
        #expect(snapshot.latestSession == previous)
        #expect(snapshot.displayedSession == nil)
    }

    @Test("a matching run identity still cannot show another plan's session")
    func currentSessionRequiresMatchingPlan() {
        let planID = UUID()
        let previous = session(planID: planID, at: 100)
        let foreign = session(planID: UUID(), at: 200, phase: .runningTask)
        let snapshot = ActivityPlanSnapshot(
            planID: planID, sessions: [foreign, previous], activePlanID: planID,
            activeRunID: foreign.runID, isWorkflowRunning: true
        )

        #expect(snapshot.isCurrent)
        #expect(snapshot.currentSession == nil)
        #expect(snapshot.displayedSession == nil)
    }

    @Test("an idle plan shows its latest result even when old active identities remain in the input")
    func finishedSnapshotUsesLatestOwnResult() {
        let planID = UUID()
        let latest = session(planID: planID, at: 200)
        let older = session(planID: planID, at: 100)
        let maintenance = session(planID: nil, at: 300)
        let snapshot = ActivityPlanSnapshot(
            planID: planID, sessions: [maintenance, latest, older], activePlanID: planID,
            activeRunID: latest.runID, isWorkflowRunning: false
        )

        #expect(!snapshot.isCurrent)
        #expect(snapshot.currentSession == nil)
        #expect(snapshot.latestSession == latest)
        #expect(snapshot.displayedSession == latest)
    }

    @Test("a plan without history stays empty while another plan runs")
    func foreignHistoryDoesNotFillAnEmptyPlan() {
        let foreign = session(planID: UUID(), at: 100, phase: .runningTask)
        let snapshot = ActivityPlanSnapshot(
            planID: UUID(), sessions: [foreign], activePlanID: foreign.planID,
            activeRunID: foreign.runID, isWorkflowRunning: true
        )

        #expect(!snapshot.isCurrent)
        #expect(snapshot.currentSession == nil)
        #expect(snapshot.latestSession == nil)
        #expect(snapshot.displayedSession == nil)
    }

    private func session(planID: UUID?, at timestamp: TimeInterval, phase: RunnerPhase = .completed) -> ActivitySession {
        let runID = UUID()
        return ActivitySession(id: runID.uuidString, runID: runID, entries: [LogEntry(
            timestamp: Date(timeIntervalSince1970: timestamp), level: .info, message: "测试运行记录",
            runID: runID, phase: phase, planID: planID
        )])
    }

    @MainActor
    private func makeModel(root: URL) -> AppModel {
        let model = AppModel(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents"),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            allowsAutomaticMAAMaintenance: false,
            runnerExecutableURL: URL(filePath: "/usr/bin/true"),
            resourceProbeExecutable: URL(filePath: "/usr/bin/true")
        )
        model.configuration.cliPath = "/usr/bin/true"
        model.configuration.notifications.importantEventsEnabled = false
        model.configuration.clients = [ClientConfiguration(
            name: "测试客户端", kind: .official, appPath: root.appending(path: "Missing.app").path,
            address: "127.0.0.1:61392", profileName: "activity-workspace-test",
            bundleIdentifier: "dev.automaa.tests.activity-workspace", accounts: [AccountConfiguration(name: "测试账号")]
        )]
        model.configuration.plans[0].policy.hotUpdateBeforeRun = false
        return model
    }
}
