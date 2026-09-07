import Foundation
import XCTest
@testable import AutoMAAKit

private func command(_ output: String = "", exit: Int32 = 0, timeout: Bool = false, cancelled: Bool = false) -> CommandResult {
    CommandResult(exitCode: exit, standardOutput: output, standardError: "", timedOut: timeout, cancelled: cancelled)
}

private func callback(_ kind: String, _ payload: String) -> String {
    "[test] Assistant::append_callback | \(kind) \(payload)"
}

private let battleStart = callback("SubTaskStart", #"{"taskchain":"Fight","first":["FightBegin"],"details":{"task":"StartButton2"}}"#)
private let stageDrops = callback("SubTaskExtraInfo", #"{"taskchain":"Fight","what":"StageDrops","details":{"stage":{"stageCode":"1-7"},"cur_times":1,"drops":[]}}"#)
private let noSanity = callback("SubTaskStart", #"{"taskchain":"Fight","first":["FightBegin"],"details":{"task":"NoStone"}}"#)
private let noAnnihilation = callback("SubTaskError", #"{"taskchain":"Fight","first":["Annihilation"],"pre_task":""}"#)

private func settlementCallbacks(stage: String?, kind: FightKind?, times: Int = 1, weeklyProgress: [Int]? = nil) throws -> String {
    var lines: [String] = []
    var completion: String?
    if let kind {
        let task = kind == .annihilation ? "EndOfActionAnnihilation" : "EndOfAction"
        let event: [String: Any] = ["taskchain": "Fight", "subtask": "ProcessTask", "details": ["task": task]]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
        lines.append(callback("SubTaskStart", payload))
        completion = callback("SubTaskCompleted", payload)
    }
    var details: [String: Any] = ["stage": stage.map { ["stageCode": $0] } ?? [:], "cur_times": times, "drops": []]
    if let weeklyProgress { details["annihilation_weekly_process"] = weeklyProgress }
    let event: [String: Any] = ["taskchain": "Fight", "what": "StageDrops", "details": details]
    lines.append(callback("SubTaskExtraInfo", String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)))
    if let completion { lines.append(completion) }
    return lines.joined(separator: "\n")
}

final class FightExecutionTests: XCTestCase {
    func testAnnihilationClassificationDoesNotDependOnServerLanguageOrWeeklyOCR() throws {
        for name in FightStageMemoryTests.mapNames {
            for progress: [Int]? in [nil, [320, 1800], [1800, 1800]] {
                var observation = FightObservation()
                let callbacks = try settlementCallbacks(stage: name, kind: .annihilation, weeklyProgress: progress)
                callbacks.components(separatedBy: "\n").forEach { observation.consume($0) }
                let result = observation.result(for: command(), configuredStage: "")
                XCTAssertEqual(result.kind, .annihilation, name)
                XCTAssertEqual(result.status, .completed)
                XCTAssertEqual(result.reason, progress == [1800, 1800] ? .weeklyLimit : nil)
                let clientID = UUID(), accountID = UUID()
                var memory = FightStageMemory(entries: [.init(clientID: clientID, accountID: accountID, stage: "1-7")])
                XCTAssertTrue(memory.recordSuccessfulFight(result, clientID: clientID, accountID: accountID))
                XCTAssertEqual(memory.stage(clientID: clientID, accountID: accountID), "1-7")
                XCTAssertTrue(memory.requiresRecovery(clientID: clientID, accountID: accountID))
            }
        }
    }

    func testWeeklyProgressIdentifiesAnnihilationBeforeTheCapWithoutSettlementTask() throws {
        var observation = FightObservation()
        let lines = try settlementCallbacks(stage: "Unknown map", kind: nil, weeklyProgress: [320, 1800])
        lines.components(separatedBy: "\n").forEach { observation.consume($0) }
        let result = observation.result(for: command(), configuredStage: nil)
        XCTAssertEqual(result.kind, .annihilation)
        XCTAssertNil(result.reason)
    }

    func testRegularClassificationRequiresItsOwnSettlementAndNeverUsesSummaryStage() throws {
        var observation = FightObservation()
        for (stage, kind): (String?, FightKind?) in [("1-7", .regular), ("CE-6", nil), (nil, .regular)] {
            let lines = try settlementCallbacks(stage: stage, kind: kind)
            lines.components(separatedBy: "\n").forEach { observation.consume($0) }
            let result = observation.result(for: command("Fight SR-6 3 times"), configuredStage: "SR-6")
            XCTAssertEqual(result.kind, kind)
            XCTAssertEqual(result.stage, stage)
        }
    }

    func testUnrelatedAndIncompleteSettlementEventsCannotClassifyRegularFight() throws {
        let completed = callback("SubTaskStart", #"{"taskchain":"Fight","subtask":"ProcessTask","details":{"task":"Fight@EndOfAction"}}"#)
        for line in [completed.replacingOccurrences(of: "SubTaskStart", with: "SubTaskCompleted"),
                     completed.replacingOccurrences(of: "\"Fight\"", with: "\"Mall\""),
                     completed.replacingOccurrences(of: "ProcessTask", with: "OtherPlugin")] {
            var observation = FightObservation()
            observation.consume(line)
            observation.consume(stageDrops)
            XCTAssertNil(observation.result(for: command(), configuredStage: "1-7").kind)
        }
    }

    func testOldResultsRemainUnknownAndNewKindsRoundTrip() throws {
        let old = try JSONDecoder().decode(FightResult.self, from: Data(#"{"status":"completed","stage":"1-7","times":2}"#.utf8))
        XCTAssertNil(old.kind)
        for kind in [FightKind.regular, .annihilation] {
            let result = FightResult(status: .completed, stage: "1-7", times: 2, kind: kind)
            XCTAssertEqual(try JSONDecoder().decode(FightResult.self, from: JSONEncoder().encode(result)), result)
        }
    }

    func testExitZeroWithoutEvidenceIsUnconfirmed() {
        let result = FightObservation().result(for: command("Fight Completed"), configuredStage: "Annihilation")
        XCTAssertEqual(result.status, .unconfirmed)
        XCTAssertEqual(result.reason, .missingEvidence)
    }

    func testPositiveCLICountWithoutSettlementIsStillUnconfirmed() {
        let result = FightObservation().result(for: command("Fight 1-7 2 times"), configuredStage: nil)
        XCTAssertEqual(result.status, .unconfirmed)
        XCTAssertEqual(result.times, 0)
    }

    func testSettlementCountsAccumulateAcrossSeries() {
        var observation = FightObservation()
        observation.consume(stageDrops.replacingOccurrences(of: "\"cur_times\":1", with: "\"cur_times\":3"))
        observation.consume(battleStart)
        observation.consume(stageDrops.replacingOccurrences(of: "\"cur_times\":1", with: "\"cur_times\":2"))
        XCTAssertEqual(observation.result(for: command("Fight 1-7 7 times"), configuredStage: nil).times, 5)
    }

    func testSettledBattleIsCompletedAndKeepsActualStage() {
        var observation = FightObservation()
        observation.consume(battleStart)
        observation.consume(stageDrops)
        let result = observation.result(for: command(), configuredStage: "")
        XCTAssertEqual(result, FightResult(status: .completed, stage: "1-7", times: 1))
    }

    func testLaterUnsettledBattleOverridesEarlierCompletion() {
        var observation = FightObservation()
        observation.consume(stageDrops)
        observation.consume(battleStart)
        let result = observation.result(for: command("Fight 1-7 1 times"), configuredStage: nil)
        XCTAssertEqual(result.status, .unconfirmed)
        XCTAssertEqual(result.times, 1)
        XCTAssertEqual(result.reason, .interruptedBattle)
    }

    func testInterruptionOverridesPositiveSummary() {
        for result in [command("Fight 1-7 2 times", exit: 1), command("Fight 1-7 2 times", timeout: true),
                       command("Fight 1-7 2 times", cancelled: true), command("Fight 1-7 2 times\nGameOffline")] {
            XCTAssertEqual(FightObservation().result(for: result, configuredStage: nil).status, .unconfirmed)
        }
        XCTAssertEqual(FightObservation().result(for: command(exit: 1), configuredStage: nil).status, .failed)
    }

    func testMissingAnnihilationEntranceDoesNotProveWeeklyLimit() {
        var observation = FightObservation()
        observation.consume(noAnnihilation)
        observation.consume(callback("TaskChainCompleted", #"{"taskchain":"Fight"}"#))
        XCTAssertEqual(observation.result(for: command(), configuredStage: "Annihilation").reason, .navigationUnavailable)
        XCTAssertEqual(observation.result(for: command(), configuredStage: "Annihilation").status, .unconfirmed)
    }

    func testNoOpRequiresFightLoopOrExplicitWeeklyProgress() {
        var observation = FightObservation()
        observation.consume(noSanity.replacingOccurrences(of: "FightBegin", with: "StartUp"))
        XCTAssertEqual(observation.result(for: command(), configuredStage: nil).status, .unconfirmed)
        observation.consume(noSanity)
        XCTAssertEqual(observation.result(for: command(), configuredStage: nil).reason, .insufficientSanity)
        XCTAssertEqual(observation.result(for: command(), configuredStage: nil).status, .unnecessary)
        var weekly = FightObservation()
        weekly.consume(callback("SubTaskExtraInfo", #"{"taskchain":"Fight","what":"StageDrops","details":{"annihilation_weekly_process":[1800,1800]}}"#))
        XCTAssertEqual(weekly.result(for: command(), configuredStage: "Annihilation").reason, .weeklyLimit)
        XCTAssertEqual(weekly.result(for: command(), configuredStage: "Annihilation").status, .unnecessary)
    }

    func testUnrelatedMalformedAndOCRLinesCannotCompleteFight() {
        var observation = FightObservation()
        observation.consume(stageDrops.replacingOccurrences(of: "Fight", with: "Mall"))
        observation.consume("OCR: NoStone Annihilation StageDrops")
        observation.consume(callback("SubTaskExtraInfo", "{broken"))
        XCTAssertEqual(observation.result(for: command(), configuredStage: nil).status, .unconfirmed)
    }

    func testRotatedEvidenceIsReadInOrderAndOnlyCallbacksAreRetained() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "debug"), withIntermediateDirectories: true)
        try (battleStart + "\n").write(to: root.appending(path: "debug/asst.bak.log"), atomically: true, encoding: .utf8)
        try ("unrelated OCR text\n" + stageDrops + "\n").write(to: root.appending(path: "debug/asst.log"), atomically: true, encoding: .utf8)
        let evidence = FightCommandEvidence.read(from: root)
        XCTAssertEqual(evidence.observation.result(for: command(), configuredStage: nil).status, .completed)
        XCTAssertFalse(evidence.callbacks.contains("unrelated OCR text"))
    }

    func testOldConfigurationAndHistoryDecodeWithoutChangingSchema() throws {
        let data = Data(#"{"enabled":true,"settingsMode":"custom","stageStrategy":"fixed","stage":"1-7","drGrandet":false}"#.utf8)
        let configuration = try JSONDecoder().decode(FightConfiguration.self, from: data)
        XCTAssertFalse(configuration.annihilationFirst)
        XCTAssertEqual(configuration.stage, "1-7")
        let summary = try JSONDecoder().decode(WorkflowRunSummary.self, from: Data(#"{"completedSteps":1,"failedSteps":0,"unexecutedSteps":0,"totalSteps":1}"#.utf8))
        XCTAssertEqual(summary.unconfirmedSteps, 0)
        XCTAssertEqual(summary.unnecessarySteps, 0)
        XCTAssertEqual(AppConfiguration.currentSchemaVersion, 6)
    }

    func testNoOpDoesNotBecomeSuccessfulCheckpoint() throws {
        let key = "test"
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(FightResult(status: .unnecessary, reason: .insufficientSanity), for: key)
        XCTAssertTrue(state.isResolved(key))
        XCTAssertFalse(state.completedSteps.contains(key))
        state.record(FightResult(status: .unconfirmed), for: key)
        XCTAssertFalse(state.isResolved(key))
        XCTAssertTrue(state.needsFightConfirmation(key))
        var progress = FightProgress(regularStage: "1-7")
        progress.annihilation = FightResult(status: .completed, times: 1)
        state.fightProgress = [key: progress]
        XCTAssertFalse(state.needsFightConfirmation(key), "A regular phase that was never dispatched can safely resume")
        state.fightProgress?[key]?.regular = FightResult(status: .unconfirmed)
        XCTAssertTrue(state.needsFightConfirmation(key), "A dispatched phase requires explicit retry")
        XCTAssertEqual(try JSONDecoder().decode(ExecutionState.self, from: JSONEncoder().encode(state)), state)
    }
}

private actor FightTestCommands: CommandRunning {
    struct Reply: Sendable {
        var result: CommandResult
        var callbacks: String? = nil
    }
    struct Call: Sendable {
        let name: String
        let taskJSON: Data
        let statePath: String?
        let stateBeforeDispatch: ExecutionState
    }
    var replies: [Reply]
    var calls: [Call] = []
    let directories: AppDirectories
    let blockStateSave: Bool

    init(_ replies: [Reply], directories: AppDirectories, blockStateSave: Bool) {
        self.replies = replies
        self.directories = directories
        self.blockStateSave = blockStateSave
    }

    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool) async throws -> CommandResult {
        if arguments.first == "startup", blockStateSave {
            try FileManager.default.removeItem(at: directories.executionState)
            try FileManager.default.createDirectory(at: directories.executionState, withIntermediateDirectories: true)
        }
        guard arguments.first == "run" else { return command(exit: arguments.first == "dir" ? 1 : 0) }
        let name = arguments[1]
        let data = try Data(contentsOf: directories.maaConfig.appending(path: "tasks/\(name).json"))
        calls.append(Call(name: name, taskJSON: data, statePath: environment["MAA_STATE_DIR"],
                          stateBeforeDispatch: ExecutionStateStore(directories: directories).loadForToday()))
        let reply = replies.isEmpty ? Reply(result: command()) : replies.removeFirst()
        if let callbacks = reply.callbacks, let path = environment["MAA_STATE_DIR"] {
            let root = URL(filePath: path).appending(path: "debug")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try (callbacks + "\n").write(to: root.appending(path: "asst.log"), atomically: true, encoding: .utf8)
        } else {
            try writeFightSettlementFixture(reply.result, environment: environment)
        }
        return reply.result
    }

    func recordedCalls() -> [Call] { calls }
}

@MainActor
private final class FightTestRuntime: PortProbing, GameProcessControlling {
    var running = false
    var launches = 0
    var events: [RunnerEvent] = []
    func isOpen(_ value: String, observeCancellation: Bool) async -> Bool { running }
    func wait(forOpen: Bool, address: String, timeout: TimeInterval, observeCancellation: Bool) async -> Bool {
        if forOpen { running = true; launches += 1 }
        return running == forOpen
    }
    func isRunning(_ client: ClientConfiguration) -> Bool { running }
    func terminate(_ client: ClientConfiguration, force: Bool) -> Bool { running = false; return true }
    func record(_ event: RunnerEvent) { events.append(event) }
}

@MainActor
private final class FightFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "fight-tests-\(UUID())")
    let account = AccountConfiguration(name: "测试账号")
    var client: ClientConfiguration
    var plan = AutomationPlan.lightRoutine
    let runtime = FightTestRuntime()
    var directories: AppDirectories { AppDirectories(root: root) }
    var configuration: AppConfiguration { AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan]) }
    var step: WorkflowStep { WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight) }
    var state: ExecutionState { ExecutionStateStore(directories: directories).loadForToday() }

    init(priority: Bool = false, award: Bool = false) throws {
        let app = root.appending(path: "Test.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        client = ClientConfiguration(name: "测试客户端", kind: .yoStarJP, appPath: app.path,
                                     address: "127.0.0.1:65492", profileName: "fight-test",
                                     bundleIdentifier: "dev.automaa.tests.fight", accounts: [account])
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = award
        plan.fight.stageStrategy = .fixed
        plan.fight.stage = "1-7"
        plan.fight.annihilationFirst = priority
        plan.policy.hotUpdateBeforeRun = false
        plan.policy.maxRetries = 2
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func run(_ replies: [FightTestCommands.Reply], retry: Bool = false, confirm: Bool = false, blockStateSave: Bool = false) async -> (WorkflowReport, [FightTestCommands.Call]) {
        let commands = FightTestCommands(replies, directories: directories, blockStateSave: blockStateSave)
        let runner = WorkflowRunner(directories: directories, portProbe: runtime, gameController: runtime,
                                    shutdownPolicy: ClientShutdownPolicy(maaGracePeriod: 0, systemGracePeriod: 0, forcedGracePeriod: 0),
                                    commandRunner: commands, eventSink: runtime.record)
        let report = await runner.run(configuration, planID: plan.id, retryStep: retry ? step : nil, confirmAnnihilation: confirm)
        return (report, await commands.recordedCalls())
    }
}

@MainActor
final class FightWorkflowTests: XCTestCase {
    func testFollowingGameRecognizesAnnihilationAndRestoresRegularStageAcrossAllClients() async throws {
        let names: [ClientKind: String] = [.official: "切尔诺伯格", .bilibili: "切尔诺伯格", .txwy: "切爾諾伯格",
                                          .yoStarEN: "Chernobog", .yoStarJP: "カズデル", .yoStarKR: "체르노보그"]
        for kind in ClientKind.allCases {
            for strategy in [FightStageStrategy.gameCurrentOrLast, .rememberedRegular] {
                let fixture = try FightFixture()
                defer { fixture.cleanup() }
                fixture.client.kind = kind
                fixture.client.accounts[0].accountSelector = kind.supportsAccountSwitching ? "fixture-selector" : ""
                fixture.plan.fight.stageStrategy = strategy
                fixture.plan.fight.stage = ""
                let store = FightStageMemoryStore(directories: fixture.directories)
                var memory = FightStageMemory()
                memory.remember("1-7", clientID: fixture.client.id, accountID: fixture.account.id)
                try store.save(memory)
                let callbacks = try settlementCallbacks(stage: names[kind], kind: .annihilation)
                let (report, calls) = await fixture.run([.init(result: command(), callbacks: callbacks)])
                XCTAssertTrue(report.isSuccess, kind.rawValue)
                XCTAssertEqual(calls.count, 1)
                XCTAssertEqual(fixture.state.fightResults?[fixture.step.key]?.kind, .annihilation)
                memory = try store.load()
                XCTAssertEqual(memory.stage(clientID: fixture.client.id, accountID: fixture.account.id), "1-7")
                XCTAssertTrue(memory.requiresRecovery(clientID: fixture.client.id, accountID: fixture.account.id))
                if strategy == .rememberedRegular {
                    try ExecutionStateStore(directories: fixture.directories).save(.init(dateKey: ExecutionStateStore.todayKey))
                    let (restored, next) = await fixture.run([.init(result: command("Fight 1-7 1 times"))])
                    XCTAssertTrue(restored.isSuccess)
                    XCTAssertEqual(try parameters(XCTUnwrap(next.first))["stage"] as? String, "1-7")
                    XCTAssertFalse(try store.load().requiresRecovery(clientID: fixture.client.id, accountID: fixture.account.id))
                }
            }
        }
    }

    func testInvalidFrozenStageUsesCorrectedTargetWithoutRepeatingAnnihilation() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        var progress = FightProgress(regularStage: "カズデル")
        progress.annihilation = FightResult(status: .completed, times: 1, kind: .annihilation)
        progress.regular = FightResult(status: .failed)
        state.fightProgress = [fixture.step.key: progress]
        state.record(.init(status: .failed), for: fixture.step.key)
        try ExecutionStateStore(directories: fixture.directories).save(state)
        let (report, calls) = await fixture.run([.init(result: command("Fight 1-7 1 times"))])
        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(try parameters(XCTUnwrap(calls.first))["stage"] as? String, "1-7")
        XCTAssertEqual(fixture.state.fightProgress?[fixture.step.key]?.regularStage, "1-7")
    }

    func testPriorityRejectsMapNamesAsFixedRegularTargetsBeforeLaunching() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        for stage in FightStageMemoryTests.mapNames + ["_INVALID_"] {
            fixture.plan.fight.stage = stage
            let (report, calls) = await fixture.run([])
            XCTAssertNotNil(report.fatalError)
            XCTAssertTrue(calls.isEmpty)
            XCTAssertEqual(fixture.runtime.launches, 0)
        }
    }

    func testUnconfirmedFightStopsClientAndExplicitRetryOnlyRunsSelectedTask() async throws {
        let fixture = try FightFixture(award: true)
        defer { fixture.cleanup() }
        let (report, calls) = await fixture.run([.init(result: command())])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(report.unconfirmedSteps, 1)
        XCTAssertEqual(report.unexecutedSteps, 1)
        XCTAssertFalse(report.isSuccess)
        XCTAssertFalse(fixture.state.completedSteps.contains(fixture.step.key))
        XCTAssertFalse(fixture.runtime.running)
        let (continued, remaining) = await fixture.run([.init(result: command())])
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first?.name.hasSuffix("award") == true)
        XCTAssertEqual(continued.unconfirmedSteps, 1)
        let (retried, selected) = await fixture.run([.init(result: command("Fight 1-7 2 times"))], retry: true)
        XCTAssertTrue(retried.isSuccess)
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(fixture.state.completedSteps.contains(fixture.step.key))
        XCTAssertEqual(fixture.state.completedSteps.count, 2)
    }

    func testNoOpPersistsSeparatelyAndDoesNotRunAgain() async throws {
        let fixture = try FightFixture()
        defer { fixture.cleanup() }
        let (report, calls) = await fixture.run([.init(result: command(), callbacks: noSanity)])
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(report.unnecessarySteps, 1)
        XCTAssertEqual(report.runSummary?.completedSteps, 0)
        XCTAssertTrue(fixture.state.completedSteps.isEmpty)
        let (_, second) = await fixture.run([])
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(fixture.runtime.launches, 1)
        let (stale, repeated) = await fixture.run([], retry: true)
        XCTAssertNotNil(stale.fatalError)
        XCTAssertTrue(repeated.isEmpty)
        XCTAssertEqual(fixture.runtime.launches, 1)
    }

    func testPriorityFreezesRegularStageAndKeepsResourceLimitsInRegularPhase() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        fixture.plan.fight.stageStrategy = .gameCurrentOrLast
        fixture.plan.fight.medicine = 2
        fixture.plan.fight.stone = 1
        fixture.plan.fight.times = 4
        fixture.plan.fight.medicineExpireDays = 3
        var memory = FightStageMemory()
        memory.remember("1-7", clientID: fixture.client.id, accountID: fixture.account.id)
        try FightStageMemoryStore(directories: fixture.directories).save(memory)
        let (report, calls) = await fixture.run([.init(result: command("Fight Annihilation 1 times")), .init(result: command("Fight 1-7 4 times"))])
        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(calls.count, 2)
        let first = try parameters(calls[0])
        let second = try parameters(calls[1])
        XCTAssertEqual(first["stage"] as? String, "Annihilation")
        for field in ["medicine", "stone", "times", "medicine_expire_days"] { XCTAssertNil(first[field]) }
        XCTAssertEqual(second["stage"] as? String, "1-7")
        XCTAssertEqual(second["medicine"] as? Int, 2)
        XCTAssertEqual(second["stone"] as? Int, 1)
        XCTAssertEqual(second["times"] as? Int, 4)
        XCTAssertEqual(second["medicine_expire_days"] as? Int, 3)
        XCTAssertNotEqual(calls[0].statePath, calls[1].statePath)
        for call in calls {
            XCTAssertTrue(call.stateBeforeDispatch.needsFightConfirmation(fixture.step.key))
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(call.statePath)))
        }
        XCTAssertEqual(fixture.state.fightProgress?[fixture.step.key]?.regularStage, "1-7")
        XCTAssertEqual(fixture.state.fightResults?[fixture.step.key]?.times, 5)
        XCTAssertFalse(try FightStageMemoryStore(directories: fixture.directories).load().requiresRecovery(clientID: fixture.client.id, accountID: fixture.account.id))
    }

    func testRetryOfRegularPhaseDoesNotRepeatCompletedAnnihilation() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        let (failed, _) = await fixture.run([.init(result: command("Fight Annihilation 1 times")), .init(result: command(exit: 1))])
        XCTAssertEqual(failed.failedSteps, 1)
        XCTAssertFalse(fixture.state.isResolved(fixture.step.key))
        fixture.plan.fight.stage = "CE-6"
        let (resumed, calls) = await fixture.run([.init(result: command("Fight 1-7 1 times"))])
        XCTAssertTrue(resumed.isSuccess)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(try parameters(calls[0])["stage"] as? String, "1-7", "Retry uses the frozen stage")
    }

    func testMissingEntrancePausesUntilManualConfirmationThenOnlyRunsRegular() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        let (initial, calls) = await fixture.run([.init(result: command(), callbacks: noAnnihilation)])
        XCTAssertEqual(initial.unconfirmedSteps, 1)
        XCTAssertEqual(calls.count, 1)
        let (confirmed, remaining) = await fixture.run([.init(result: command("Fight 1-7 1 times"))], retry: true, confirm: true)
        XCTAssertTrue(confirmed.isSuccess)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(try parameters(remaining[0])["stage"] as? String, "1-7")
        XCTAssertEqual(fixture.state.fightProgress?[fixture.step.key]?.annihilation?.reason, .confirmedWeeklyLimit)
    }

    func testCancellationPreservesCompletedPhaseAndMarksDispatchedRegularUnknown() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        let (report, calls) = await fixture.run([.init(result: command("Fight Annihilation 1 times")), .init(result: command(cancelled: true))])
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(fixture.state.fightProgress?[fixture.step.key]?.annihilation?.isResolved == true)
        XCTAssertTrue(fixture.state.needsFightConfirmation(fixture.step.key))
        XCTAssertFalse(fixture.runtime.running)
        let (_, retry) = await fixture.run([.init(result: command("Fight 1-7 1 times"))], retry: true)
        XCTAssertEqual(retry.count, 1)
        XCTAssertEqual(try parameters(retry[0])["stage"] as? String, "1-7")
    }

    func testPriorityRequiresRegularStageAndRejectsAnnihilationAsFallback() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        fixture.plan.fight.stageStrategy = .gameCurrentOrLast
        let (missing, calls) = await fixture.run([])
        XCTAssertNotNil(missing.fatalError)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.runtime.launches, 0)
        fixture.plan.fight.stageStrategy = .fixed
        fixture.plan.fight.stage = "Annihilation"
        XCTAssertFalse(ConfigurationValidator.structuralProblems(in: fixture.configuration).isEmpty)
        let (invalid, _) = await fixture.run([])
        XCTAssertNotNil(invalid.fatalError)
        XCTAssertEqual(fixture.runtime.launches, 0)
    }

    func testManualWeeklyConfirmationRejectsOtherUnconfirmedResults() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        _ = await fixture.run([.init(result: command(timeout: true))])
        let (report, calls) = await fixture.run([], retry: true, confirm: true)
        XCTAssertNotNil(report.fatalError)
        XCTAssertTrue(calls.isEmpty)
    }

    func testContinuationIncludesUnattemptedFailuresAndIgnoresOtherDaysAndPlans() throws {
        let fixture = try FightFixture(award: true)
        defer { fixture.cleanup() }
        let entry = LogEntry(level: .info, message: "正在准备", phase: .preparing, planID: fixture.plan.id)
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        var continuation = PlanContinuation(configuration: fixture.configuration, planID: fixture.plan.id, state: state, history: [entry])
        XCTAssertTrue(continuation.hasStarted)
        XCTAssertEqual(continuation.pending, 2)
        state.record(FightResult(status: .unconfirmed), for: fixture.step.key)
        continuation = PlanContinuation(configuration: fixture.configuration, planID: fixture.plan.id, state: state, history: [])
        XCTAssertEqual(continuation.pending, 1)
        XCTAssertEqual(continuation.unconfirmed, 1)
        state.dateKey = "2000-01-01"
        continuation = PlanContinuation(configuration: fixture.configuration, planID: fixture.plan.id, state: state, history: [])
        XCTAssertEqual(continuation.pending, 2)
        XCTAssertFalse(continuation.hasStarted)
        XCTAssertEqual(PlanContinuation(configuration: fixture.configuration, planID: UUID(), state: state, history: []).pending, 0)
    }

    func testOnlyUnconfirmedWorkDoesNotLaunchClient() async throws {
        let fixture = try FightFixture()
        defer { fixture.cleanup() }
        _ = await fixture.run([.init(result: command())])
        let (report, calls) = await fixture.run([])
        XCTAssertEqual(report.unconfirmedSteps, 1)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.runtime.launches, 1)
    }

    func testUndispatchedRegularPhaseResumesWithoutRepeatingAnnihilation() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        var state = fixture.state
        state.record(FightResult(status: .unconfirmed), for: fixture.step.key)
        var progress = FightProgress(regularStage: "1-7")
        progress.annihilation = FightResult(status: .completed, stage: "Annihilation", times: 1)
        state.fightProgress = [fixture.step.key: progress]
        let otherKey = WorkflowStep(planID: UUID(), clientID: fixture.client.id, accountID: fixture.account.id, task: .fight).key
        state.completedSteps.insert(otherKey)
        try ExecutionStateStore(directories: fixture.directories).save(state)
        let (report, calls) = await fixture.run([.init(result: command("Fight 1-7 1 times"))])
        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(try parameters(calls[0])["stage"] as? String, "1-7")
        XCTAssertTrue(fixture.state.completedSteps.contains(otherKey))
    }

    func testUnreadableCheckpointStopsBeforeStartingGame() async throws {
        let fixture = try FightFixture()
        defer { fixture.cleanup() }
        try fixture.directories.prepare()
        try Data("invalid state".utf8).write(to: fixture.directories.executionState)
        let (report, calls) = await fixture.run([])
        XCTAssertNotNil(report.fatalError)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(fixture.runtime.launches, 0)
    }

    func testRecommendedModePreservesPriorityOptionWithoutRunningTwoPhases() async throws {
        let fixture = try FightFixture(priority: true)
        defer { fixture.cleanup() }
        fixture.plan.fight.usesCustomSettings = false
        let (report, calls) = await fixture.run([.init(result: command("Fight 1-7 1 times"))])
        XCTAssertTrue(report.isSuccess)
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(try parameters(calls[0])["stage"])
        XCTAssertTrue(fixture.plan.fight.annihilationFirst)
        XCTAssertNil(fixture.state.fightProgress)
    }

    func testCheckpointWriteFailurePreventsFightDispatchAndClosesClient() async throws {
        let fixture = try FightFixture()
        defer { fixture.cleanup() }
        let (report, calls) = await fixture.run([], blockStateSave: true)
        XCTAssertNotNil(report.fatalError)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(fixture.runtime.running)
    }

    func testIsolatedCallbacksAndFailureDetailsUseConfiguredRedaction() async throws {
        let fixture = try FightFixture()
        defer { fixture.cleanup() }
        fixture.client.kind = .official
        fixture.client.accounts[0].accountSelector = "fixture-private-token"
        let evidence = noAnnihilation.replacingOccurrences(of: "\"pre_task\":\"\"", with: "\"pre_task\":\"\",\"private\":\"fixture-private-token\"")
        _ = await fixture.run([.init(result: command("fixture-private-token user@example.com"), callbacks: evidence)])
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directories.logs, includingPropertiesForKeys: nil)
        let output = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertTrue(output.contains("Fight callbacks"))
        XCTAssertFalse(output.contains("fixture-private-token"))
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertFalse(fixture.runtime.events.contains { ($0.log.details ?? "").contains("fixture-private-token") })
    }

    private func parameters(_ call: FightTestCommands.Call) throws -> [String: Any] {
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: call.taskJSON) as? [String: Any])
        let tasks = try XCTUnwrap(document["tasks"] as? [[String: Any]])
        return try XCTUnwrap(tasks.first?["params"] as? [String: Any])
    }
}

func writeFightSettlementFixture(_ result: CommandResult, environment: [String: String]) throws {
    guard let path = environment["MAA_STATE_DIR"], result.exitCode == 0, !result.timedOut, !result.cancelled,
          let summary = MAAOutputSummaryParser.fightSummary(in: result.combinedOutput), summary.times > 0 else { return }
    let root = URL(filePath: path).appending(path: "debug")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let lines = try settlementCallbacks(stage: summary.stage,
        kind: FightStagePolicy.isAnnihilation(summary.stage) ? .annihilation : .regular, times: summary.times)
    try (lines + "\n").write(to: root.appending(path: "asst.log"), atomically: true, encoding: .utf8)
}
