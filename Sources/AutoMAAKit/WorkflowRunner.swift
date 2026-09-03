import Foundation

struct MonotonicProgress {
    private(set) var value = 0.0

    mutating func reset() {
        value = 0
    }

    mutating func advance(to proposedValue: Double) -> Double {
        let normalized = proposedValue.isFinite ? min(max(proposedValue, 0), 1) : 0
        value = max(value, normalized)
        return value
    }
}

private struct TaskRunOutcome {
    let succeeded: Bool
    let recoveredAfterRetry: Bool
    let notices: [WorkflowNotice]
    let fightSummary: MAAFightSummary?
    let completionSummary: TaskCompletionSummary?
    let failureDetails: String?
}

private struct TaskCompletionSummary {
    let messageSuffix: String
    let details: String?
}

private struct MaintenanceCommandOutcome {
    let result: CommandResult
    let recoveredAfterRetry: Bool
}

private enum StagedMAAUpdateResult {
    case success(changed: Bool, recoveredAfterRetry: Bool)
    case incompatible(MAAResourceCompatibilityIssue)
    case failed(String)
    case cancelled
}

private enum StableCoreUpdatePreflight {
    case proceed(recoveredAfterRetry: Bool)
    case deferred(current: MAASemanticVersion, stable: MAASemanticVersion, recoveredAfterRetry: Bool)
    case failed(String)
    case cancelled
}

struct ClientShutdownPolicy: Sendable, Equatable {
    let maaGracePeriod: TimeInterval
    let systemGracePeriod: TimeInterval
    let forcedGracePeriod: TimeInterval

    static let playCover = ClientShutdownPolicy(
        maaGracePeriod: 5,
        systemGracePeriod: 5,
        forcedGracePeriod: 8
    )
}

struct MAACommandTimeoutPolicy: Sendable, Equatable {
    let startup: TimeInterval
    let shutdown: TimeInterval
    let fight: TimeInterval
    let recruitBase: TimeInterval
    let recruitPerSlot: TimeInterval
    let recruitMaximum: TimeInterval
    let infrastCollectOnly: TimeInterval
    let infrastFullShift: TimeInterval
    let infrastCustomSchedule: TimeInterval
    let mall: TimeInterval
    let award: TimeInterval

    static let standard = MAACommandTimeoutPolicy(
        startup: 120,
        shutdown: 60,
        fight: 7_200,
        recruitBase: 180,
        recruitPerSlot: 60,
        recruitMaximum: 900,
        infrastCollectOnly: 900,
        infrastFullShift: 1_800,
        infrastCustomSchedule: 3_600,
        mall: 600,
        award: 300
    )

    func taskTimeout(for task: TaskKind, plan: AutomationPlan) -> TimeInterval {
        switch task {
        case .fight:
            fight
        case .recruit:
            min(recruitMaximum, recruitBase + recruitPerSlot * Double(max(0, plan.recruit.times)))
        case .infrast:
            switch plan.infrast.mode {
            case .collectOnly: infrastCollectOnly
            case .fullShift: infrastFullShift
            case .customSchedule: infrastCustomSchedule
            }
        case .mall:
            mall
        case .award:
            award
        }
    }
}

@MainActor
public final class WorkflowRunner {
    public typealias EventSink = @MainActor @Sendable (RunnerEvent) -> Void
    public typealias NoticeSink = @MainActor @Sendable ([WorkflowNotice], UUID) async -> NotificationDeliveryResult

    private let directories: AppDirectories
    private let commandRunner: any CommandRunning
    private let resourceProbeExecutable: URL
    private let coreReleaseManifestFetcher: any MAACoreReleaseManifestFetching
    private let portProbe: any PortProbing
    private let gameController: any GameProcessControlling
    private let shutdownPolicy: ClientShutdownPolicy
    private let timeoutPolicy: MAACommandTimeoutPolicy
    private let maintenanceRetryDelay: Duration
    private let historyStore: HistoryStore
    private let diagnosticLogStore: DiagnosticLogStore
    private let stateStore: ExecutionStateStore
    private let fightStageMemoryStore: FightStageMemoryStore
    private let noticeSink: NoticeSink?
    private let eventSink: EventSink
    private var currentPlanID: UUID?
    private var currentRunID: UUID?
    private var currentSensitiveValues: [String] = []
    private var runProgress = MonotonicProgress()
    private var restartedClientsForRecovery: Set<UUID> = []

    public convenience init(
        directories: AppDirectories = .init(),
        resourceProbeExecutable: URL? = nil,
        eventSink: @escaping EventSink = { _ in }
    ) {
        self.init(
            directories: directories,
            portProbe: PortProbe(),
            gameController: GameProcessController(),
            shutdownPolicy: .playCover,
            resourceProbeExecutable: resourceProbeExecutable,
            noticeSink: nil,
            eventSink: eventSink
        )
    }

    public convenience init(
        directories: AppDirectories = .init(),
        resourceProbeExecutable: URL? = nil,
        noticeSink: NoticeSink?,
        eventSink: @escaping EventSink
    ) {
        self.init(
            directories: directories,
            portProbe: PortProbe(),
            gameController: GameProcessController(),
            shutdownPolicy: .playCover,
            resourceProbeExecutable: resourceProbeExecutable,
            noticeSink: noticeSink,
            eventSink: eventSink
        )
    }

    init(
        directories: AppDirectories,
        portProbe: any PortProbing,
        gameController: any GameProcessControlling,
        shutdownPolicy: ClientShutdownPolicy,
        commandRunner: any CommandRunning = CommandRunner(),
        timeoutPolicy: MAACommandTimeoutPolicy = .standard,
        maintenanceRetryDelay: Duration = .seconds(5),
        resourceProbeExecutable: URL? = nil,
        coreReleaseManifestFetcher: any MAACoreReleaseManifestFetching = MAACoreReleaseManifestClient(),
        noticeSink: NoticeSink? = nil,
        eventSink: @escaping EventSink = { _ in }
    ) {
        self.directories = directories
        self.portProbe = portProbe
        self.gameController = gameController
        self.shutdownPolicy = shutdownPolicy
        self.commandRunner = commandRunner
        self.timeoutPolicy = timeoutPolicy
        self.maintenanceRetryDelay = maintenanceRetryDelay
        self.resourceProbeExecutable = resourceProbeExecutable ?? Self.defaultResourceProbeExecutable()
        self.coreReleaseManifestFetcher = coreReleaseManifestFetcher
        historyStore = HistoryStore(directories: directories)
        diagnosticLogStore = DiagnosticLogStore(directories: directories)
        stateStore = ExecutionStateStore(directories: directories)
        fightStageMemoryStore = FightStageMemoryStore(directories: directories)
        self.noticeSink = noticeSink
        self.eventSink = eventSink
    }

