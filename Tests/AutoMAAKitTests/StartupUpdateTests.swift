import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Startup resource update evidence")
struct StartupUpdateTests {
    @Test("only the current startup download step identifies an unfinished resource update",
          arguments: ["GameStartUpdateOCR", "StartUp@GameStartUpdateOCR"])
    func currentDownload(task: String) {
        let lines = [callback("SubTaskStart", task: task), callback("SubTaskCompleted", task: task)]
        #expect(StartupUpdateObservation.isWaitingForDownload(.init(lines: lines)))
        #expect(StartupUpdateObservation.isWaitingForDownload(.init(lines: lines + [lines[0]])))
        for next in ["StartUpBegin", "StartToWakeUp", "StartUp", "OfflineConfirm", "UnknownPopup"] {
            #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: lines + [callback("SubTaskStart", task: next)])))
        }
        for kind in ["TaskChainStart", "TaskChainCompleted", "TaskChainStopped", "TaskChainError", "SubTaskError", "AllTasksCompleted"] {
            #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: lines + [callback(kind, task: task)])))
        }
    }

    @Test("unrelated, incomplete or contradictory evidence cannot classify an update")
    func uncertainEvidence() {
        let line = callback("SubTaskStart", task: "GameStartUpdateOCR")
        for replacement in [line.replacingOccurrences(of: "StartUp\"", with: "Mall\""),
                            line.replacingOccurrences(of: "ProcessTask", with: "OtherTask"),
                            "[INF] GameStartUpdateOCR MB", "Assistant::append_callback | SubTaskStart {broken}"] {
            #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: [replacement])))
        }
        for ending in ["[ERR] screenshot unavailable", "Assistant::append_callback | SubTaskStart {broken}",
                       "Assistant::append_callback | InitFailed {}",
                       "Assistant::append_callback | ConnectionInfo {\"what\":\"Disconnect\"}",
                       "Assistant::append_callback | ConnectionInfo {\"what\":\"ScreencapFailed\"}"] {
            #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: [line, ending])))
        }
        #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: [line], notes: ["日志不完整"])))
        #expect(!StartupUpdateObservation.isWaitingForDownload(.init()))
    }

    @Test("rotated command logs retain download evidence without parsing redacted JSON")
    func rotatedLogs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-update-evidence-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data((callback("SubTaskStart", task: "GameStartUpdateOCR") + "\n").utf8)
            .write(to: directory.appending(path: "asst.bak.log"))
        let line = callback("SubTaskCompleted", task: "GameStartUpdateOCR")
        let current = directory.appending(path: "asst.log")
        try Data((line + "\n").utf8).write(to: current)
        #expect(StartupUpdateObservation.isWaitingForDownload(MAACoreLog.read(from: root)))
        try Data((line + "\nAssistant::append_callback | SubTaskStart {partial").utf8).write(to: current)
        #expect(!StartupUpdateObservation.isWaitingForDownload(MAACoreLog.read(from: root)))
        try FileManager.default.removeItem(at: current)
        #expect(!StartupUpdateObservation.isWaitingForDownload(MAACoreLog.read(from: root)))
    }

    @Test("update evidence cannot override success, cancellation, initialization or connection failure")
    func outcomePriority() {
        var timeout = CommandResult(exitCode: 9, standardOutput: "", standardError: "", timedOut: true)
        timeout.diagnosticDetails = "GameStartUpdateOCR"
        #expect(StartupFailureClassifier.commandOutcome(result: timeout, output: "") == .connectionLost)
        timeout.startupWaitingForUpdate = true
        #expect(StartupFailureClassifier.commandOutcome(result: timeout, output: "")
            == .needsIntervention(StartupFailureClassifier.gameDataUpdateDiagnosis))
        for output in ["GameOffline", "ScreencapFailed"] {
            #expect(StartupFailureClassifier.commandOutcome(result: timeout, output: output) == .connectionLost)
        }
        #expect(StartupFailureClassifier.commandOutcome(result: timeout, output: "load resource failed") == .coreInitializationFailed)
        for cancelled in [false, true] {
            var result = CommandResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false, cancelled: cancelled)
            result.startupWaitingForUpdate = true
            #expect(StartupFailureClassifier.commandOutcome(result: result, output: "") == (cancelled ? .failed : .ready))
        }
    }

    @Test("explicit client intervention takes precedence over a generic timeout",
          arguments: ["resource download", "update required", "maintenance", "captcha"])
    func explicitIntervention(output: String) {
        let result = CommandResult(exitCode: 9, standardOutput: "", standardError: output, timedOut: true)
        let diagnosis = StartupFailureClassifier.diagnose(output: output, hasAccountSelector: false)
        #expect(StartupFailureClassifier.commandOutcome(result: result, output: output) == .needsIntervention(diagnosis))
    }

    private func callback(_ kind: String, task: String) -> String {
        "Assistant::append_callback | \(kind) {\"taskchain\":\"StartUp\",\"subtask\":\"ProcessTask\",\"details\":{\"task\":\"\(task)\",\"max_times\":2147483647,\"result\":{\"text\":\"MB\"}}}"
    }
}
