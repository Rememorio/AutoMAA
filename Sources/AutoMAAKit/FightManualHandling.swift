import Foundation

extension ExecutionState {
    public func canHandleRegularWithoutRetry(_ key: String, expected: FightResult) -> Bool {
        guard expected.status == .unconfirmed, expected.kind != .annihilation,
              !FightStagePolicy.isAnnihilation(expected.stage ?? ""), fightResults?[key] == expected else { return false }
        if let progress = fightProgress?[key] {
            return progress.regular == expected && !progress.isRegularManuallyHandled
        }
        return FightStagePolicy.regularStage(from: expected.stage ?? "", times: 1) != nil
    }

    public mutating func handleRegularWithoutRetry(_ step: WorkflowStep, expected: FightResult, at date: Date) throws {
        guard step.task == .fight, canHandleRegularWithoutRetry(step.key, expected: expected) else {
            throw FightManualHandlingError.staleResult
        }
        var progress = fightProgress?[step.key] ?? FightProgress(regularStage: expected.stage ?? "")
        progress.regular = expected
        progress.regularManuallyHandledAt = date
        if fightProgress == nil { fightProgress = [:] }
        fightProgress?[step.key] = progress
        record(progress.handledRegularResult!, for: step.key)
        updatedAt = date
    }
}

extension ExecutionStateStore {
    public func handleRegularWithoutRetry(_ step: WorkflowStep, expected: FightResult) throws -> ExecutionState {
        try directories.prepare()
        let lock = try ProcessLock(url: directories.lock)
        return try withExtendedLifetime(lock) {
            var state = try loadForExecution()
            try state.handleRegularWithoutRetry(step, expected: expected, at: Date())
            try save(state)
            return state
        }
    }
}

public enum FightManualHandlingError: LocalizedError {
    case staleResult
    public var errorDescription: String? { "作战记录已变化，请刷新后重新检查" }
}
