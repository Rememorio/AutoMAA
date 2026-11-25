import Foundation
import XCTest
@testable import AutoMAAKit

final class FightDropRecognitionTests: XCTestCase {
    private func callback(_ kind: String, _ fields: String = "") -> String {
        let extra = fields.isEmpty ? "" : "," + fields
        return #"Assistant::append_callback | \#(kind) {"taskchain":"Fight","taskid":1\#(extra)}"#
    }

    private func task(_ kind: String, _ name: String) -> String {
        callback(kind, #""subtask":"ProcessTask","first":["FightBegin"],"details":{"task":"Fight@\#(name)"}"#)
    }

    private func fightTimes(_ count: Int, series: Int) -> String {
        callback("SubTaskExtraInfo", #""subtask":"FightTimesTask","what":"FightTimes","details":{"times_finished":\#(count),"series":\#(series),"sanity_cost":\#(6 * series)}"#)
    }

    private func sanity(_ amount: Int) -> String {
        callback("SubTaskExtraInfo", #""subtask":"FightTimesTask","what":"SanityBeforeStage","details":{"current_sanity":\#(amount),"max_sanity":135}"#)
    }

    private var dropError: String {
        callback("SubTaskError", #""subtask":"RecognizeDrops","why":"drop recognition error""#)
    }

    private func recognizedDrops(_ count: Int) -> String {
        callback("SubTaskExtraInfo", #""what":"StageDrops","details":{"stage":{"stageCode":"1-7"},"cur_times":\#(count),"drops":[]}"#)
    }

    private var missingBatch: [String] {
        [callback("TaskChainStart"), sanity(90), fightTimes(0, series: 2), task("SubTaskStart", "StartButton2"),
         task("SubTaskStart", "EndOfAction"), dropError, task("SubTaskCompleted", "EndOfAction"),
         sanity(78), fightTimes(2, series: 1), callback("TaskChainCompleted")]
    }

    private func result(_ events: [String], output: String = "", exit: Int32 = 0,
                        timeout: Bool = false, cancelled: Bool = false, stage: String? = "1-7") -> FightResult {
        var observation = FightObservation()
        for event in events { observation.consume(event) }
        let command = CommandResult(exitCode: exit, standardOutput: output, standardError: "",
                                    timedOut: timeout, cancelled: cancelled)
        return observation.result(for: command, configuredStage: stage)
    }

    func testConfirmedSettlementWithMissingDropsDoesNotInventObservedStage() throws {
        let value = result(missingBatch, output: "Fight 1-7 2 times")
        XCTAssertEqual(value.status, .completed)
        XCTAssertEqual(value.times, 2)
        XCTAssertEqual(value.missingDropRuns, 2)
        XCTAssertNil(value.totalDrops)
        XCTAssertNil(value.stage)
        XCTAssertTrue(value.description.contains("掉落"))
        XCTAssertEqual(try JSONDecoder().decode(FightResult.self, from: JSONEncoder().encode(value)), value)
        let older = try JSONDecoder().decode(FightResult.self, from: Data(#"{"status":"completed","times":1}"#.utf8))
        XCTAssertNil(older.missingDropRuns)
    }

    func testRecognizedAndMissingBatchesPreserveVerifiedCountStageAndPartialDrops() {
        let events = [callback("TaskChainStart"), sanity(90), fightTimes(0, series: 2), task("SubTaskStart", "StartButton2"),
                      task("SubTaskStart", "EndOfAction"), recognizedDrops(2), task("SubTaskCompleted", "EndOfAction"),
                      sanity(78), fightTimes(2, series: 1), task("SubTaskStart", "StartButton2"),
                      task("SubTaskStart", "EndOfAction"), dropError, task("SubTaskCompleted", "EndOfAction"),
                      sanity(5), fightTimes(3, series: 1), callback("TaskChainCompleted")]
        let value = result(events, output: "Fight 1-7 3 times, drops:\ntotal drops: 源岩 × 4")
        XCTAssertEqual(value.status, .completed)
        XCTAssertEqual(value.reason, .insufficientSanity)
        XCTAssertEqual(value.times, 3)
        XCTAssertEqual(value.missingDropRuns, 1)
        XCTAssertEqual(value.stage, "1-7")
        XCTAssertEqual(value.totalDrops, "源岩 × 4")
        XCTAssertEqual(value.dropsSummary, "已识别掉落：源岩 × 4")
    }

    func testSubsequentSuccessfulDropRecognitionTakesPrecedenceWithoutDoubleCounting() {
        var events = missingBatch
        events.insert(recognizedDrops(2), at: 6)
        let value = result(events)
        XCTAssertEqual(value.status, .completed)
        XCTAssertEqual(value.stage, "1-7")
        XCTAssertEqual(value.times, 2)
        XCTAssertNil(value.missingDropRuns)
    }

    func testIncompleteOrContradictoryEvidenceCannotConfirmMissingDrops() {
        func omitting(_ index: Int) -> [String] {
            var events = missingBatch
            events.remove(at: index)
            return events
        }
        func replacing(_ index: Int, with event: String) -> [String] {
            var events = missingBatch
            events[index] = event
            return events
        }
        var reversedSettlement = missingBatch
        reversedSettlement.swapAt(5, 6)
        var reversedFollowUp = missingBatch
        reversedFollowUp.swapAt(7, 8)
        var closedTooEarly = missingBatch
        closedTooEarly.insert(closedTooEarly.removeLast(), at: 7)
        var unclosedBattle = missingBatch
        unclosedBattle.insert(task("SubTaskStart", "StartButton2"), at: 3)
        var stageWithoutReward = missingBatch
        stageWithoutReward.insert(callback("SubTaskError", #""subtask":"CheckStageValid","why":"stage without reward""#), at: 6)
        let cases = [
            ("chain start missing", omitting(0)), ("no pre-battle count", omitting(2)),
            ("no battle start", omitting(3)), ("no settlement start", omitting(4)),
            ("no recognition error", omitting(5)), ("no settlement completion", omitting(6)),
            ("no post-settlement sanity", omitting(7)), ("no post-settlement count", omitting(8)),
            ("chain incomplete", omitting(9)), ("stale baseline", replacing(2, with: fightTimes(1, series: 2))),
            ("mismatched follow-up count", replacing(8, with: fightTimes(3, series: 1))),
            ("invalid follow-up sanity", replacing(7, with: sanity(-1))),
            ("unrelated plugin error", replacing(5, with: callback("SubTaskError", #""subtask":"ReportToPenguinStats","why":"UnknownDrops""#))),
            ("wrong error reason", replacing(5, with: callback("SubTaskError", #""subtask":"RecognizeDrops","why":"other error""#))),
            ("out-of-order error", reversedSettlement), ("out-of-order follow-up", reversedFollowUp),
            ("chain completed before evidence", closedTooEarly), ("previous battle unsettled", unclosedBattle),
            ("annihilation settlement", missingBatch.map { $0.replacingOccurrences(of: "EndOfAction", with: "EndOfActionAnnihilation") })
        ]
        for (reason, events) in cases {
            XCTAssertEqual(result(events, output: "Fight 1-7 2 times").status, .unconfirmed, reason)
        }
        XCTAssertEqual(result(stageWithoutReward, stage: nil).status, .unconfirmed)
        XCTAssertEqual(result(missingBatch, stage: "Annihilation").status, .unconfirmed)
    }

    func testInterruptedOrFailedChainCannotWriteSuccessfulSettlement() {
        var incomplete = missingBatch
        incomplete.insert(task("SubTaskStart", "StartButton2"), at: incomplete.count - 1)
        var stopped = missingBatch
        stopped[stopped.count - 1] = callback("TaskChainStopped")
        var failed = missingBatch
        failed[failed.count - 1] = callback("TaskChainError")
        for value in [result(incomplete), result(stopped), result(failed, exit: 1), result(missingBatch, timeout: true),
                      result(missingBatch, cancelled: true), result(missingBatch, exit: 1), result(missingBatch, output: "GameOffline")] {
            XCTAssertEqual(value.status, .unconfirmed)
            var state = ExecutionState(dateKey: "test")
            state.record(value, for: "fight")
            XCTAssertTrue(state.needsFightConfirmation("fight"))
            XCTAssertFalse(state.completedSteps.contains("fight"))
        }
    }

    func testMissingBattleStartWithDropErrorCannotBeHiddenBySanityOrEarlierDrops() {
        let events = [callback("TaskChainStart"), sanity(90), fightTimes(0, series: 1),
                      task("SubTaskStart", "EndOfAction"), dropError, task("SubTaskCompleted", "EndOfAction"),
                      sanity(0), fightTimes(1, series: 1), callback("TaskChainCompleted")]
        XCTAssertEqual(result(events).status, .unconfirmed)
        var afterRecognized = events
        afterRecognized.insert(contentsOf: [task("SubTaskStart", "StartButton2"), task("SubTaskStart", "EndOfAction"),
                                            recognizedDrops(1), task("SubTaskCompleted", "EndOfAction"),
                                            sanity(42), fightTimes(1, series: 1)], at: 3)
        afterRecognized[afterRecognized.count - 2] = fightTimes(2, series: 1)
        let uncertain = result(afterRecognized)
        XCTAssertEqual(uncertain.status, .unconfirmed)
        XCTAssertEqual(uncertain.times, 1)
    }
}