    public func run(
        _ configuration: AppConfiguration,
        planID: UUID,
        resumeToday: Bool = true
    ) async -> WorkflowReport {
        var report = WorkflowReport()
        var lock: ProcessLock?
        var lease: CaffeinateLease?
        beginActivity(sensitiveValues: configuration.clients.flatMap { $0.accounts.map(\.accountSelector) })
        defer { endActivity() }
        currentPlanID = nil
        guard let plan = configuration.plans.first(where: { $0.id == planID }) else {
            report.fatalError = "找不到要运行的自动化方案"
            emit(.failed, report.fatalError ?? "方案不存在", 0, .error)
            return report
        }
        currentPlanID = plan.id
        defer { currentPlanID = nil }
        var fightStageMemory: FightStageMemory
        do {
            fightStageMemory = try fightStageMemoryStore.load()
        } catch {
            report.fatalError = "无法读取常规关卡记录：\(error.localizedDescription)"
            emit(.failed, report.fatalError ?? "常规关卡记录无法读取", 0, .error)
            return report
        }
        if let problem = ConfigurationValidator.readinessProblems(
            in: configuration,
            planID: plan.id,
            fightStageMemory: fightStageMemory
        ).first(where: { $0.severity == .error }) {
            report.fatalError = problem.message
            emit(.failed, problem.message, 0, .error)
            return report
        }
        guard !plan.enabledTasks.isEmpty else {
            report.fatalError = "「\(plan.displayName)」没有启用任何步骤"
            emit(.failed, report.fatalError ?? "方案没有任务", 0, .error)
            return report
        }
        guard configuration.clients.contains(where: { client in
            client.enabled && client.accounts.contains(where: plan.includes)
        }) else {
            report.fatalError = "「\(plan.displayName)」没有可执行的账号"
            emit(.failed, report.fatalError ?? "方案没有账号", 0, .error)
            return report
        }
        do {
            try directories.prepare()
            guard FileManager.default.isExecutableFile(atPath: configuration.cliPath) else {
                throw CommandRunnerError.executableNotFound(configuration.cliPath)
            }
            lock = try ProcessLock(url: directories.lock)
            lease = CaffeinateLease()
            try MAAConfigurationWriter(directories: directories).prepare(
                configuration,
                fightStageMemory: fightStageMemory
            )
        } catch {
            report.fatalError = error.localizedDescription
            emit(.failed, error.localizedDescription, 0, .error)
            return report
        }
        _ = lock
        _ = lease

        var state = resumeToday ? stateStore.loadForToday() : ExecutionState(dateKey: ExecutionStateStore.todayKey)
        if !resumeToday { try? stateStore.save(state) }

        let activeClients = configuration.clients.filter { client in
            client.enabled && client.accounts.contains(where: plan.includes)
        }
        let totalSteps = max(1, activeClients.reduce(0) { partial, client in
            partial + client.accounts.filter(plan.includes).count * plan.enabledTasks.count
        })
        report.totalSteps = totalSteps
        var visitedSteps = 0

        emit(.preparing, "正在准备「\(plan.displayName)」", 0, .info)
        if plan.policy.hotUpdateBeforeRun {
            emit(.updating, "正在热更新 MAA 资源", 0, .info)
            let update = await performStagedMAAUpdate(
                cliPath: configuration.cliPath,
                component: .resources,
                operation: "热更新 MAA 资源"
            )
            switch update {
            case .cancelled:
                report.cancelled = true
            case .success:
                emit(.updating, "MAA 资源已更新", 0, .success)
            case let .incompatible(issue):
                emit(
                    .updating,
                    "新资源与当前 MaaCore 不兼容，未启用",
                    0,
                    .warning,
                    details: issue.guidance + "\n" + issue.details
                )
            case let .failed(details):
                emit(
                    .updating,
                    "资源更新失败，继续使用本地资源",
                    0,
                    .warning,
                    details: details
                )
            }
        }

        if let issue = await maaResourceCompatibilityIssue(cliPath: configuration.cliPath) {
            report.fatalError = issue.guidance
            report.unexecutedSteps = totalSteps
            emit(.failed, issue.guidance, 0, .error)
            return report
        }

        clientLoop: for client in activeClients {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            let clientStepCount = client.accounts.filter(plan.includes).count * plan.enabledTasks.count
            let visitedAtClientStart = visitedSteps
            if clientStepCount == 0 {
                emit(.runningTask, "\(clientText(client))没有待执行任务，未启动", Double(visitedSteps) / Double(totalSteps), .info, client: client)
                continue
            }
            let completedClientSteps = resumeToday
                ? completedStepCount(plan: plan, client: client, state: state)
                : 0
            if completedClientSteps == clientStepCount {
                report.skippedSteps += clientStepCount
                visitedSteps += clientStepCount
                emit(
                    .runningTask,
                    "\(clientText(client))的今日任务已全部完成，未启动",
                    Double(visitedSteps) / Double(totalSteps),
                    .info,
                    client: client
                )
                continue
            }
            do {
                try await launch(client, configuredClients: configuration.clients)
            } catch {
                if isCancellation(error) {
                    report.cancelled = true
                    do {
                        let portIsOpen = await portProbe.isOpen(client.address, observeCancellation: false)
                        if gameController.isRunning(client) || portIsOpen {
                            try await close(client, configuration: configuration)
                        }
                    } catch {
                        report.fatalError = error.localizedDescription
                        emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                    }
                    break clientLoop
                }
                if isSafetyCritical(error) {
                    report.fatalError = error.localizedDescription
                    emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                    break
                }
                let intervention = manualIntervention(for: error, client: client)
                let completedBeforeLaunch = resumeToday ? completedClientSteps : 0
                report.skippedSteps += completedBeforeLaunch
                visitedSteps += completedBeforeLaunch
                appendIntervention(
                    intervention,
                    skippedSteps: max(0, clientStepCount - completedBeforeLaunch),
                    visitedSteps: &visitedSteps,
                    totalSteps: totalSteps,
                    report: &report,
                    client: client
                )
                do {
                    let portIsOpen = await portProbe.isOpen(client.address, observeCancellation: false)
                    if gameController.isRunning(client) || portIsOpen {
                        try await close(client, configuration: configuration)
                    }
                } catch {
                    report.fatalError = error.localizedDescription
                    emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                    break
                }
                continue clientLoop
            }

            var stopAfterClosingClient = false
            accountLoop: for account in client.accounts where plan.includes(account) {
                if Task.isCancelled {
                    report.cancelled = true
                    stopAfterClosingClient = true
                    break accountLoop
                }
                let enabledTasks = plan.enabledTasks
                let visitedAtAccountStart = visitedSteps
                if resumeToday, enabledTasks.allSatisfy({
                    state.completedSteps.contains(checkpointKey(plan: plan, client: client, account: account, task: $0))
                }) {
                    report.skippedSteps += enabledTasks.count
                    visitedSteps += enabledTasks.count
                    emit(
                        .runningTask,
                        "\(accountText(account))的今日任务已全部完成，无需再次准备",
                        Double(visitedSteps) / Double(totalSteps),
                        .info,
                        client: client,
                        account: account
                    )
                    continue
                }
                do {
                    try await switchAccount(
                        account,
                        client: client,
                        configuration: configuration,
                        policy: plan.policy
                    )
                } catch {
                    if isCancellation(error) {
                        report.cancelled = true
                        stopAfterClosingClient = true
                        break accountLoop
                    }
                    if isSafetyCritical(error) {
                        report.fatalError = error.localizedDescription
                        emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                        break clientLoop
                    }
                    let intervention = manualIntervention(for: error, client: client, account: account)
                    let skipped = intervention.scope == .client
                        ? max(0, clientStepCount - (visitedSteps - visitedAtClientStart))
                        : enabledTasks.count
                    appendIntervention(
                        intervention,
                        skippedSteps: skipped,
                        visitedSteps: &visitedSteps,
                        totalSteps: totalSteps,
                        report: &report,
                        client: client,
                        account: account
                    )
                    if intervention.scope == .client { break accountLoop }
                    continue
                }

                taskLoop: for task in enabledTasks {
                    if Task.isCancelled {
                        report.cancelled = true
                        stopAfterClosingClient = true
                        break accountLoop
                    }
                    let key = checkpointKey(plan: plan, client: client, account: account, task: task)
                    if resumeToday, state.completedSteps.contains(key) {
                        report.skippedSteps += 1
                        visitedSteps += 1
                        emit(
                            .runningTask,
                            "\(accountText(account))：\(task.title)今日已完成，已跳过",
                            Double(visitedSteps) / Double(totalSteps),
                            .info,
                            client: client,
                            account: account,
                            task: task
                        )
                        continue
                    }

                    let outcome: TaskRunOutcome
                    do {
                        outcome = try await runTask(
                            task,
                            plan: plan,
                            account: account,
                            client: client,
                            configuration: configuration
                        )
                    } catch {
                        if isCancellation(error) {
                            report.cancelled = true
                            stopAfterClosingClient = true
                            break accountLoop
                        }
                        if isSafetyCritical(error) {
                            report.fatalError = error.localizedDescription
                            emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                            break clientLoop
                        }
                        report.failedSteps += 1
                        visitedSteps += 1
                        emit(
                            .runningTask,
                            "\(accountText(account))：\(task.title)失败",
                            Double(visitedSteps) / Double(totalSteps),
                            .error,
                            client: client,
                            account: account,
                            task: task
                        )
                        let intervention = manualIntervention(for: error, client: client, account: account)
                        let skipped: Int
                        if intervention.scope == .client {
                            skipped = max(0, clientStepCount - (visitedSteps - visitedAtClientStart))
                        } else {
                            skipped = max(0, enabledTasks.count - (visitedSteps - visitedAtAccountStart))
                        }
                        appendIntervention(
                            intervention,
                            skippedSteps: skipped,
                            visitedSteps: &visitedSteps,
                            totalSteps: totalSteps,
                            report: &report,
                            client: client,
                            account: account
                        )
                        if intervention.scope == .client { break accountLoop }
                        break taskLoop
                    }
                    report.notices.append(contentsOf: outcome.notices)
                    if !outcome.notices.isEmpty {
                        let delivered = if let noticeSink {
                            await noticeSink(outcome.notices, plan.id).wasDelivered
                        } else {
                            false
                        }
                        if !delivered {
                            report.pendingNotificationNotices.append(contentsOf: outcome.notices)
                        }
                    }
                    visitedSteps += 1
                    if outcome.succeeded {
                        report.succeededSteps += 1
                        if task == .fight {
                            var updatedMemory = fightStageMemory
                            if updatedMemory.recordSuccessfulFight(
                                configuration: plan.fight,
                                reportedStage: outcome.fightSummary?.stage,
                                completedTimes: outcome.fightSummary?.times,
                                clientID: client.id,
                                accountID: account.id
                            ) {
                                do {
                                    try fightStageMemoryStore.save(updatedMemory)
                                    fightStageMemory = updatedMemory
                                } catch {
                                    emit(
                                        .runningTask,
                                        "\(accountText(account))：常规关卡记录保存失败",
                                        Double(visitedSteps) / Double(totalSteps),
                                        .warning,
                                        client: client,
                                        account: account,
                                        task: task,
                                        details: error.localizedDescription
                                    )
                                }
                            }
                        }
                        state.completedSteps.insert(key)
                        state.updatedAt = Date()
                        try? stateStore.save(state)
                        emit(
                            .runningTask,
                            "\(accountText(account))：\(task.title)\(outcome.recoveredAfterRetry ? "重试后" : "")已完成\(outcome.completionSummary?.messageSuffix ?? "")",
                            Double(visitedSteps) / Double(totalSteps),
                            .success,
                            client: client,
                            account: account,
                            task: task,
                            details: outcome.completionSummary?.details
                        )
                    } else {
                        report.failedSteps += 1
                        emit(
                            .runningTask,
                            "\(accountText(account))：\(task.title)失败",
                            Double(visitedSteps) / Double(totalSteps),
                            .error,
                            client: client,
                            account: account,
                            task: task,
                            details: outcome.failureDetails
                        )
                        if plan.policy.continueAfterStepFailure {
                            do {
                                try await switchAccount(
                                    account,
                                    client: client,
                                    configuration: configuration,
                                    policy: plan.policy
                                )
                            } catch {
                                if isCancellation(error) {
                                    report.cancelled = true
                                    stopAfterClosingClient = true
                                    break accountLoop
                                }
                                if isSafetyCritical(error) {
                                    report.fatalError = error.localizedDescription
                                    emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                                    break clientLoop
                                }
                                let intervention = manualIntervention(for: error, client: client, account: account)
                                let skipped: Int
                                if intervention.scope == .client {
                                    skipped = max(0, clientStepCount - (visitedSteps - visitedAtClientStart))
                                } else {
                                    skipped = max(0, enabledTasks.count - (visitedSteps - visitedAtAccountStart))
                                }
                                appendIntervention(
                                    intervention,
                                    skippedSteps: skipped,
                                    visitedSteps: &visitedSteps,
                                    totalSteps: totalSteps,
                                    report: &report,
                                    client: client,
                                    account: account
                                )
                                if intervention.scope == .client { break accountLoop }
                                break taskLoop
                            }
                        } else {
                            report.fatalError = "\(accountText(account))的\(task.title)失败，已按设置停止后续步骤"
                            stopAfterClosingClient = true
                            break accountLoop
                        }
                    }
                }
            }

            do {
                try await close(client, configuration: configuration)
            } catch {
                report.fatalError = error.localizedDescription
                emit(.failed, error.localizedDescription, Double(visitedSteps) / Double(totalSteps), .error, client: client)
                break
            }
            if stopAfterClosingClient || report.cancelled { break }
        }

        if Task.isCancelled { report.cancelled = true }
        let completedSteps = activeClients.reduce(0) { partial, client in
            partial + completedStepCount(plan: plan, client: client, state: state)
        }
        report.unexecutedSteps = max(0, totalSteps - completedSteps - report.failedSteps)
        if let fatalError = report.fatalError {
            emit(.failed, "流程中止：\(fatalError)", Double(visitedSteps) / Double(totalSteps), .error)
        } else if report.cancelled {
            emit(.cancelled, "流程已安全停止，当前客户端已关闭且连接已释放", Double(visitedSteps) / Double(totalSteps), .warning)
        } else if let summary = report.runSummary, summary.isPartial {
            let suffix = report.attentionMessages.isEmpty ? "" : "；\(attentionSummary(report.attentionMessages))"
            let noticeSuffix = report.notices.isEmpty ? "" : "，另有 \(report.notices.count) 项结果需要确认"
            emit(
                .completed,
                "流程部分完成：\(summary.completionDescription)\(noticeSuffix)\(suffix)",
                1,
                .warning,
                runSummary: summary
            )
        } else if !report.attentionMessages.isEmpty {
            emit(.completed, attentionSummary(report.attentionMessages), 1, .warning, runSummary: report.runSummary)
        } else if report.failedSteps > 0 {
            let suffix = report.notices.isEmpty ? "" : "，另有 \(report.notices.count) 项结果需要确认"
            emit(.completed, "流程完成，\(report.failedSteps) 个步骤失败\(suffix)", 1, .warning, runSummary: report.runSummary)
        } else if !report.notices.isEmpty {
            emit(.completed, noticeSummary(plan: plan, notices: report.notices), 1, .warning, runSummary: report.runSummary)
        } else {
            emit(.completed, "「\(plan.displayName)」已全部完成", 1, .success, runSummary: report.runSummary)
        }
        return report
    }

