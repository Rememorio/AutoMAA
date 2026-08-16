import AutoMAAKit
import Foundation

enum PlanReadinessState: Equatable {
    case ready
    case warnings(Int)
    case errors(Int)
    case blockedByOtherPlan(Int)
}

struct PlanReadiness: Equatable {
    let directIssues: [ReadinessIssue]
    let externalBlockers: [ReadinessIssue]

    init(planID: UUID, issues: [ReadinessIssue]) {
        directIssues = issues.filter { issue in
            switch issue.scope {
            case .shared: true
            case let .plan(sourcePlanID): sourcePlanID == planID
            }
        }
        externalBlockers = issues.filter { issue in
            guard issue.severity == .error else { return false }
            if case let .plan(sourcePlanID) = issue.scope {
                return sourcePlanID != planID
            }
            return false
        }
    }

    var state: PlanReadinessState {
        let directErrors = directIssues.count { $0.severity == .error }
        if directErrors > 0 {
            return .errors(directErrors + externalBlockers.count)
        }
        if !externalBlockers.isEmpty {
            return .blockedByOtherPlan(externalBlockers.count)
        }
        let warnings = directIssues.count { $0.severity == .warning }
        return warnings == 0 ? .ready : .warnings(warnings)
    }

    var hasBlockingErrors: Bool {
        switch state {
        case .errors, .blockedByOtherPlan: true
        case .ready, .warnings: false
        }
    }
}
