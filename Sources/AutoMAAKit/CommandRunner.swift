import Darwin
import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool
    public let cancelled: Bool

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        timedOut: Bool,
        cancelled: Bool = false
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
        self.cancelled = cancelled
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: standardOutput.isEmpty || standardError.isEmpty ? "" : "\n")
    }
}

public enum CommandRunnerError: LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(path): "找不到命令：\(path)"
        case let .launchFailed(message): "命令启动失败：\(message)"
        }
    }
}

protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        observeCancellation: Bool
    ) async throws -> CommandResult
}

public struct CommandRunner: CommandRunning, Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        timeout: TimeInterval = 7_200,
        observeCancellation: Bool = true
    ) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandRunnerError.executableNotFound(executable)
        }

        let worker = Task.detached(priority: .utility) {
            if observeCancellation { try Task.checkCancellation() }
            let temp = FileManager.default.temporaryDirectory
                .appending(path: "automaa-command-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }

            let stdoutURL = temp.appending(path: "stdout")
            let stderrURL = temp.appending(path: "stderr")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)

            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

            do {
                if observeCancellation { try Task.checkCancellation() }
                try process.run()
            } catch {
                try? stdoutHandle.close()
                try? stderrHandle.close()
                if error is CancellationError { throw CancellationError() }
                throw CommandRunnerError.launchFailed(error.localizedDescription)
            }

            let processID = process.processIdentifier
            // Foundation creates a child process group on macOS. Never signal our own group.
            let signalTarget = getpgid(processID) == processID && processID != getpgrp()
                ? -processID : processID
            let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
            var timedOut = false
            var cancelled = false
            while process.isRunning,
                  ContinuousClock.now < deadline,
                  (!observeCancellation || !Task.isCancelled) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            if process.isRunning {
                cancelled = observeCancellation && Task.isCancelled
                timedOut = !cancelled
                // Git and download helpers must exit before their staging directory is removed.
                await Task.detached {
                    kill(signalTarget, SIGTERM)
                    let terminationDeadline = ContinuousClock.now.advanced(by: .seconds(2))
                    while kill(signalTarget, 0) == 0, ContinuousClock.now < terminationDeadline {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if kill(signalTarget, 0) == 0 { kill(signalTarget, SIGKILL) }
                    let killDeadline = ContinuousClock.now.advanced(by: .seconds(2))
                    while process.isRunning, ContinuousClock.now < killDeadline {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }.value
            }
            try? stdoutHandle.close()
            try? stderrHandle.close()

            let stdout = String(data: (try? Data(contentsOf: stdoutURL)) ?? Data(), encoding: .utf8) ?? ""
            let stderr = String(data: (try? Data(contentsOf: stderrURL)) ?? Data(), encoding: .utf8) ?? ""
            return CommandResult(
                exitCode: process.isRunning ? -Int32(SIGKILL) : process.terminationStatus,
                standardOutput: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                standardError: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                timedOut: timedOut,
                cancelled: cancelled
            )
        }
        if observeCancellation {
            return try await withTaskCancellationHandler(
                operation: { try await worker.value },
                onCancel: { worker.cancel() }
            )
        }
        return try await worker.value
    }
}
