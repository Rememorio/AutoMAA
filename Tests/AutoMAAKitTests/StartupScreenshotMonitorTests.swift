import Foundation
import XCTest
@testable import AutoMAAKit

final class StartupScreenshotMonitorTests: XCTestCase {
    func testScreenshotStreakRequiresRepeatedFailuresOverTimeAndResetsOnProgressOrGaps() {
        let start = ContinuousClock.now
        var monitor = StartupScreenshotMonitor(policy: .standard)
        for second in 0..<10 {
            XCTAssertFalse(monitor.consume("[ERROR] ScreencapFailed", at: start.advanced(by: .seconds(second))))
        }
        XCTAssertTrue(monitor.consume("[ERROR] ScreencapFailed", at: start.advanced(by: .seconds(10))))
        XCTAssertFalse(monitor.consume("StartUp Completed", at: start.advanced(by: .seconds(11))))
        XCTAssertFalse(monitor.consume("[ERROR] ScreencapFailed", at: start.advanced(by: .seconds(12))))
        XCTAssertFalse(monitor.consume("[ERROR] ScreencapFailed", at: start.advanced(by: .seconds(20))))
        for _ in 0..<20 {
            XCTAssertFalse(monitor.consume("[ERROR] ScreencapFailed", at: start.advanced(by: .seconds(20))))
        }
    }

    func testOutputTailRetainsPartialLinesWithoutRepeatingOldOutput() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        let writer = try FileHandle(forWritingTo: root)
        defer { try? writer.close() }
        var tail = try CommandOutputTail(url: root)
        defer { try? tail.handle.close() }
        try writer.write(contentsOf: Data("[ERROR] Screen".utf8))
        XCTAssertTrue(try tail.readLines().isEmpty)
        try writer.write(contentsOf: Data("capFailed\n恢复".utf8))
        XCTAssertEqual(try tail.readLines(), ["[ERROR] ScreencapFailed"])
        XCTAssertTrue(try tail.readLines().isEmpty)
        try writer.write(contentsOf: Data("完成\n".utf8))
        XCTAssertEqual(try tail.readLines(), ["恢复完成"])
    }

    func testMonitoredStartupStopsPersistentFailuresAndTerminatesChildProcesses() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appending(path: "child.pid")
        let script = "sleep 30 & child=$!; echo $child > \"$1\"; while :; do echo '[ERROR] ScreencapFailed' >&2; sleep 0.1; done"
        let result = try await CommandRunner().run(
            executable: "/bin/sh", arguments: ["-c", script, "test", pidFile.path], environment: [:], timeout: 10,
            observeCancellation: true,
            startupScreenshotPolicy: .init(minimumFailures: 3, minimumDuration: .milliseconds(300), maximumGap: .seconds(3))
        )
        XCTAssertEqual(result.stopReason, .startupScreenshotFailure)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.cancelled)
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testUnmonitoredCommandsAndTransientStartupErrorsCanFinishSuccessfully() async throws {
        let script = "echo '[ERROR] ScreencapFailed' >&2; sleep 0.2; echo 'StartUp Completed'"
        let result = try await CommandRunner().run(executable: "/bin/sh", arguments: ["-c", script], environment: [:],
                                                  timeout: 5, observeCancellation: true, startupScreenshotPolicy: .standard)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(result.stopReason)
        let unmonitored = try await CommandRunner().run(executable: "/bin/sh", arguments: ["-c", script], timeout: 5)
        XCTAssertEqual(unmonitored.exitCode, 0)
        XCTAssertNil(unmonitored.stopReason)
    }

    func testCancellationDuringStartupMonitoringRemainsCancellation() async throws {
        let task = Task {
            try await CommandRunner().run(executable: "/bin/sh",
                arguments: ["-c", "while :; do echo '[ERROR] ScreencapFailed' >&2; sleep 0.1; done"],
                environment: [:], timeout: 10, observeCancellation: true, startupScreenshotPolicy: .standard)
        }
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()
        do {
            let result = try await task.value
            XCTAssertTrue(result.cancelled)
            XCTAssertFalse(result.timedOut)
            XCTAssertNil(result.stopReason)
        } catch is CancellationError {
            // Cancellation before process creation is also a valid outcome.
        }
    }
}