    public func hotUpdate(cliPath: String) async -> Bool {
        beginActivity()
        defer { endActivity() }
        var lock: ProcessLock?
        var lease: CaffeinateLease?
        do {
            try directories.prepare()
            lock = try ProcessLock(url: directories.lock)
            lease = CaffeinateLease()
        } catch {
            emit(.failed, "暂时无法热更新 MAA 资源：\(error.localizedDescription)", 1, .error)
            return false
        }
        _ = lock
        _ = lease
        emit(.updating, "正在热更新 MAA 资源", 0, .info)
        let outcome = await performStagedMAAUpdate(
            cliPath: cliPath,
            component: .resources,
            operation: "热更新 MAA 资源"
        )
        switch outcome {
        case .cancelled:
            emit(.cancelled, "资源更新已停止", 1, .warning)
            return false
        case let .incompatible(issue):
            emit(
                .failed,
                "新资源与当前 MaaCore 不兼容，未启用",
                1,
                .error,
                details: issue.guidance + "\n" + issue.details
            )
            return false
        case let .failed(details):
            emit(.failed, "资源更新失败", 1, .error, details: details)
            return false
        case let .success(_, recoveredAfterRetry):
            emit(
                .completed,
                recoveredAfterRetry ? "MAA 资源重试后已经是最新" : "MAA 资源已经是最新",
                1,
                .success
            )
            return true
        }
    }

