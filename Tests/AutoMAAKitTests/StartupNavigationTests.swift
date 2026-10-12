import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Startup navigation evidence")
struct StartupNavigationTests {
    @Test("warm navigation and a return-button retry retain the Settings failure evidence", arguments: [false, true])
    func warmNavigation(returnedFromAnotherPage: Bool) {
        var lines = settingsNavigationFailureLog().split(separator: "\n").map(String.init)
        let tasks = ["StartUpBegin"] + (returnedFromAnotherPage ? ["ReturnButton"] : []) + ["SwitchAccount"]
        let navigation = tasks.flatMap { task in
            ["SubTaskStart", "SubTaskCompleted"].map { kind in
                "Assistant::append_callback | \(kind) {\"taskchain\":\"StartUp\",\"subtask\":\"ProcessTask\",\"first\":[\"SwitchAccount@StartUpBegin\"],\"details\":{\"task\":\"\(task)\"}}"
            }
        }
        lines.insert(contentsOf: navigation, at: 2)
        #expect(StartupNavigationObservation.failedInSettings(.init(lines: lines)))
    }

    @Test("a complete navigation failure survives log rotation")
    func rotatedFailure() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-evidence-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lines = settingsNavigationFailureLog().split(separator: "\n").map(String.init)
        try Data((lines.prefix(4).joined(separator: "\n") + "\n").utf8).write(to: directory.appending(path: "asst.bak.log"))
        try Data((lines.dropFirst(4).joined(separator: "\n") + "\n").utf8).write(to: directory.appending(path: "asst.log"))
        #expect(StartupNavigationObservation.failedInSettings(MAACoreLog.read(from: root)))
        try FileManager.default.removeItem(at: directory.appending(path: "asst.log"))
        try Data(settingsNavigationFailureLog().utf8).write(to: directory.appending(path: "asst.bak.log"))
        #expect(!StartupNavigationObservation.failedInSettings(MAACoreLog.read(from: root)))
    }

    @Test("incomplete, unrelated or contradictory callbacks never authorize a restart")
    func uncertainEvidence() {
        let lines = settingsNavigationFailureLog().split(separator: "\n").map(String.init)
        for index in 0..<7 {
            var incomplete = lines
            incomplete.remove(at: index)
            #expect(!StartupNavigationObservation.failedInSettings(.init(lines: incomplete)), "Missing callback \(index)")
        }
        for (old, new) in [("StartUp", "Mall"), ("Settings", "AccountManagerOfficial"),
                           ("SwitchAccount@StartUpBegin", "StartUpBegin")] {
            let unrelated = lines.map { $0.replacingOccurrences(of: old, with: new) }
            #expect(!StartupNavigationObservation.failedInSettings(.init(lines: unrelated)))
        }
        for terminal in ["TaskChainCompleted", "TaskChainStopped", "InitFailed"] {
            let contradiction = "Assistant::append_callback | \(terminal) {\"taskchain\":\"StartUp\"}"
            #expect(!StartupNavigationObservation.failedInSettings(.init(lines: lines + [contradiction])))
        }
        for next in ["AccountManagerOfficial", "LoginOther", "OfflineConfirm", "UnknownPopup"] {
            var progressed = lines
            progressed.insert("Assistant::append_callback | SubTaskStart {\"taskchain\":\"StartUp\",\"subtask\":\"ProcessTask\",\"details\":{\"task\":\"\(next)\"}}", at: 4)
            #expect(!StartupNavigationObservation.failedInSettings(.init(lines: progressed)))
        }
        let malformed = "Assistant::append_callback | SubTaskStart {broken}"
        #expect(!StartupNavigationObservation.failedInSettings(.init(lines: lines + [malformed])))
        let disconnected = "Assistant::append_callback | ConnectionInfo {\"what\":\"Disconnect\"}"
        #expect(!StartupNavigationObservation.failedInSettings(.init(lines: lines + [disconnected])))
        #expect(!StartupNavigationObservation.failedInSettings(.init(lines: lines, notes: ["日志不完整"])))
    }

    @Test("partial and truncated files cannot promote a navigation error to recovery")
    func partialFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-startup-partial-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "debug")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "asst.log")
        for text in [String(repeating: "x", count: MAACoreLog.readLimit) + "\n" + settingsNavigationFailureLog(),
                     settingsNavigationFailureLog() + "Assistant::append_callback | SubTaskStart {partial"] {
            try Data(text.utf8).write(to: path)
            let log = MAACoreLog.read(from: root)
            #expect(!log.isComplete)
            #expect(!StartupNavigationObservation.failedInSettings(log))
        }
    }

    @Test("display diagnostics and successful commands cannot request navigation recovery")
    func resultAuthority() {
        var result = CommandResult(exitCode: 1, standardOutput: "", standardError: "StartUp Error", timedOut: false)
        result.diagnosticDetails = settingsNavigationFailureLog()
        #expect(StartupFailureClassifier.commandOutcome(result: result, output: result.combinedOutput) == .failed)
        result.startupNavigationFailed = true
        #expect(StartupFailureClassifier.commandOutcome(result: result, output: result.combinedOutput) == .accountNavigationFailed)
        var success = CommandResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false)
        success.startupNavigationFailed = true
        #expect(StartupFailureClassifier.commandOutcome(result: success, output: "") == .ready)
    }
}

func settingsNavigationFailureLog() -> String {
    """
    Assistant::append_callback | TaskChainStart {"taskchain":"StartUp","taskid":1}
    Assistant::append_callback | SubTaskStart {"taskchain":"StartUp","subtask":"AccountSwitchTask","taskid":0}
    Assistant::append_callback | SubTaskStart {"taskchain":"StartUp","subtask":"ProcessTask","first":["SwitchAccount@StartUpBegin"],"details":{"task":"Settings"},"taskid":0}
    Assistant::append_callback | SubTaskCompleted {"taskchain":"StartUp","subtask":"ProcessTask","first":["SwitchAccount@StartUpBegin"],"details":{"task":"Settings"},"taskid":0}
    Assistant::append_callback | SubTaskError {"taskchain":"StartUp","subtask":"ProcessTask","first":["SwitchAccount@StartUpBegin"],"pre_task":"SwitchAccount","taskid":0}
    Assistant::append_callback | SubTaskError {"taskchain":"StartUp","subtask":"AccountSwitchTask","taskid":0}
    Assistant::append_callback | TaskChainError {"taskchain":"StartUp","taskid":1}
    Assistant::append_callback | AllTasksCompleted {"taskchain":"StartUp","taskid":1,"finished_tasks":[1]}

    """
}
