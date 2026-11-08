import AutoMAAKit
import Foundation

enum PlanTaskStatus: Equatable, Sendable {
    case none, running, success, failure, cancelled, attention
}

struct PlanTaskStatusSnapshot: Sendable {
    struct ActiveRun: Sendable {
        let planID: UUID?
        let runID: UUID?
        let phase: RunnerPhase
        var isCancelling = false
    }

    private let statuses: [TaskKind: PlanTaskStatus]

    init(plan: AutomationPlan, clients: [ClientConfiguration], state: ExecutionState, entries: [LogEntry],
         weeklyAnnihilation: WeeklyAnnihilationState = .init(), activeRun: ActiveRun? = nil,
         now: Date = Date(), calendar: Calendar = .current) {
        var state = state.forGameDays(of: clients, at: now, calendar: calendar)
        state.prepareWeeklyAnnihilation(plan: plan, clients: clients, weekly: weeklyAnnihilation, at: now)
        let accounts = clients.filter(\.enabled).flatMap { client in
            client.accounts.filter(plan.includes).map { (client.id, $0.id) }
        }
        let steps = Set(plan.enabledTasks.flatMap { task in
            accounts.map { WorkflowStep(planID: plan.id, clientID: $0.0, accountID: $0.1, task: task) }
        })
        let planEntries = entries.filter { $0.planID == plan.id }
        let clientKinds = Dictionary(clients.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let today = planEntries.filter { entry in
            if let kind = entry.clientID.flatMap({ clientKinds[$0] }) {
                return GameDay.contains(entry.timestamp, for: kind, at: now)
            }
            return clientKinds.values.contains { GameDay.contains(entry.timestamp, for: $0, at: now) }
        }
        var latest: [WorkflowStep: LogEntry] = [:]
        for entry in today {
            if let step = Self.step(entry), steps.contains(step) { latest[step] = entry }
        }
        var interruptions: [WorkflowStep: PlanTaskStatus] = [:]
        let runs = Dictionary(grouping: today.filter { $0.runID != nil }, by: { $0.runID! })
        for run in runs.values {
            guard let end = run.last, end.phase == .cancelled || end.phase == .failed,
                  let last = run.last(where: { Self.step($0).map(steps.contains) == true }),
                  let step = Self.step(last), Self.isInFlight(last), latest[step]?.id == last.id else { continue }
            interruptions[step] = end.phase == .cancelled ? .cancelled : .failure
        }
        let activeRunID = activeRun?.planID == plan.id ? activeRun?.runID : nil
        let current = activeRunID.map { id in planEntries.filter { $0.runID == id } }
        var running: WorkflowStep?
        if let activeRun, let current {
            if activeRun.isCancelling,
               let last = current.last(where: { Self.step($0).map(steps.contains) == true }),
               let step = Self.step(last), Self.isInFlight(last) {
                interruptions[step] = .cancelled
            } else if activeRun.phase == .runningTask, let last = current.last,
                      let step = Self.step(last), steps.contains(step), Self.isInFlight(last),
                      !state.isResolved(step.key) {
                running = step
            }
        }
        statuses = Dictionary(uniqueKeysWithValues: TaskKind.allCases.map { task in
            let targets = steps.filter { $0.task == task }
            guard !targets.isEmpty else { return (task, .none) }
            if running?.task == task { return (task, .running) }
            let outcomes = targets.map { step -> PlanTaskStatus in
                let entry = latest[step]
                if let activeRunID, let entry, entry.runID == activeRunID, Self.isFightFallback(entry) {
                    return interruptions[step] ?? .none
                }
                return Self.outcome(step, state: state, latest: entry, interruption: interruptions[step])
            }
            if outcomes.allSatisfy({ $0 == .success }) { return (task, .success) }
            for status in [PlanTaskStatus.failure, .attention, .cancelled] where outcomes.contains(status) {
                return (task, status)
            }
            return (task, .none)
        })
    }

    func status(for task: TaskKind) -> PlanTaskStatus { statuses[task] ?? .none }

    private static func outcome(_ step: WorkflowStep, state: ExecutionState, latest: LogEntry?,
                                interruption: PlanTaskStatus?) -> PlanTaskStatus {
        if step.task == .fight {
            if state.fightProgress?[step.key]?.isRegularManuallyHandled == true { return .attention }
            if let result = state.fightResults?[step.key] {
                switch result.status {
                case .completed: return .success
                case .unconfirmed, .manuallyHandled: return .attention
                case .unnecessary: return result.reason == .navigationUnavailable ? .attention : .none
                case .failed:
                    if let interruption { return interruption }
                    return latest?.level == .success ? .none : .failure
                }
            }
        }
        if state.completedSteps.contains(step.key) { return .success }
        if let result = latest?.fightResult {
            switch result.status {
            case .unconfirmed, .manuallyHandled: return .attention
            case .unnecessary: return result.reason == .navigationUnavailable ? .attention : .none
            case .failed: return .failure
            case .completed: return .none
            }
        }
        if let interruption { return interruption }
        switch latest?.level {
        case .error: return .failure
        case .warning: return .attention
        default: return .none
        }
    }

    private static func step(_ entry: LogEntry) -> WorkflowStep? {
        guard let plan = entry.planID, let client = entry.clientID,
              let account = entry.accountID, let task = entry.task else { return nil }
        return WorkflowStep(planID: plan, clientID: client, accountID: account, task: task)
    }

    private static func isInFlight(_ entry: LogEntry) -> Bool {
        entry.phase == .runningTask
            && ((entry.fightResult == nil && (entry.level == .info || entry.level == .warning)) || isFightFallback(entry))
    }

    private static func isFightFallback(_ entry: LogEntry) -> Bool {
        entry.level == .warning && entry.fightResult.map { FightStagePolicy.canChangeStage(after: $0) } == true
    }
}