    public func updateCore(
        cliPath: String,
        channel: MAAUpdateChannel = .stable
    ) async -> Bool {
        beginActivity()
        defer { endActivity() }
        var lock: ProcessLock?
        var lease: CaffeinateLease?
        do {
            try directories.prepare()
            lock = try ProcessLock(url: directories.lock)
            lease = CaffeinateLease()
        } catch {
            emit(.failed, "暂时无法更新 MAA：\(error.localizedDescription)", 1, .error)
            return false
        }
        _ = lock
        _ = lease
        let operation = channel == .stable
            ? "更新 MAA 核心与基础资源"
            : "更新 MAA Beta 核心与基础资源"
        emit(.updating, "正在\(operation)", 0, .info)
        var preflightRecoveredAfterRetry = false
        if channel == .stable {
            switch await stableCoreUpdatePreflight(cliPath: cliPath) {
            case let .proceed(recoveredAfterRetry):
                preflightRecoveredAfterRetry = recoveredAfterRetry
            case let .deferred(current, stable, recoveredAfterRetry):
                emit(
                    .completed,
                    "\(recoveredAfterRetry ? "重试后确认：" : "")稳定版 v\(stable) 尚未追上当前预发布版 v\(current)，已保留当前 MAA",
                    1,
                    .success
                )
                return true
            case let .failed(details):
                emit(.failed, "无法检查 MAA 稳定版", 1, .error, details: details)
                return false
            case .cancelled:
                emit(.cancelled, "MAA 更新已停止", 1, .warning)
                return false
            }
        }
        let outcome = await performStagedMAAUpdate(
            cliPath: cliPath,
            component: .core(channel),
            operation: operation
        )
        switch outcome {
        case .cancelled:
            emit(.cancelled, "MAA 更新已停止", 1, .warning)
            return false
        case let .incompatible(issue):
            emit(
                .failed,
                channel == .stable
                    ? "稳定通道候选组件未通过资源验证，未启用"
                    : "Beta 候选组件未通过资源验证，未启用",
                1,
                .error,
                details: issue.guidance + "\n" + issue.details
            )
            return false
        case let .failed(details):
            emit(.failed, "MAA 更新失败", 1, .error, details: details)
            return false
        case let .success(changed, recoveredAfterRetry):
            emit(
                .completed,
                updateCoreSuccessMessage(
                    channel: channel,
                    changed: changed,
                    recoveredAfterRetry: recoveredAfterRetry || preflightRecoveredAfterRetry
                ),
                1,
                .success
            )
            return true
        }
    }

    private func stableCoreUpdatePreflight(cliPath: String) async -> StableCoreUpdatePreflight {
        let versionResult = await runCommand(
            executable: cliPath,
            arguments: ["version", "maa-core", "--batch"],
            timeout: 20
        )
        guard !versionResult.cancelled, !Task.isCancelled else { return .cancelled }
        guard versionResult.exitCode == 0, !versionResult.timedOut else {
            return .failed("无法读取当前 MaaCore 版本：\(shortOutput(versionResult))")
        }
        guard let current = MAACoreVersionParser.parseCLIOutput(versionResult.combinedOutput) else {
            return .failed("maa-cli 返回了无法识别的 MaaCore 版本：\(shortOutput(versionResult))")
        }
        guard current.isPrerelease else { return .proceed(recoveredAfterRetry: false) }

        let manifestURL: URL
        do {
            manifestURL = try await coreManifestURL(cliPath: cliPath, channel: .stable)
        } catch {
            return .failed("无法确定稳定版清单地址：\(error.localizedDescription)")
        }
        do {
            let (stable, recoveredAfterRetry) = try await coreReleaseVersion(at: manifestURL)
            if stable <= current {
                return .deferred(
                    current: current,
                    stable: stable,
                    recoveredAfterRetry: recoveredAfterRetry
                )
            }
            return .proceed(recoveredAfterRetry: recoveredAfterRetry)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed("无法读取稳定版清单：\(error.localizedDescription)")
        }
    }

    private func coreReleaseVersion(at url: URL) async throws -> (MAASemanticVersion, Bool) {
        do {
            return (try await coreReleaseManifestFetcher.version(at: url), false)
        } catch {
            guard MAAMaintenanceFailureClassifier.isTransientNetworkFailure(error),
                  !Task.isCancelled
            else { throw error }
            emit(
                .updating,
                "检查稳定版时遇到临时网络问题，正在自动重试（1/1）",
                0,
                .info,
                details: error.localizedDescription
            )
            try await Task.sleep(for: maintenanceRetryDelay)
            guard !Task.isCancelled else { throw CancellationError() }
            return (try await coreReleaseManifestFetcher.version(at: url), true)
        }
    }

