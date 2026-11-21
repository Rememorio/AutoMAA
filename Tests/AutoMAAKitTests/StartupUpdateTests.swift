import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Startup resource update evidence")
struct StartupUpdateTests {
    @Test("a current game update keeps the original startup process alive beyond its normal deadline")
    @MainActor
    func downloadContinuesPastStartupDeadline() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-download-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data((callback("SubTaskStart", task: "GameStartUpdateOCR") + "\n").utf8)
            .write(to: directory.appending(path: "asst.log"))
        let notification = root.appending(path: "wait-extended")
        var extensions = 0
        let result = try await CommandRunner().run(executable: "/bin/sh",
            arguments: ["-c", "echo startup; until [ -f \"$1\" ]; do sleep 0.1; done; echo ready", "test", notification.path],
            environment: ["MAA_STATE_DIR": root.path], timeout: 0.9,
            observeCancellation: true, startupScreenshotPolicy: .standard, startupUpdateWait: .init(timeout: 30) {
                extensions += 1
                #expect(FileManager.default.createFile(atPath: notification.path, contents: nil))
            })
        #expect(extensions == 1)
        #expect(result.exitCode == 0)
        #expect(!result.timedOut)
        #expect(result.standardOutput == "startup\nready")
        #expect(result.effectiveTimeout == 30)
        #expect(result.startupUpdateWaitExtended)
    }

    @Test("ordinary startup limits survive missing, stale, unrelated and incomplete download evidence",
          arguments: ["missing", "text", "stale", "otherChain", "incomplete", "backup", "unmonitored"])
    func onlyCurrentDownloadCanExtendStartup(evidence: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-limit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let update = callback("SubTaskStart", task: "GameStartUpdateOCR")
        let text = switch evidence {
        case "missing": ""
        case "text": "[INF] GameStartUpdateOCR MB\n"
        case "stale": update + "\n" + callback("SubTaskStart", task: "UnknownPopup") + "\n"
        case "otherChain": update.replacingOccurrences(of: "StartUp\"", with: "Mall\"") + "\n"
        case "incomplete": update + "\nAssistant::append_callback | SubTaskStart {partial"
        default: update + "\n"
        }
        try Data(text.utf8).write(to: directory.appending(path: evidence == "backup" ? "asst.bak.log" : "asst.log"))
        let result = try await CommandRunner().run(executable: "/bin/sh",
            arguments: ["-c", "/bin/sleep 30 && echo ready"], environment: ["MAA_STATE_DIR": root.path], timeout: 0.6,
            observeCancellation: true, startupScreenshotPolicy: evidence == "unmonitored" ? nil : .standard,
            startupUpdateWait: .init(timeout: 4) { Issue.record("Unexpected update wait") })
        #expect(result.timedOut)
        #expect(!result.cancelled)
        #expect(result.effectiveTimeout == 0.6)
        #expect(!result.startupUpdateWaitExtended)
        #expect(result.standardOutput.isEmpty)
    }

    @Test("repeated downloads and a pending update notification cannot delay the hard deadline")
    @MainActor
    func repeatedUpdatesKeepOneDeadline() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-hard-limit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = callback("SubTaskCompleted", task: "GameStartUpdateOCR")
        let log = directory.appending(path: "asst.log")
        try Data((line + "\n").utf8).write(to: log)
        var extensions = 0
        let stopped = root.appending(path: "stopped")
        let script = #"""
            trap 'touch "$3"; exit 0' TERM
            for i in $(seq 1 100); do
                printf '%s\n' "$2" >> "$1"
                sleep 0.3
            done
            echo ready
            """#
        let result = try await CommandRunner().run(executable: "/bin/sh",
            arguments: ["-c", script, "test", log.path, line, stopped.path], environment: ["MAA_STATE_DIR": root.path], timeout: 0.6,
            observeCancellation: true, startupScreenshotPolicy: .standard, startupUpdateWait: .init(timeout: 1.2) {
                extensions += 1
                let limit = ContinuousClock.now.advanced(by: .seconds(10))
                while !FileManager.default.fileExists(atPath: stopped.path), ContinuousClock.now < limit {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                #expect(FileManager.default.fileExists(atPath: stopped.path))
            })
        #expect(extensions == 1)
        #expect(result.timedOut)
        #expect(!result.cancelled)
        #expect(result.effectiveTimeout == 1.2)
        #expect(result.startupUpdateWaitExtended)
        #expect(result.standardOutput.isEmpty)
    }

    @Test("safe cancellation still interrupts an extended game update")
    func extendedDownloadCanBeCancelled() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data((callback("SubTaskStart", task: "GameStartUpdateOCR") + "\n").utf8)
            .write(to: directory.appending(path: "asst.log"))
        let marker = root.appending(path: "waiting")
        let pidFile = root.appending(path: "child.pid")
        let task = Task {
            try await CommandRunner().run(executable: "/bin/sh",
                arguments: ["-c", "sleep 1.2; sleep 30 & echo $! > \"$2\"; touch \"$1\"; wait",
                            "test", marker.path, pidFile.path],
                environment: ["MAA_STATE_DIR": root.path], timeout: 0.6, observeCancellation: true,
                startupScreenshotPolicy: .standard, startupUpdateWait: .init(timeout: 4) {})
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        task.cancel()
        let result = try await task.value
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(result.effectiveTimeout == 4)
        #expect(result.cancelled)
        #expect(!result.timedOut)
        #expect(result.stopReason == nil)
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test("persistent screenshot failures can stop an extended update before its hard deadline")
    func extendedDownloadRetainsScreenshotProtection() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-update-screenshots-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data((callback("SubTaskStart", task: "GameStartUpdateOCR") + "\n").utf8)
            .write(to: directory.appending(path: "asst.log"))
        let script = "sleep 1.2; while :; do echo '[ERROR] ScreencapFailed' >&2; sleep 0.1; done"
        let result = try await CommandRunner().run(executable: "/bin/sh", arguments: ["-c", script],
            environment: ["MAA_STATE_DIR": root.path], timeout: 0.6, observeCancellation: true,
            startupScreenshotPolicy: .init(minimumFailures: 3, minimumDuration: .milliseconds(300), maximumGap: .seconds(3)),
            startupUpdateWait: .init(timeout: 4) {})
        #expect(result.effectiveTimeout == 4)
        #expect(result.stopReason == .startupScreenshotFailure)
        #expect(!result.timedOut)
        #expect(!result.cancelled)
    }

    @Test("an exhausted update wait needs review when the final download evidence is no longer complete")
    func extendedTimeoutNeedsReview() {
        var result = CommandResult(exitCode: 9, standardOutput: "", standardError: "", timedOut: true)
        result.startupUpdateWaitExtended = true
        #expect(StartupFailureClassifier.commandOutcome(result: result, output: "")
            == .needsIntervention(.init(scope: .client,
                guidance: "游戏更新等待已超时，请手动确认游戏已进入主界面，再继续未完成任务")))
        for output in ["GameOffline", "ScreencapFailed"] {
            #expect(StartupFailureClassifier.commandOutcome(result: result, output: output) == .connectionLost)
        }
        result = CommandResult(exitCode: 9, standardOutput: "", standardError: "", timedOut: true, cancelled: true)
        result.startupUpdateWaitExtended = true
        #expect(StartupFailureClassifier.commandOutcome(result: result, output: "") == .failed)
    }

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

    @Test("a timeout stop preserves only the current complete startup download evidence")
    func timeoutStopRetainsCurrentDownload() {
        let update = callback("SubTaskStart", task: "GameStartUpdateOCR")
        let stopped = "Assistant::append_callback | TaskChainStopped {\"taskchain\":\"StartUp\",\"taskid\":1}"
        #expect(StartupUpdateObservation.isWaitingForDownload(.init(lines: [update, stopped]), stoppedByTimeout: true))
        #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: [update, stopped])))
        #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: [stopped]), stoppedByTimeout: true))
        #expect(!StartupUpdateObservation.isWaitingForDownload(
            .init(lines: [update, stopped], notes: ["日志不完整"]), stoppedByTimeout: true))
        let contradictions = ["TaskChainStart", "TaskChainCompleted", "TaskChainError", "SubTaskError", "AllTasksCompleted"]
            .map { callback($0, task: "GameStartUpdateOCR") }
            + [callback("SubTaskStart", task: "StartToWakeUp"),
               stopped.replacingOccurrences(of: "StartUp", with: "Mall"),
               "Assistant::append_callback | ConnectionInfo {\"what\":\"Disconnect\"}",
               "Assistant::append_callback | SubTaskStart {broken}", "[ERR] screenshot unavailable"]
        for contradiction in contradictions {
            for lines in [[update, contradiction, stopped], [update, stopped, contradiction]] {
                #expect(!StartupUpdateObservation.isWaitingForDownload(.init(lines: lines), stoppedByTimeout: true))
            }
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
