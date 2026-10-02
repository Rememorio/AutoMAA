import Foundation

struct StartupScreenshotPolicy: Sendable, Equatable {
    let minimumFailures: Int
    let minimumDuration: Duration
    let maximumGap: Duration

    static let standard = Self(minimumFailures: 5, minimumDuration: .seconds(10), maximumGap: .seconds(3))
}

struct StartupScreenshotMonitor {
    let policy: StartupScreenshotPolicy
    private var firstFailure: ContinuousClock.Instant?
    private var lastFailure: ContinuousClock.Instant?
    private var failures = 0

    init(policy: StartupScreenshotPolicy) {
        self.policy = policy
    }

    mutating func consume(_ line: String, at now: ContinuousClock.Instant) -> Bool {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard StartupFailureClassifier.isScreenshotConnectionFailure(line) else {
            firstFailure = nil
            lastFailure = nil
            failures = 0
            return false
        }
        if let lastFailure, lastFailure.duration(to: now) > policy.maximumGap {
            firstFailure = nil
            failures = 0
        }
        let start = firstFailure ?? now
        firstFailure = start
        lastFailure = now
        failures += 1
        return failures >= policy.minimumFailures && start.duration(to: now) >= policy.minimumDuration
    }
}

// Read only newly appended, complete lines; retain split UTF-8 sequences between polls.
struct CommandOutputTail {
    let handle: FileHandle
    private var pending = Data()

    init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }

    mutating func readLines() throws -> [String] {
        guard let data = try handle.read(upToCount: 65_536), !data.isEmpty else { return [] }
        pending.append(data)
        let lines = pending.split(separator: 10, omittingEmptySubsequences: false)
        let complete = lines.dropLast().map { String(decoding: $0, as: UTF8.self) }
        pending = Data(lines.last ?? Data.SubSequence())
        if pending.count > 65_536 { pending.removeAll(keepingCapacity: true) }
        return complete
    }
}