    private func coreManifestURL(
        cliPath: String,
        channel: MAAUpdateChannel
    ) async throws -> URL {
        let extensions = ["json", "yaml", "yml", "toml"]
        let configURL = extensions
            .map { directories.maaConfig.appending(path: "cli.\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        var configurationData: Data?
        if let configURL {
            let result = await runCommand(
                executable: cliPath,
                arguments: ["convert", configURL.path, "--format", "json", "--batch"],
                timeout: 20
            )
            guard !result.cancelled, !Task.isCancelled else { throw RuntimeError.cancelled }
            guard result.exitCode == 0, !result.timedOut else {
                throw RuntimeError.taskFailed(shortOutput(result))
            }
            configurationData = Data(result.standardOutput.utf8)
        }
        return try MAACoreReleaseManifestEndpoint.url(
            channel: channel,
            configurationData: configurationData
        )
    }

    private func performStagedMAAUpdate(
        cliPath: String,
        component: MAAComponentUpdate,
        operation: String
    ) async -> StagedMAAUpdateResult {
        guard let paths = await maaInstallationPaths(cliPath: cliPath) else {
            return .failed("无法定位 MaaCore、基础资源或热更新目录；当前安装没有更改")
        }
        let installationLock: ProcessLock
        do {
            installationLock = try ProcessLock(
                url: paths.data.appending(path: ".automaa-update.lock")
            )
        } catch {
            return .failed("另一个 AutoMAA 实例正在维护同一套 MAA 组件；当前安装没有更改")
        }
        _ = installationLock

        let staging: MAAUpdateStaging
        do {
            staging = try prepareMAAUpdateStaging(paths: paths, includesCore: component.includesCore)
        } catch {
            return .failed("无法准备隔离更新目录；当前安装没有更改：\(error.localizedDescription)")
        }
        defer { staging.remove() }
        let installedCoreChecksum = component.includesCore
            ? try? SoftwareUpdateVerifier.sha256(of: paths.library.appending(path: "libMaaCore.dylib"))
            : nil

        let outcome = await runMaintenanceCommand(
            executable: cliPath,
            arguments: component.arguments,
            timeout: component.timeout,
            operation: operation,
            environment: [
                "MAA_DATA_DIR": staging.data.path,
                "MAA_CACHE_DIR": staging.cache.path,
                "MAA_STATE_DIR": staging.state.path,
            ]
        )
        let result = outcome.result
        guard !result.cancelled, !Task.isCancelled else { return .cancelled }
        guard result.exitCode == 0, !result.timedOut else {
            return .failed(shortOutput(result))
        }
        if result.combinedOutput.localizedCaseInsensitiveContains("failed to update resource repository") {
            return .failed(shortOutput(result))
        }
        guard FileManager.default.fileExists(
            atPath: staging.hotUpdate.appending(path: "resource", directoryHint: .isDirectory).path
        ) else {
            return .failed("maa-cli 未生成可验证的热更新资源；当前安装没有更改")
        }

        let library = component.includesCore ? staging.library : paths.library
        let resource = component.includesCore ? staging.resource : paths.resource
        if let issue = await maaResourceCompatibilityIssue(
            libraryDirectory: library,
            resourceDirectory: resource,
            hotUpdateDirectory: staging.hotUpdate,
            cacheDirectory: staging.cache,
            candidateWasNotActivated: true
        ) {
            return .incompatible(issue)
        }
        let componentChanged = component.includesCore && installedCoreChecksum != (try? SoftwareUpdateVerifier.sha256(
            of: staging.library.appending(path: "libMaaCore.dylib")
        ))

        do {
            try FileReplacementTransaction.commit(
                replacements(
                    for: component,
                    paths: paths,
                    staging: staging
                )
            )
        } catch {
            return .failed("无法启用已验证的候选组件；当前安装已尝试恢复：\(error.localizedDescription)")
        }
        return .success(
            changed: componentChanged,
            recoveredAfterRetry: outcome.recoveredAfterRetry
        )
    }

    private func maaInstallationPaths(cliPath: String) async -> MAAInstallationPaths? {
        async let data = maaDirectory(cliPath: cliPath, name: "data")
        async let cache = maaDirectory(cliPath: cliPath, name: "cache")
        async let library = maaDirectory(cliPath: cliPath, name: "library")
        async let resource = maaDirectory(cliPath: cliPath, name: "resource")
        async let hotUpdate = maaDirectory(cliPath: cliPath, name: "hot-update")
        guard let data = await data,
              let cache = await cache,
              let library = await library,
              let resource = await resource,
              let hotUpdate = await hotUpdate
        else { return nil }
        return .init(
            data: data,
            cache: cache,
            library: library,
            resource: resource,
            hotUpdate: hotUpdate
        )
    }

    private func maaDirectory(cliPath: String, name: String) async -> URL? {
        let result = await runCommand(
            executable: cliPath,
            arguments: ["dir", name, "--batch"],
            timeout: 20
        )
        guard result.exitCode == 0, !result.timedOut, !result.cancelled,
              let path = result.standardOutput
                .split(whereSeparator: \Character.isNewline)
                .last
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/")
        else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private func prepareMAAUpdateStaging(
        paths: MAAInstallationPaths,
        includesCore: Bool
    ) throws -> MAAUpdateStaging {
        try removeOwnedStagingItems(in: paths.data, prefix: ".automaa-update-")
        try removeOwnedStagingItems(in: paths.cache, prefix: ".automaa-update-")
        try removeOwnedStagingItems(in: directories.root, prefix: ".maa-update-state-")
        let identifier = UUID().uuidString
        let staging = MAAUpdateStaging(
            data: paths.data.appending(
                path: ".automaa-update-\(identifier)",
                directoryHint: .isDirectory
            ),
            cache: paths.cache.appending(
                path: ".automaa-update-\(identifier)",
                directoryHint: .isDirectory
            ),
            state: directories.root.appending(
                path: ".maa-update-state-\(identifier)",
                directoryHint: .isDirectory
            )
        )
        do {
            try FileManager.default.createDirectory(at: staging.data, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staging.cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staging.state, withIntermediateDirectories: true)
            if includesCore {
                try copyIfPresent(from: paths.library, to: staging.library)
                try copyIfPresent(from: paths.resource, to: staging.resource)
            }
            try copyIfPresent(from: paths.hotUpdate, to: staging.hotUpdate)
            try copyIfPresent(
                from: paths.cache.appending(path: "resource", directoryHint: .isDirectory),
                to: staging.cache.appending(path: "resource", directoryHint: .isDirectory)
            )
            try copyIfPresent(
                from: paths.cache.appending(path: "StageActivityV2.json"),
                to: staging.cache.appending(path: "StageActivityV2.json")
            )
            try copyIfPresent(
                from: paths.cache.appending(path: "StageActivityV2.json.etag"),
                to: staging.cache.appending(path: "StageActivityV2.json.etag")
            )
            return staging
        } catch {
            staging.remove()
            throw error
        }
    }

    private func copyIfPresent(from source: URL, to target: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: target)
    }

    private func removeOwnedStagingItems(in directory: URL, prefix: String) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for item in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) where item.lastPathComponent.hasPrefix(prefix) {
            let values = try item.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff
            else { continue }
            try FileManager.default.removeItem(at: item)
        }
    }

    private func replacements(
        for component: MAAComponentUpdate,
        paths: MAAInstallationPaths,
        staging: MAAUpdateStaging
    ) -> [FileReplacement] {
        var replacements: [FileReplacement] = []
        if component.includesCore {
            replacements.append(.init(
                source: staging.library,
                target: paths.data.appending(path: "lib", directoryHint: .isDirectory)
            ))
            replacements.append(.init(
                source: staging.resource,
                target: paths.data.appending(path: "resource", directoryHint: .isDirectory)
            ))
        }
        replacements.append(.init(source: staging.hotUpdate, target: paths.hotUpdate))
        replacements.append(.init(
            source: staging.cache.appending(path: "resource", directoryHint: .isDirectory),
            target: paths.cache.appending(path: "resource", directoryHint: .isDirectory)
        ))
        replacements.append(.init(
            source: staging.cache.appending(path: "StageActivityV2.json"),
            target: paths.cache.appending(path: "StageActivityV2.json")
        ))
        replacements.append(.init(
            source: staging.cache.appending(path: "StageActivityV2.json.etag"),
            target: paths.cache.appending(path: "StageActivityV2.json.etag")
        ))
        return replacements
    }

