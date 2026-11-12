import Foundation

public enum WorkflowRunRequest: Equatable, Sendable {
    case newRound
    case resume(roundID: UUID)
}

public struct ExecutionRound: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let number: Int

    public init(id: UUID = UUID(), startedAt: Date, number: Int = 1) {
        self.id = id
        self.startedAt = startedAt
        self.number = number
    }
}

extension ExecutionState {
    public func currentRound(for planID: UUID) -> ExecutionRound? {
        rounds?[planID.uuidString]
    }

    /// Retain only the latest round's checkpoints, plus decisions that still protect a fight.
    @discardableResult
    public mutating func startRound(for planID: UUID, at date: Date, calendar: Calendar = .current) -> ExecutionRound {
        let previous = currentRound(for: planID)
        let number = previous.map { calendar.isDate($0.startedAt, inSameDayAs: date) ? $0.number + 1 : 1 } ?? 1
        let round = ExecutionRound(startedAt: date, number: number)
        let prefix = "\(planID.uuidString)/"
        let fightKeys = Set(fightResults?.keys.map { $0 } ?? []).union(fightProgress?.keys.map { $0 } ?? [])
        let protected = Set(fightKeys.filter {
            $0.hasPrefix(prefix) && (needsFightConfirmation($0) || fightProgress?[$0]?.isRegularManuallyHandled == true)
        })
        completedSteps = completedSteps.filter { !$0.hasPrefix(prefix) }
        fightResults = fightResults?.filter { !$0.key.hasPrefix(prefix) || protected.contains($0.key) }
        fightProgress = fightProgress?.filter { !$0.key.hasPrefix(prefix) || protected.contains($0.key) }
        for key in protected {
            guard var progress = fightProgress?[key] else { continue }
            if progress.regular?.status != .unconfirmed, !progress.isRegularManuallyHandled { progress.regular = nil }
            if progress.annihilation?.status != .unconfirmed { progress.annihilation = nil }
            fightProgress?[key] = progress
        }
        if rounds == nil { rounds = [:] }
        rounds?[planID.uuidString] = round
        updatedAt = date
        return round
    }
}
