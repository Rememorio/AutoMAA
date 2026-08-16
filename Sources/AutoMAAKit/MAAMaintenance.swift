import Foundation

public struct MAAMaintenanceState: Codable, Equatable, Sendable {
    public var lastCoreUpdateAttempt: Date?

    public init(lastCoreUpdateAttempt: Date? = nil) {
        self.lastCoreUpdateAttempt = lastCoreUpdateAttempt
    }
}

public struct MAAMaintenanceStore: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func load() -> MAAMaintenanceState {
        guard let data = try? Data(contentsOf: directories.maaMaintenanceState),
              let state = try? Self.decoder.decode(MAAMaintenanceState.self, from: data)
        else { return .init() }
        return state
    }

    public func save(_ state: MAAMaintenanceState) throws {
        try directories.prepare()
        let data = try Self.encoder.encode(state)
        try data.write(to: directories.maaMaintenanceState, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum AutomaticMAAUpdatePolicy {
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let scheduledRunSafetyWindow: TimeInterval = 90 * 60

    public static func nextAttemptDate(
        lastAttempt: Date?,
        now: Date = Date()
    ) -> Date {
        lastAttempt?.addingTimeInterval(checkInterval) ?? now
    }

    public static func canStart(
        enabled: Bool,
        lastAttempt: Date?,
        nextScheduledRun: Date?,
        now: Date = Date()
    ) -> Bool {
        guard enabled, nextAttemptDate(lastAttempt: lastAttempt, now: now) <= now else { return false }
        guard let nextScheduledRun else { return true }
        return nextScheduledRun.timeIntervalSince(now) >= scheduledRunSafetyWindow
    }
}