    private func runMaintenanceCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        operation: String,
        environment: [String: String] = [:]
    ) async -> MaintenanceCommandOutcome {
        let first = await runCommand(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        )
        guard MAAMaintenanceFailureClassifier.isTransientNetworkFailure(first), !Task.isCancelled else {
            return .init(result: first, recoveredAfterRetry: false)
        }
        emit(
            .updating,
            "\(operation)遇到临时网络问题，正在自动重试（1/1）",
            0,
            .info,
            details: shortOutput(first)
        )
        do {
            try await Task.sleep(for: maintenanceRetryDelay)
        } catch {
            return .init(result: first, recoveredAfterRetry: false)
        }
        guard !Task.isCancelled else {
            return .init(result: first, recoveredAfterRetry: false)
        }
        let retried = await runCommand(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        )
        return .init(
            result: retried,
            recoveredAfterRetry: retried.exitCode == 0 && !retried.timedOut
        )
    }

    private func launch(
        _ client: ClientConfiguration,
        configuredClients: [ClientConfiguration]
    ) async throws {
        guard !Task.isCancelled else { throw RuntimeError.cancelled }
        emit(.launching, "正在启动\(clientText(client))", 0, .info, client: client)
        let address = try PortAddress(client.address)
        guard !client.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeError.bundleIdentifierMissing(client.displayName)
        }
        guard FileManager.default.fileExists(atPath: client.appPath) else {
            throw RuntimeError.appNotFound(client.appPath)
        }
        if await portProbe.isOpen(client.address) {
            if let conflict = configuredClients.first(where: {
                $0.id != client.id
                    && (try? PortAddress($0.address)) == address
                    && gameController.isRunning($0)
            }) {
                throw RuntimeError.portOccupiedByClient(
                    address: client.address,
                    client: conflict.displayName
                )
            }
            guard gameController.isRunning(client) else {
                throw RuntimeError.portOccupied(client.address)
            }
            emit(.launching, "\(clientText(client))已在运行", 0, .info, client: client)
            return
        }
        let result = await runCommand(executable: "/usr/bin/open", arguments: [client.appPath], timeout: 20)
        guard !result.cancelled, !Task.isCancelled else { throw RuntimeError.cancelled }
        guard result.exitCode == 0 else {
            throw RuntimeError.launchFailed(shortOutput(result))
        }
        let connected = await portProbe.wait(forOpen: true, address: client.address, timeout: 90)
        guard !Task.isCancelled else { throw RuntimeError.cancelled }
        guard connected else {
            throw RuntimeError.connectionTimeout(client.address)
        }
        emit(.launching, "\(clientText(client))已连接 MaaTools", 0, .success, client: client)
    }

    private func switchAccount(
        _ account: AccountConfiguration,
        client: ClientConfiguration,
        configuration: AppConfiguration,
        policy: ExecutionPolicy
    ) async throws {
        guard !Task.isCancelled else { throw RuntimeError.cancelled }
        let selector = client.kind.maaAccountSelector(from: account.accountSelector)
        if client.kind.supportsAccountSwitching,
           client.accounts.filter(\.enabled).count > 1,
           selector == nil {
            throw RuntimeError.accountSelectorMissing(account.displayName)
        }

        emit(.switchingAccount, "正在准备\(accountText(account))", 0, .info, client: client, account: account)
        var arguments = ["startup", client.kind.maaClientType]
        if let selector {
            arguments += ["--account-name", selector]
        }
        arguments += commonArguments(client)
        var remainingRetries = max(0, policy.maxRetries)
        var didRestartClient = false
        var didRetry = false
        var lastResult = CommandResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: false)
        while true {
            guard !Task.isCancelled else { throw RuntimeError.cancelled }
            lastResult = await runCommand(
                executable: configuration.cliPath,
                arguments: arguments,
                timeout: timeoutPolicy.startup
            )
            guard !lastResult.cancelled, !Task.isCancelled else { throw RuntimeError.cancelled }
            let detail = shortOutput(lastResult, sensitiveValues: [selector].compactMap { $0 })
            let outcome = StartupFailureClassifier.commandOutcome(
                result: lastResult,
                output: detail
            )
            if outcome == .ready {
                emit(
                    .switchingAccount,
                    "\(accountText(account))\(didRestartClient ? "恢复后" : (didRetry ? "重试后" : ""))已就绪",
                    0,
                    .success,
                    client: client,
                    account: account
                )
                return
            }
            if outcome == .coreInitializationFailed {
                break
            }
            if outcome == .connectionLost {
                let message = lastResult.timedOut
                    ? "\(accountText(account))准备超时，正在重启\(clientText(client))后恢复"
                    : "检测到游戏连接离线，正在重启\(clientText(client))后恢复\(accountText(account))"
                if try await restartClientForRecovery(
                    client,
                    configuration: configuration,
                    message: message,
                    account: account,
                    details: lastResult.timedOut
                        ? timeoutDetails(timeout: timeoutPolicy.startup, output: detail)
                        : detail
                ) {
                    didRestartClient = true
                    continue
                }
                break
            }
            guard remainingRetries > 0 else { break }
            let retry = policy.maxRetries - remainingRetries + 1
            remainingRetries -= 1
            didRetry = true
            emit(
                .switchingAccount,
                "\(accountText(account))准备暂未完成，正在自动重试（\(retry)/\(policy.maxRetries)）",
                0,
                .info,
                client: client,
                account: account,
                details: detail
            )
            try? await Task.sleep(for: .seconds(2))
        }
        let detail = shortOutput(lastResult, sensitiveValues: [selector].compactMap { $0 })
        let diagnosis = StartupFailureClassifier.diagnose(
            output: detail,
            hasAccountSelector: selector != nil
        )
        throw ManualInterventionError(
            scope: diagnosis.scope,
            reason: "\(accountText(account))准备失败",
            guidance: diagnosis.guidance,
            details: detail
        )
    }

    private func restartClientForRecovery(
        _ client: ClientConfiguration,
        configuration: AppConfiguration,
        message: String,
        account: AccountConfiguration?,
        task: TaskKind? = nil,
        details: String? = nil
    ) async throws -> Bool {
        guard restartedClientsForRecovery.insert(client.id).inserted else { return false }
        emit(
            task == nil ? .switchingAccount : .runningTask,
            message,
            0,
            .info,
            client: client,
            account: account,
            task: task,
            details: details
        )
        try await close(client, configuration: configuration)
        try await launch(client, configuredClients: configuration.clients)
        return true
    }

    private func maaResourceCompatibilityIssue(cliPath: String) async -> MAAResourceCompatibilityIssue? {
        guard let paths = await maaInstallationPaths(cliPath: cliPath) else { return nil }
        return await maaResourceCompatibilityIssue(
            libraryDirectory: paths.library,
            resourceDirectory: paths.resource,
            hotUpdateDirectory: paths.hotUpdate,
            cacheDirectory: paths.cache,
            candidateWasNotActivated: false
        )
    }

    private func maaResourceCompatibilityIssue(
        libraryDirectory: URL,
        resourceDirectory: URL,
        hotUpdateDirectory: URL,
        cacheDirectory: URL,
        candidateWasNotActivated: Bool
    ) async -> MAAResourceCompatibilityIssue? {
        let manager = FileManager.default
        let library = libraryDirectory.appending(path: "libMaaCore.dylib")
        guard manager.isReadableFile(atPath: library.path),
              manager.fileExists(atPath: resourceDirectory.path)
        else {
            return .init(
                details: "无法读取 MaaCore 动态库或基础资源目录",
                candidateWasNotActivated: candidateWasNotActivated
            )
        }

        var baseRoots = [resourceDirectory.deletingLastPathComponent()]
        if manager.fileExists(
            atPath: hotUpdateDirectory.appending(path: "resource", directoryHint: .isDirectory).path
        ) {
            baseRoots.append(hotUpdateDirectory)
        }
        if manager.fileExists(
            atPath: cacheDirectory.appending(path: "resource", directoryHint: .isDirectory).path
        ) {
            baseRoots.append(cacheDirectory)
        }

        let globalResources: [String?] = [nil, "txwy", "YoStarEN", "YoStarJP", "YoStarKR"]
        for globalResource in globalResources {
            var roots = baseRoots
            if let globalResource {
                roots += overlayRoots(
                    in: baseRoots,
                    relativePath: "resource/global/\(globalResource)/resource"
                )
            }
            roots += overlayRoots(
                in: baseRoots,
                relativePath: "resource/platform_diff/iOS/resource"
            )
            if let details = await resourceProbeFailure(library: library, resourceRoots: roots) {
                return .init(
                    details: details,
                    candidateWasNotActivated: candidateWasNotActivated
                )
            }
        }
        return nil
    }

    private func overlayRoots(in baseRoots: [URL], relativePath: String) -> [URL] {
        baseRoots.compactMap { root in
            let resource = root.appending(path: relativePath)
            guard FileManager.default.fileExists(atPath: resource.path) else { return nil }
            return resource.deletingLastPathComponent()
        }
    }

    private func resourceProbeFailure(library: URL, resourceRoots: [URL]) async -> String? {
        let userDirectory = directories.root.appending(
            path: ".maa-resource-probe-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: userDirectory) }
        var environment: [String: String] = [
            "DYLD_LIBRARY_PATH": library.deletingLastPathComponent().path,
        ]
        if let inherited = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"], !inherited.isEmpty {
            environment["DYLD_LIBRARY_PATH"]? += ":\(inherited)"
        }
        let result = await runCommand(
            executable: resourceProbeExecutable.path,
            arguments: [library.path, userDirectory.path] + resourceRoots.map(\.path),
            timeout: 30,
            environment: environment
        )
        guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
            return shortOutput(result)
        }
        return nil
    }

    private func updateCoreSuccessMessage(
        channel: MAAUpdateChannel,
        changed: Bool,
        recoveredAfterRetry: Bool
    ) -> String {
        if !changed {
            let message = channel == .beta
                ? "MAA Beta 核心与基础资源已经是最新"
                : "MAA 核心与基础资源已经是最新"
            return recoveredAfterRetry ? "重试后确认：\(message)" : message
        }
        if channel == .beta {
            return recoveredAfterRetry
                ? "MAA Beta 核心与基础资源重试后已更新"
                : "MAA Beta 核心与基础资源已更新"
        }
        return recoveredAfterRetry
            ? "MAA 核心与基础资源重试后已更新"
            : "MAA 核心与基础资源已更新"
    }

    private func runTask(
        _ task: TaskKind,
        plan: AutomationPlan,
        account: AccountConfiguration,
        client: ClientConfiguration,
        configuration: AppConfiguration
    ) async throws -> TaskRunOutcome {
        guard !Task.isCancelled else { throw RuntimeError.cancelled }
        let writer = MAAConfigurationWriter(directories: directories)
        let taskName = writer.taskName(
            planID: plan.id,
            clientID: client.id,
            accountID: account.id,
            task: task
        )
        let attempts = max(1, plan.policy.maxRetries + 1)
        let timeout = timeoutPolicy.taskTimeout(for: task, plan: plan)
        var notices: [WorkflowNotice] = []
        var failureDetails: String?
        for attempt in 1...attempts {
            guard !Task.isCancelled else { throw RuntimeError.cancelled }
            emit(
                .runningTask,
                "\(accountText(account))：正在执行\(task.title)\(attempt > 1 ? "（重试 \(attempt - 1)）" : "")",
                0,
                .info,
                client: client,
                account: account,
                task: task
            )
            let result = await runCommand(
                executable: configuration.cliPath,
                arguments: ["run", taskName] + commonArguments(client),
                timeout: timeout
            )
            guard !result.cancelled, !Task.isCancelled else { throw RuntimeError.cancelled }
            let outputNotices = workflowNotices(
                for: task,
                output: result.combinedOutput,
                plan: plan,
                account: account
            )
            for notice in outputNotices where !notices.contains(notice) {
                notices.append(notice)
                emit(
                    .runningTask,
                    notice.message,
                    0,
                    .warning,
                    client: client,
                    account: account,
                    task: task,
                    details: notice.details
                )
            }
            if result.exitCode == 0, !result.timedOut {
                let fightSummary = task == .fight
                    ? MAAOutputSummaryParser.fightSummary(in: result.combinedOutput)
                    : nil
                return TaskRunOutcome(
                    succeeded: true,
                    recoveredAfterRetry: attempt > 1,
                    notices: notices,
                    fightSummary: fightSummary,
                    completionSummary: completionSummary(for: fightSummary),
                    failureDetails: nil
                )
            }
            failureDetails = shortOutput(result, sensitiveValues: client.accounts.map(\.accountSelector))
            if result.timedOut {
                guard attempt < attempts,
                      try await restartClientForRecovery(
                          client,
                          configuration: configuration,
                          message: "\(accountText(account))：\(task.title)执行超时，正在重启\(clientText(client))后重试（\(attempt)/\(attempts - 1)）",
                          account: account,
                          task: task,
                          details: timeoutDetails(timeout: timeout, output: failureDetails)
                      )
                else {
                    throw taskTimeoutIntervention(
                        task: task,
                        account: account,
                        timeout: timeout,
                        details: failureDetails,
                        recoveredBeforeFailure: restartedClientsForRecovery.contains(client.id)
                    )
                }
                try await switchAccount(
                    account,
                    client: client,
                    configuration: configuration,
                    policy: plan.policy
                )
                continue
            }
            if attempt < attempts {
                emit(
                    .runningTask,
                    "\(accountText(account))：\(task.title)未完成，正在自动重试（\(attempt)/\(attempts - 1)）",
                    0,
                    .info,
                    client: client,
                    account: account,
                    task: task,
                    details: failureDetails
                )
                if !(await portProbe.isOpen(client.address)) {
                    try await launch(client, configuredClients: configuration.clients)
                }
                try await switchAccount(
                    account,
                    client: client,
                    configuration: configuration,
                    policy: plan.policy
                )
            }
        }
        return TaskRunOutcome(
            succeeded: false,
            recoveredAfterRetry: false,
            notices: notices,
            fightSummary: nil,
            completionSummary: nil,
            failureDetails: failureDetails
        )
    }

    private func taskTimeoutIntervention(
        task: TaskKind,
        account: AccountConfiguration,
        timeout: TimeInterval,
        details: String?,
        recoveredBeforeFailure: Bool
    ) -> ManualInterventionError {
        ManualInterventionError(
            scope: .client,
            reason: "\(accountText(account))：\(task.title)执行超时",
            guidance: recoveredBeforeFailure
                ? "客户端自动重启后仍未恢复，可能停在网络、登录、更新或异常弹窗页面；请手动进入一次主界面，本次将跳过该客户端"
                : "客户端状态已不可靠；请手动检查网络、登录、更新或异常弹窗，本次将跳过该客户端",
            details: timeoutDetails(timeout: timeout, output: details)
        )
    }

    private func timeoutDetails(timeout: TimeInterval, output: String?) -> String {
        let limit = if timeout.truncatingRemainder(dividingBy: 60) == 0 {
            "\(Int(timeout / 60)) 分钟"
        } else {
            "\(Int(timeout)) 秒"
        }
        guard let output, !output.isEmpty else { return "超时上限：\(limit)" }
        return "超时上限：\(limit)\n\(output)"
    }

    private func completionSummary(for summary: MAAFightSummary?) -> TaskCompletionSummary? {
        guard let summary else { return nil }
        return TaskCompletionSummary(
            messageSuffix: "（\(summary.stage) × \(summary.times)）",
            details: summary.totalDrops.map { "总掉落：\($0)" }
        )
    }

    private func workflowNotices(
        for task: TaskKind,
        output: String,
        plan: AutomationPlan,
        account: AccountConfiguration
    ) -> [WorkflowNotice] {
        guard task == .recruit else { return [] }
        let preservedTags = plan.recruit.usesCustomSettings ? plan.recruit.preserveTags : ["支援机械"]
        return MAAOutputNoticeParser.recruitmentNotices(in: output, preservedTags: preservedTags).map { notice in
            switch notice {
            case let .highRarity(level, tags):
                return WorkflowNotice(
                    message: "\(accountText(account))：公招发现 \(level)★ 组合，请前往游戏确认",
                    details: "识别标签：\(tags.joined(separator: "、"))",
                    kind: .highRarityRecruit(level: level)
                )
            case let .preservedTag(tag, tags):
                return WorkflowNotice(
                    message: "\(accountText(account))：公招命中保留标签「\(tag)」，已跳过该槽位",
                    details: "识别标签：\(tags.joined(separator: "、"))",
                    kind: .preservedRecruitTag
                )
            case let .specialTag(tag):
                return WorkflowNotice(
                    message: "\(accountText(account))：公招发现特殊标签「\(tag)」，请前往游戏确认",
                    kind: .specialRecruitTag
                )
            }
        }
    }

    private func close(_ client: ClientConfiguration, configuration: AppConfiguration) async throws {
        emit(.closing, "正在关闭\(clientText(client))", 0, .info, client: client)
        let portIsOpen = await portProbe.isOpen(client.address, observeCancellation: false)
        if portIsOpen, !Task.isCancelled {
            _ = await runCommand(
                executable: configuration.cliPath,
                arguments: ["closedown", client.kind.maaClientType] + commonArguments(client),
                timeout: timeoutPolicy.shutdown,
                ignoreCancellation: true
            )
            if await waitUntilClosed(client, timeout: shutdownPolicy.maaGracePeriod) {
                emitClientClosed(client)
                return
            }
        } else if !portIsOpen, !gameController.isRunning(client) {
            emitClientClosed(client)
            return
        }

        _ = gameController.terminate(client, force: false)
        if await waitUntilClosed(client, timeout: shutdownPolicy.systemGracePeriod) {
            emitClientClosed(client)
            return
        }

        _ = gameController.terminate(client, force: true)
        guard await waitUntilClosed(client, timeout: shutdownPolicy.forcedGracePeriod) else {
            throw RuntimeError.portReleaseTimeout(client.address)
        }
        emitClientClosed(
            client,
            details: "客户端未响应常规退出请求，已由 macOS 完成进程清理。"
        )
    }

    private func emitClientClosed(_ client: ClientConfiguration, details: String? = nil) {
        emit(
            .closing,
            "\(clientText(client))已关闭，MaaTools 连接已释放",
            0,
            .success,
            client: client,
            details: details
        )
    }

    private func waitUntilClosed(_ client: ClientConfiguration, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let portIsOpen = await portProbe.isOpen(client.address, observeCancellation: false)
            if !gameController.isRunning(client), !portIsOpen { return true }
            await cleanupPause(.milliseconds(500))
        }
        let portIsOpen = await portProbe.isOpen(client.address, observeCancellation: false)
        return !gameController.isRunning(client) && !portIsOpen
    }

    private func appendIntervention(
        _ intervention: ManualInterventionError,
        skippedSteps: Int,
        visitedSteps: inout Int,
        totalSteps: Int,
        report: inout WorkflowReport,
        client: ClientConfiguration,
        account: AccountConfiguration? = nil
    ) {
        let skipped = max(0, skippedSteps)
        let message = intervention.localizedDescription
        report.skippedSteps += skipped
        report.attentionMessages.append(message)
        visitedSteps += skipped
        emit(
            .attention,
            message,
            Double(visitedSteps) / Double(totalSteps),
            .warning,
            client: client,
            account: account,
            details: intervention.details
        )
    }

    private func manualIntervention(
        for error: Error,
        client: ClientConfiguration,
        account: AccountConfiguration? = nil
    ) -> ManualInterventionError {
        if let intervention = error as? ManualInterventionError { return intervention }
        let reason = error.localizedDescription
        guard let runtimeError = error as? RuntimeError else {
            return .init(
                scope: .client,
                reason: reason,
                guidance: "请手动打开\(clientText(client))并确认已进入主界面；本次将跳过该客户端"
            )
        }
        switch runtimeError {
        case .accountSelectorMissing:
            return .init(
                scope: .account,
                reason: reason,
                guidance: "请补充唯一账号片段；其他账号仍会继续执行"
            )
        case .appNotFound:
            return .init(
                scope: .client,
                reason: reason,
                guidance: "请重新选择安装后的游戏应用；本次将跳过该客户端"
            )
        case .bundleIdentifierMissing, .invalidAddress:
            return .init(
                scope: .client,
                reason: reason,
                guidance: "请修正客户端连接配置；本次将跳过该客户端"
            )
        case .connectionTimeout:
            return .init(
                scope: .client,
                reason: reason,
                guidance: "游戏可能停在大版本更新、协议确认、登录或维护页面，请手动处理；本次将跳过该客户端"
            )
        case .launchFailed:
            return .init(
                scope: .client,
                reason: "\(clientText(client))启动失败",
                guidance: "请手动确认所选游戏应用能够正常启动；本次将跳过该客户端"
            )
        default:
            return .init(
                scope: account == nil ? .client : .account,
                reason: reason,
                guidance: "请手动检查后再运行"
            )
        }
    }

    private func isSafetyCritical(_ error: Error) -> Bool {
        guard let runtimeError = error as? RuntimeError else { return false }
        switch runtimeError {
        case .alreadyRunning, .portOccupied, .portOccupiedByClient, .portReleaseTimeout:
            return true
        default:
            return false
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if case RuntimeError.cancelled = error { return true }
        return Task.isCancelled
    }

    private func cleanupPause(_ duration: Duration) async {
        await Task.detached(priority: .utility) {
            try? await Task.sleep(for: duration)
        }.value
    }

    private func attentionSummary(_ messages: [String]) -> String {
        guard let first = messages.first else { return "流程完成" }
        let firstLine = first.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? first
        let concise = String(firstLine.prefix(240))
        let suffix = messages.count > 1 ? "（另有 \(messages.count - 1) 项，请查看活动记录）" : ""
        return "需要手动处理：\(concise)\(suffix)"
    }

    private func noticeSummary(plan: AutomationPlan, notices: [WorkflowNotice]) -> String {
        "「\(plan.displayName)」已完成，公招有 \(notices.count) 项结果需要确认"
    }

    private func commonArguments(_ client: ClientConfiguration) -> [String] {
        ["-a", client.address, "-p", safeProfileName(client.profileName), "--batch"]
    }

    private func clientText(_ client: ClientConfiguration) -> String {
        "客户端「\(client.displayName)」"
    }

    private func accountText(_ account: AccountConfiguration) -> String {
        "账号「\(account.displayName)」"
    }

    private func safeProfileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func runCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String] = [:],
        ignoreCancellation: Bool = false
    ) async -> CommandResult {
        let command = arguments.first(where: { !$0.hasPrefix("-") }) ?? URL(filePath: executable).lastPathComponent
        let result: CommandResult
        do {
            var commandEnvironment = environment
            commandEnvironment["MAA_CONFIG_DIR"] = directories.maaConfig.path
            result = try await commandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: commandEnvironment,
                timeout: timeout,
                observeCancellation: !ignoreCancellation
            )
        } catch {
            result = CommandResult(
                exitCode: -1,
                standardOutput: "",
                standardError: error.localizedDescription,
                timedOut: false,
                cancelled: !ignoreCancellation && Task.isCancelled
            )
        }
        if let currentRunID {
            diagnosticLogStore.append(
                result,
                command: command,
                runID: currentRunID,
                sensitiveValues: currentSensitiveValues
            )
        }
        return result
    }

    private static func defaultResourceProbeExecutable() -> URL {
        let executable = Bundle.main.executableURL
            ?? URL(filePath: CommandLine.arguments.first ?? "AutoMAA")
        return executable.deletingLastPathComponent().appending(path: "AutoMAAResourceProbe")
    }

    private func beginActivity(sensitiveValues: [String] = []) {
        let runID = UUID()
        currentRunID = runID
        currentSensitiveValues = sensitiveValues
        runProgress.reset()
        restartedClientsForRecovery = []
        diagnosticLogStore.begin(runID: runID)
    }

    private func endActivity() {
        currentRunID = nil
        currentSensitiveValues = []
    }

    private func shortOutput(_ result: CommandResult, sensitiveValues: [String] = []) -> String {
        let output = SensitiveDataRedactor.redact(
            result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            sensitiveValues: sensitiveValues
        )
        if result.timedOut {
            guard !output.isEmpty else { return "执行超时" }
            return "执行超时：\(String(output.suffix(1_480)))"
        }
        guard !output.isEmpty else { return "命令退出码：\(result.exitCode)" }
        return String(output.suffix(1_500))
    }

    private func checkpointKey(
        plan: AutomationPlan,
        client: ClientConfiguration,
        account: AccountConfiguration,
        task: TaskKind
    ) -> String {
        "\(plan.id.uuidString)/\(client.id.uuidString)/\(account.id.uuidString)/\(task.rawValue)"
    }

    private func completedStepCount(plan: AutomationPlan, client: ClientConfiguration, state: ExecutionState) -> Int {
        client.accounts.filter(plan.includes).reduce(0) { count, account in
            count + plan.enabledTasks.filter { task in
                state.completedSteps.contains(checkpointKey(plan: plan, client: client, account: account, task: task))
            }.count
        }
    }

    private func emit(
        _ phase: RunnerPhase,
        _ message: String,
        _ proposedProgress: Double,
        _ level: LogLevel,
        client: ClientConfiguration? = nil,
        account: AccountConfiguration? = nil,
        task: TaskKind? = nil,
        details: String? = nil,
        runSummary: WorkflowRunSummary? = nil
    ) {
        let normalizedProgress = runProgress.advance(to: proposedProgress)
        let log = LogEntry(
            level: level,
            message: message,
            details: details,
            runID: currentRunID,
            phase: phase,
            progress: normalizedProgress,
            planID: currentPlanID,
            clientID: client?.id,
            accountID: account?.id,
            task: task,
            runSummary: runSummary
        )
        historyStore.append(log)
        eventSink(RunnerEvent(phase: phase, message: message, progress: normalizedProgress, log: log))
    }
}
