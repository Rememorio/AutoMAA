import AutoMAAKit
import Combine
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity workspace")
struct ActivityWorkspaceTests {
    @Test("pending work navigation selects its plan even when a filtered historical record was selected")
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

        #expect(model.selection == .activity)
        #expect(model.activitySelection == .plan(planID))
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
        #expect(model.selection == .activity)
        #expect(model.activitySelection == (maintenance ? .maintenance : .plan(planID)))
        #expect(model.activitySearch.isEmpty)
        #expect(model.activityFilter == .all)
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
