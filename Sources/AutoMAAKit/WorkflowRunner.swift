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
    let notices: [WorkflowNotice]
    let completionSummary: TaskCompletionSummary?
}

private struct TaskCompletionSummary {
    let messageSuffix: String
    let details: String?
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

@MainActor
public final class WorkflowRunner {
    public typealias EventSink = @MainActor @Sendable (RunnerEvent) -> Void

    private let directories: AppDirectories
    private let commandRunner = CommandRunner()
    private let portProbe: any PortProbing
    private let gameController: any GameProcessControlling
    private let shutdownPolicy: ClientShutdownPolicy
    private let historyStore: HistoryStore
    private let diagnosticLogStore: DiagnosticLogStore
    private let stateStore: ExecutionStateStore
    private let eventSink: EventSink
    private var currentPlanID: UUID?
    private var currentRunID: UUID?
    private var currentSensitiveValues: [String] = []
    private var runProgress = MonotonicProgress()

    public convenience init(
        directories: AppDirectories = .init(),
        eventSink: @escaping EventSink = { _ in }
    ) {
        self.init(
            directories: directories,
            portProbe: PortProbe(),
            gameController: GameProcessController(),
            shutdownPolicy: .playCover,
            eventSink: eventSink
        )
    }

    init(
        directories: AppDirectories,
        portProbe: any PortProbing,
        gameController: any GameProcessControlling,
        shutdownPolicy: ClientShutdownPolicy,
        eventSink: @escaping EventSink = { _ in }
    ) {
        self.directories = directories
        self.portProbe = portProbe
        self.gameController = gameController
        self.shutdownPolicy = shutdownPolicy
        historyStore = HistoryStore(directories: directories)
        diagnosticLogStore = DiagnosticLogStore(directories: directories)
        stateStore = ExecutionStateStore(directories: directories)
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
        if let problem = ConfigurationValidator.readinessProblems(
            in: configuration,
            planID: plan.id
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
            try MAAConfigurationWriter(directories: directories).prepare(configuration)
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
        var visitedSteps = 0

        emit(.preparing, "正在准备「\(plan.displayName)」", 0, .info)
        if plan.policy.hotUpdateBeforeRun {
            emit(.updating, "正在热更新 MAA 资源", 0, .info)
            let result = await runCommand(
                executable: configuration.cliPath,
                arguments: ["hot-update", "--batch"],
                timeout: 120
            )
            if result.cancelled || Task.isCancelled {
                report.cancelled = true
            } else if result.exitCode == 0 {
                emit(.updating, "MAA 资源已更新", 0, .success)
            } else {
                emit(
                    .updating,
                    "资源更新失败，继续使用本地资源",
                    0,
                    .warning,
                    details: shortOutput(result)
                )
            }
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
                try await launch(client)
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
                appendIntervention(
                    intervention.localizedDescription,
                    skippedSteps: clientStepCount,
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
                    let intervention = manualIntervention(for: error, client: client, account: account)
                    let skipped = intervention.scope == .client
                        ? max(0, clientStepCount - (visitedSteps - visitedAtClientStart))
                        : enabledTasks.count
                    appendIntervention(
                        intervention.localizedDescription,
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
                            intervention.localizedDescription,
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
                    visitedSteps += 1
                    if outcome.succeeded {
                        report.succeededSteps += 1
                        state.completedSteps.insert(key)
                        state.updatedAt = Date()
                        try? stateStore.save(state)
                        emit(
                            .runningTask,
                            "\(accountText(account))：\(task.title)已完成\(outcome.completionSummary?.messageSuffix ?? "")",
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
                            task: task
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
                                let intervention = manualIntervention(for: error, client: client, account: account)
                                let skipped: Int
                                if intervention.scope == .client {
                                    skipped = max(0, clientStepCount - (visitedSteps - visitedAtClientStart))
                                } else {
                                    skipped = max(0, enabledTasks.count - (visitedSteps - visitedAtAccountStart))
                                }
                                appendIntervention(
                                    intervention.localizedDescription,
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
        if let fatalError = report.fatalError {
            emit(.failed, "流程中止：\(fatalError)", Double(visitedSteps) / Double(totalSteps), .error)
        } else if report.cancelled {
            emit(.cancelled, "流程已安全停止，当前客户端已关闭且连接已释放", Double(visitedSteps) / Double(totalSteps), .warning)
        } else if !report.attentionMessages.isEmpty {
            emit(.completed, attentionSummary(report.attentionMessages), 1, .warning)
        } else if report.failedSteps > 0 {
            let suffix = report.notices.isEmpty ? "" : "，另有 \(report.notices.count) 项结果需要确认"
            emit(.completed, "流程完成，\(report.failedSteps) 个步骤失败\(suffix)", 1, .warning)
        } else if !report.notices.isEmpty {
            emit(.completed, noticeSummary(plan: plan, notices: report.notices), 1, .warning)
        } else {
            emit(.completed, "「\(plan.displayName)」已全部完成", 1, .success)
        }
        return report
    }

    public func hotUpdate(cliPath: String) async -> Bool {
        beginActivity()
        defer { endActivity() }
        emit(.updating, "正在热更新 MAA 资源", 0, .info)
        let result = await runCommand(executable: cliPath, arguments: ["hot-update", "--batch"], timeout: 180)
        if result.cancelled || Task.isCancelled {
            emit(.cancelled, "资源更新已停止", 1, .warning)
            return false
        }
        let success = result.exitCode == 0
        emit(
            success ? .completed : .failed,
            success ? "MAA 资源已经是最新" : "资源更新失败",
            1,
            success ? .success : .error,
            details: success ? nil : shortOutput(result)
        )
        return success
    }

    public func updateCore(cliPath: String) async -> Bool {
        beginActivity()
        defer { endActivity() }
        emit(.updating, "正在更新 MAA 核心与基础资源", 0, .info)
        let result = await runCommand(
            executable: cliPath,
            arguments: ["update", "stable", "--batch"],
            timeout: 900
        )
        if result.cancelled || Task.isCancelled {
            emit(.cancelled, "MAA 更新已停止", 1, .warning)
            return false
        }
        let success = result.exitCode == 0 && !result.timedOut
        emit(
            success ? .completed : .failed,
            success ? "MAA 核心与基础资源已更新" : "MAA 更新失败",
            1,
            success ? .success : .error,
            details: success ? nil : shortOutput(result)
        )
        return success
    }

    private func launch(_ client: ClientConfiguration) async throws {
        guard !Task.isCancelled else { throw RuntimeError.cancelled }
        emit(.launching, "正在启动\(clientText(client))", 0, .info, client: client)
        _ = try PortAddress(client.address)
        guard !client.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeError.bundleIdentifierMissing(client.displayName)
        }
        guard FileManager.default.fileExists(atPath: client.appPath) else {
            throw RuntimeError.appNotFound(client.appPath)
        }
        if await portProbe.isOpen(client.address) {
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
        let attempts = max(1, policy.maxRetries + 1)
        var lastResult = CommandResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: false)
        for attempt in 1...attempts {
            guard !Task.isCancelled else { throw RuntimeError.cancelled }
            if attempt > 1 {
                emit(
                    .switchingAccount,
                    "正在重试准备\(accountText(account))（\(attempt - 1)/\(attempts - 1)）",
                    0,
                    .info,
                    client: client,
                    account: account
                )
            }
            lastResult = await runCommand(executable: configuration.cliPath, arguments: arguments, timeout: 120)
            guard !lastResult.cancelled, !Task.isCancelled else { throw RuntimeError.cancelled }
            if lastResult.exitCode == 0, !lastResult.timedOut {
                emit(.switchingAccount, "\(accountText(account))已就绪", 0, .success, client: client, account: account)
                return
            }
            emit(
                .switchingAccount,
                "\(accountText(account))尚未就绪\(attempt < attempts ? "，稍后重试" : "")",
                0,
                .warning,
                client: client,
                account: account,
                details: shortOutput(lastResult, sensitiveValues: [selector].compactMap { $0 })
            )
            if attempt < attempts { try? await Task.sleep(for: .seconds(2)) }
        }
        let detail = shortOutput(lastResult, sensitiveValues: [selector].compactMap { $0 })
        let diagnosis = StartupFailureClassifier.diagnose(
            output: detail,
            hasAccountSelector: selector != nil
        )
        throw ManualInterventionError(
            scope: diagnosis.scope,
            reason: "\(accountText(account))准备失败",
            guidance: diagnosis.guidance
        )
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
        var notices: [WorkflowNotice] = []
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
                timeout: task == .fight ? 7_200 : 900
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
                return TaskRunOutcome(
                    succeeded: true,
                    notices: notices,
                    completionSummary: completionSummary(for: task, output: result.combinedOutput)
                )
            }
            emit(
                .runningTask,
                "\(accountText(account))：\(task.title)未完成\(attempt < attempts ? "，准备重试" : "")",
                0,
                .warning,
                client: client,
                account: account,
                task: task,
                details: shortOutput(result, sensitiveValues: client.accounts.map(\.accountSelector))
            )
            if attempt < attempts {
                if !(await portProbe.isOpen(client.address)) {
                    try await launch(client)
                }
                try await switchAccount(
                    account,
                    client: client,
                    configuration: configuration,
                    policy: plan.policy
                )
            }
        }
        return TaskRunOutcome(succeeded: false, notices: notices, completionSummary: nil)
    }

    private func completionSummary(for task: TaskKind, output: String) -> TaskCompletionSummary? {
        guard task == .fight,
              let summary = MAAOutputSummaryParser.fightSummary(in: output)
        else { return nil }
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
                timeout: 60,
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
        _ message: String,
        skippedSteps: Int,
        visitedSteps: inout Int,
        totalSteps: Int,
        report: inout WorkflowReport,
        client: ClientConfiguration,
        account: AccountConfiguration? = nil
    ) {
        let skipped = max(0, skippedSteps)
        report.skippedSteps += skipped
        report.attentionMessages.append(message)
        visitedSteps += skipped
        emit(
            .attention,
            message,
            Double(visitedSteps) / Double(totalSteps),
            .warning,
            client: client,
            account: account
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
        case .alreadyRunning, .portOccupied, .portReleaseTimeout:
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
        return "流程完成，需要手动处理：\(concise)\(suffix)"
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
        ignoreCancellation: Bool = false
    ) async -> CommandResult {
        let command = arguments.first(where: { !$0.hasPrefix("-") }) ?? URL(filePath: executable).lastPathComponent
        let result: CommandResult
        do {
            result = try await commandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: ["MAA_CONFIG_DIR": directories.maaConfig.path],
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

    private func beginActivity(sensitiveValues: [String] = []) {
        let runID = UUID()
        currentRunID = runID
        currentSensitiveValues = sensitiveValues
        runProgress.reset()
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
        details: String? = nil
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
            task: task
        )
        historyStore.append(log)
        eventSink(RunnerEvent(phase: phase, message: message, progress: normalizedProgress, log: log))
    }
}
