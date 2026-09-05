import Foundation

/// Shared limits for automatic and manual updates. Retries consume the same deadline.
public enum UpdatePolicy {
    public static let checkTimeout: TimeInterval = 30
    public static let resourceTimeout: TimeInterval = 3 * 60
    public static let packageTimeout: TimeInterval = 15 * 60
    public static let retryDelay: Duration = .seconds(5)
    public static let maximumAttempts = 2

    public static func durationDescription(_ seconds: TimeInterval) -> String {
        seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0
            ? "\(Int(seconds / 60)) 分钟"
            : "\(Int(seconds)) 秒"
    }
}

struct UpdateTimeoutError: LocalizedError {
    let operation: String
    let timeout: TimeInterval

    var errorDescription: String? {
        "\(operation)超过 \(UpdatePolicy.durationDescription(timeout))上限（含重试）；请检查网络后重试"
    }
}

struct UpdateDeadline: Sendable {
    let timeout: TimeInterval
    private let end: ContinuousClock.Instant

    init(timeout: TimeInterval) {
        self.timeout = timeout
        end = .now.advanced(by: .seconds(timeout))
    }

    var remaining: TimeInterval {
        let duration = ContinuousClock.now.duration(to: end).components
        return max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }

    func check(operation: String) throws {
        try Task.checkCancellation()
        guard remaining > 0 else { throw UpdateTimeoutError(operation: operation, timeout: timeout) }
    }

    func perform<T: Sendable>(
        operation: String,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try check(operation: operation)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(remaining))
                throw UpdateTimeoutError(operation: operation, timeout: timeout)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
