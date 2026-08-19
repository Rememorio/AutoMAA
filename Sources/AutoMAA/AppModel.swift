import AppKit
import AutoMAAKit
import Combine
import Foundation
import SwiftUI

enum SidebarSelection: Hashable {
    case overview
    case plan(UUID)
    case client(UUID)
    case account(UUID, UUID)
    case activity
    case settings
    case about
}

typealias ReadinessIssue = ConfigurationProblem

enum PlanRunState: Equatable {
    case ready
    case running
    case anotherPlanRunning
    case maintenanceRunning
    case configurationIncomplete

    static func resolve(
        planID: UUID?,
        isRunning: Bool,
        runningPlanID: UUID?,
        hasReadinessError: Bool
    ) -> Self {
        if isRunning {
            guard let runningPlanID else { return .maintenanceRunning }
            return runningPlanID == planID ? .running : .anotherPlanRunning
        }
        return hasReadinessError ? .configurationIncomplete : .ready
    }
}

enum ApplicationUpdateState {
    case idle
    case checking
    case upToDate
    case available(SoftwareUpdateRelease)
    case downloading(SoftwareUpdateRelease)
    case ready(PreparedSoftwareUpdate)
    case installing(SoftwareUpdateRelease)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    var blocksWorkflow: Bool {
        switch self {
        case .downloading, .installing: true
        default: false
        }
    }
}

private enum ScheduleSynchronizationFeedback {
    case enabled(UUID)
    case disabled(UUID)
    case changed(UUID)
}

private struct ExternalRunState {
    let runID: UUID?
    let planID: UUID?
    let phase: RunnerPhase
    let message: String
    let progress: Double
}

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published var selection: SidebarSelection = .overview {
        didSet {
            if case let .plan(planID) = selection {
                selectCurrentPlan(planID)
            }
        }
    }
    @Published private(set) var currentPlanID: UUID?
    @Published var activityEntries: [LogEntry]
    @Published var phase: RunnerPhase = .idle
    @Published var statusMessage = "等待开始"
    @Published var progress = 0.0
    @Published var isRunning = false
    @Published var runningPlanID: UUID?
    @Published private var externalRunState: ExternalRunState?
    @Published var bannerMessage: String?
    @Published var installedPlanIDs: Set<UUID>
    @Published var lastReport: WorkflowReport?
    @Published private(set) var isSynchronizingSchedules = false
    @Published private(set) var maaVersionSummary = "尚未检测"
    @Published private(set) var isCheckingMAAEnvironment = false
    @Published private(set) var applicationUpdateState: ApplicationUpdateState = .idle
    @Published private(set) var notificationAuthorizationState: NotificationAuthorizationState = .notDetermined
    @Published private(set) var isRequestingNotificationAuthorization = false
    @Published private(set) var isTestingImportantNotification = false

    let directories: AppDirectories
    let currentApplicationVersion: String
    let currentApplicationBuild: String
    let applicationUpdateRepository: String
    private let configurationStore: ConfigurationStore
    private let historyStore: HistoryStore
    private let executionStateStore: ExecutionStateStore
    private let launchAgentManager: LaunchAgentManager
    private let softwareUpdateService: any SoftwareUpdateServing
    private let softwareUpdateResultStore: SoftwareUpdateResultStore
    private let maaMaintenanceStore: MAAMaintenanceStore
    private let importantNotificationCenter: ImportantNotificationCenter
    private let commandRunner = CommandRunner()
    private let configuredRunnerExecutableURL: URL?
    private var saveTask: Task<Void, Never>?
    private var workflowTask: Task<Void, Never>?
    private var automaticMAAUpdateTask: Task<Void, Never>?
    private var automaticMAAUpdateWakeTask: Task<Void, Never>?
    private var lastMAACoreUpdateAttempt: Date?
    private var applicationUpdateTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var notificationTestTask: Task<Void, Never>?
    private var scheduleSynchronizationTask: Task<Void, Never>?
    private var applicationUpdateInstallLock: ProcessLock?
    private var scheduleSynchronizationRevision = 0
    private var didPrepareApplication = false
    private let startupNotice: String?
    private let checksForUpdatesAutomatically: Bool
    private let applicationUpdateAvailabilityValidator: (@MainActor () throws -> Void)?

    init(
        directories: AppDirectories = .init(),
        launchAgentsDirectory: URL? = nil,
        managesSystemLaunchAgents: Bool = true,
        checksForUpdatesAutomatically: Bool = true,
        runnerExecutableURL: URL? = nil,
        softwareUpdateService: (any SoftwareUpdateServing)? = nil,
        applicationUpdateAvailabilityValidator: (@MainActor () throws -> Void)? = nil
    ) {
        self.directories = directories
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        self.applicationUpdateAvailabilityValidator = applicationUpdateAvailabilityValidator
        configuredRunnerExecutableURL = runnerExecutableURL
        configurationStore = ConfigurationStore(directories: directories)
        historyStore = HistoryStore(directories: directories)
        executionStateStore = ExecutionStateStore(directories: directories)
        let applicationVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发构建"
        let applicationBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "local"
        currentApplicationVersion = applicationVersion
        currentApplicationBuild = applicationBuild
        launchAgentManager = LaunchAgentManager(
            directories: directories,
            launchAgentsDirectory: launchAgentsDirectory,
            systemIntegrationEnabled: managesSystemLaunchAgents,
            runnerIdentity: "\(applicationVersion)-\(applicationBuild)"
        )
        applicationUpdateRepository = Bundle.main.object(forInfoDictionaryKey: "AutoMAAUpdateRepository") as? String
            ?? SoftwareUpdateService.defaultRepository
        self.softwareUpdateService = softwareUpdateService ?? SoftwareUpdateService(
            currentVersion: currentApplicationVersion,
            repository: applicationUpdateRepository
        )
        softwareUpdateResultStore = SoftwareUpdateResultStore(directories: directories)
        maaMaintenanceStore = MAAMaintenanceStore(directories: directories)
        importantNotificationCenter = ImportantNotificationCenter()
        do {
            configuration = try configurationStore.load()
            startupNotice = nil
        } catch ConfigurationStoreError.unsupportedSchema {
            if let recovery = try? configurationStore.backupAndReset() {
                configuration = recovery.configuration
                startupNotice = "配置协议不兼容；旧配置已备份为 \(recovery.backupURL.lastPathComponent)，并恢复为空配置"
            } else {
                configuration = .defaults
                startupNotice = "旧配置与当前版本不兼容，且无法创建备份；当前使用空配置"
            }
        } catch {
            if let recovery = try? configurationStore.backupAndReset() {
                configuration = recovery.configuration
                startupNotice = "配置文件无法读取，已备份为 \(recovery.backupURL.lastPathComponent) 并恢复空配置"
            } else {
                configuration = .defaults
                startupNotice = "读取配置失败：\(error.localizedDescription)"
            }
        }
        activityEntries = historyStore.load()
        installedPlanIDs = launchAgentManager.installedPlanIDs
        currentPlanID = configuration.plans.first?.id
        if !ProcessLock.isHeld(at: directories.lock) {
            try? MAAConfigurationWriter(directories: directories).prepare(configuration)
        }
    }

    deinit {
        saveTask?.cancel()
        workflowTask?.cancel()
        automaticMAAUpdateTask?.cancel()
        automaticMAAUpdateWakeTask?.cancel()
        applicationUpdateTask?.cancel()
        notificationTask?.cancel()
        notificationTestTask?.cancel()
        scheduleSynchronizationTask?.cancel()
    }

    var activeClientCount: Int {
        configuration.clients.filter(\.enabled).count
    }

    var activeAccountCount: Int {
        configuration.clients.filter(\.enabled).reduce(0) { result, client in
            result + client.accounts.filter(\.enabled).count
        }
    }

    var activeTaskCount: Int {
        configuration.plans.reduce(0) { $0 + $1.enabledTasks.count }
    }

    var activeScheduleCount: Int {
        configuration.plans.count(where: isPlanScheduleCurrent)
    }

    var isWorkflowRunning: Bool {
        isRunning || externalRunState != nil
    }

    var isExternalRunActive: Bool {
        externalRunState != nil
    }

    var canCancelRun: Bool {
        isRunning && workflowTask != nil
    }

    var activeRunID: UUID? {
        isRunning ? activityEntries.last?.runID : externalRunState?.runID
    }

    var activePlanID: UUID? {
        isRunning ? runningPlanID : externalRunState?.planID
    }

    var activePhase: RunnerPhase {
        externalRunState?.phase ?? phase
    }

    var activeStatusMessage: String {
        externalRunState?.message ?? statusMessage
    }

    var activeProgress: Double {
        externalRunState?.progress ?? progress
    }

    var supportDiagnostics: SupportDiagnostics {
        SupportDiagnostics(
            applicationVersion: currentApplicationVersion,
            applicationBuild: currentApplicationBuild,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.currentArchitecture,
            maaVersionSummary: maaVersionSummary,
            configurationSchemaVersion: AppConfiguration.currentSchemaVersion,
            updateRepository: applicationUpdateRepository
        )
    }

    var repositoryURL: URL {
        URL(string: "https://github.com/\(applicationUpdateRepository)")!
    }

    var documentationURL: URL {
        URL(string: "https://rememorio.github.io/AutoMAA/")!
    }

    var issueReportURL: URL {
        repositoryURL
            .appending(path: "issues")
            .appending(path: "new")
            .appending(path: "choose")
    }

    var readinessIssues: [ReadinessIssue] {
        readinessIssues(for: currentPlanID)
    }

    var currentPlan: AutomationPlan? {
        guard let currentPlanID else { return nil }
        return configuration.plans.first(where: { $0.id == currentPlanID })
    }

    func readinessIssues(for planID: UUID?) -> [ReadinessIssue] {
        ConfigurationValidator.readinessProblems(in: configuration, planID: planID)
    }

    func planReadiness(for planID: UUID) -> PlanReadiness {
        PlanReadiness(planID: planID, issues: readinessIssues(for: planID))
    }

    var canRun: Bool {
        canRun(planID: currentPlanID)
    }

    func selectCurrentPlan(_ planID: UUID) {
        guard configuration.plans.contains(where: { $0.id == planID }) else { return }
        currentPlanID = planID
    }

    func canRun(planID: UUID?) -> Bool {
        planRunState(planID: planID) == .ready
    }

    func planRunState(planID: UUID?) -> PlanRunState {
        let hasReadinessError = planID.map { planReadiness(for: $0).hasBlockingErrors } ?? true
        return PlanRunState.resolve(
            planID: planID,
            isRunning: isWorkflowRunning || applicationUpdateState.blocksWorkflow,
            runningPlanID: activePlanID,
            hasReadinessError: hasReadinessError
        )
    }

    func isPlanScheduleCurrent(_ plan: AutomationPlan) -> Bool {
        plan.schedule.enabled && launchAgentManager.isCurrent(runnerURL: runnerExecutableURL, plan: plan)
    }

    func scheduleConflict(planID: UUID, schedule: PlanSchedule) -> PlanScheduleConflict? {
        PlanScheduleValidator.conflict(planID: planID, schedule: schedule, among: configuration.plans)
    }

    func clientBinding(_ id: UUID) -> Binding<ClientConfiguration>? {
        guard configuration.clients.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.configuration.clients.first(where: { $0.id == id })
                    ?? ClientConfiguration(name: "新客户端", kind: .official, appPath: "", profileName: "client", accounts: [])
            },
            set: { [weak self] newValue in
                guard let self,
                      let index = self.configuration.clients.firstIndex(where: { $0.id == id })
                else { return }
                self.configuration.clients[index] = newValue
            }
        )
    }

    func planBinding(_ id: UUID) -> Binding<AutomationPlan>? {
        guard configuration.plans.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.configuration.plans.first(where: { $0.id == id }) ?? .lightRoutine
            },
            set: { [weak self] newValue in
                guard let self,
                      let index = self.configuration.plans.firstIndex(where: { $0.id == id })
                else { return }
                self.configuration.plans[index] = newValue
            }
        )
    }

    func accountBinding(clientID: UUID, accountID: UUID) -> Binding<AccountConfiguration>? {
        guard let clientIndex = configuration.clients.firstIndex(where: { $0.id == clientID }),
              configuration.clients[clientIndex].accounts.contains(where: { $0.id == accountID })
        else { return nil }
        return Binding(
            get: { [weak self] in
                guard let self,
                      let client = self.configuration.clients.first(where: { $0.id == clientID }),
                      let account = client.accounts.first(where: { $0.id == accountID })
                else { return AccountConfiguration(name: "账号") }
                return account
            },
            set: { [weak self] newValue in
                guard let self,
                      let ci = self.configuration.clients.firstIndex(where: { $0.id == clientID }),
                      let ai = self.configuration.clients[ci].accounts.firstIndex(where: { $0.id == accountID })
                else { return }
                self.configuration.clients[ci].accounts[ai] = newValue
            }
        )
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveNow(showConfirmation: false)
        }
    }

    @discardableResult
    func saveNow(showConfirmation: Bool = true) -> Bool {
        do {
            refreshExternalRunState()
            if !isWorkflowRunning {
                try MAAConfigurationWriter(directories: directories).prepare(configuration)
            }
            try configurationStore.save(configuration)
            if showConfirmation { showBanner("配置已保存") }
            return true
        } catch {
            showBanner("保存失败：\(error.localizedDescription)")
            return false
        }
    }

    func runPlan(_ planID: UUID, resumeToday: Bool = true) {
        reloadActivityHistory()
        selectCurrentPlan(planID)
        let issues = readinessIssues(for: planID)
        guard canRun(planID: planID) else {
            showBanner(issues.first(where: { $0.severity == .error })?.message ?? "当前方案无法运行")
            return
        }
        guard saveNow(showConfirmation: false) else { return }
        isRunning = true
        runningPlanID = planID
        lastReport = nil
        progress = 0
        let snapshot = configuration
        let notificationCenter = importantNotificationCenter
        let noticeSink: WorkflowRunner.NoticeSink?
        if snapshot.notifications.importantEventsEnabled {
            noticeSink = { @MainActor @Sendable notices, planID in
                await notificationCenter.post(notices: notices, planID: planID)
            }
        } else {
            noticeSink = nil
        }
        let runner = WorkflowRunner(directories: directories, noticeSink: noticeSink) { [weak self] event in
            self?.consume(event)
        }
        workflowTask = Task { [weak self] in
            let report = await runner.run(snapshot, planID: planID, resumeToday: resumeToday)
            guard let self else { return }
            self.lastReport = report
            self.isRunning = false
            self.runningPlanID = nil
            self.workflowTask = nil
            _ = self.saveNow(showConfirmation: false)
            await self.postImportantNotification(for: report, planID: planID)
            if let fatalError = report.fatalError {
                self.showBanner(fatalError)
            } else if report.cancelled {
                self.showBanner("流程已安全停止，当前客户端和连接已清理")
            } else if report.isSuccess {
                if report.notices.isEmpty {
                    let name = snapshot.plans.first(where: { $0.id == planID })?.displayName ?? "方案"
                    self.showBanner("「\(name)」已全部完成")
                } else {
                    self.showBanner(self.noticeBanner(report.notices))
                }
            } else if let summary = report.runSummary, summary.isPartial {
                self.showBanner("流程部分完成：\(summary.completionDescription)，请查看活动记录")
            } else if !report.attentionMessages.isEmpty {
                self.showBanner(self.attentionBanner(report.attentionMessages))
            } else {
                let suffix = report.notices.isEmpty ? "" : "，另有 \(report.notices.count) 项公招结果需要确认"
                self.showBanner("流程完成，但有 \(report.failedSteps) 个步骤失败\(suffix)")
            }
            self.resumeAutomaticApplicationUpdateIfNeeded()
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    func runSelectedPlan(resumeToday: Bool = true) {
        guard let currentPlanID else {
            showBanner("请先创建自动化方案")
            return
        }
        runPlan(currentPlanID, resumeToday: resumeToday)
    }

    func hotUpdate() {
        reloadActivityHistory()
        guard !isWorkflowRunning, !applicationUpdateState.blocksWorkflow else { return }
        isRunning = true
        let runner = WorkflowRunner(directories: directories) { [weak self] event in
            self?.consume(event)
        }
        workflowTask = Task { [weak self] in
            _ = await runner.hotUpdate(cliPath: self?.configuration.cliPath ?? "/opt/homebrew/bin/maa")
            guard let self else { return }
            self.isRunning = false
            self.workflowTask = nil
            if Task.isCancelled { self.showBanner("资源更新已停止") }
            self.resumeAutomaticApplicationUpdateIfNeeded()
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    func prepareApplication() {
        guard !didPrepareApplication else { return }
        didPrepareApplication = true
        reloadActivityHistory()
        synchronizeSchedules()
        refreshNotificationAuthorization()
        if let startupNotice {
            showBanner(startupNotice)
        }
        if let result = softwareUpdateResultStore.loadAndClear() {
            applicationUpdateState = result.status == .success ? .upToDate : .failed(result.message)
            showBanner(result.message)
            refreshMAAStatus()
            resumeAutomaticMAAUpdateIfNeeded()
            return
        }
        refreshMAAStatus()
        if checksForUpdatesAutomatically {
            restorePreparedApplicationUpdateOrCheck()
        } else {
            resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    func setImportantNotificationsEnabled(_ enabled: Bool) {
        configuration.notifications.importantEventsEnabled = enabled
        scheduleSave()
        if enabled {
            requestNotificationAuthorization()
        } else {
            refreshNotificationAuthorization()
        }
    }

    func requestNotificationAuthorization() {
        notificationTask?.cancel()
        isRequestingNotificationAuthorization = true
        notificationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRequestingNotificationAuthorization = false
                self.notificationTask = nil
            }
            do {
                let state = try await self.importantNotificationCenter.requestAuthorization()
                guard !Task.isCancelled else { return }
                self.notificationAuthorizationState = state
                if state.canDeliver {
                    self.showBanner("重要通知已开启")
                } else {
                    self.showBanner("macOS 未允许通知，可前往系统设置开启")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.notificationAuthorizationState = await self.importantNotificationCenter.authorizationState()
                self.showBanner("无法请求通知权限：\(error.localizedDescription)")
            }
        }
    }

    func refreshNotificationAuthorization() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            guard let self else { return }
            let state = await self.importantNotificationCenter.authorizationState()
            guard !Task.isCancelled else { return }
            self.notificationAuthorizationState = state
            self.notificationTask = nil
        }
    }

    func testImportantNotification() {
        guard !isTestingImportantNotification else { return }
        guard configuration.notifications.importantEventsEnabled else {
            showBanner("请先开启重要通知")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: runnerExecutableURL.path) else {
            showBanner("找不到后台 Runner，无法测试定时通知")
            return
        }
        isTestingImportantNotification = true
        notificationTestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isTestingImportantNotification = false
                self.notificationTestTask = nil
            }
            do {
                let result = try await self.commandRunner.run(
                    executable: self.runnerExecutableURL.path,
                    arguments: ["--test-notification"],
                    timeout: 15
                )
                guard !Task.isCancelled else { return }
                self.refreshNotificationAuthorization()
                if result.exitCode == 0 {
                    self.showBanner("后台测试通知已发送")
                } else {
                    let message = result.combinedOutput.isEmpty ? "未知错误" : result.combinedOutput
                    self.showBanner("后台测试通知未送达：\(String(message.prefix(180)))")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.showBanner("无法测试后台通知：\(error.localizedDescription)")
            }
        }
    }

    private func postImportantNotification(for report: WorkflowReport, planID: UUID) async {
        guard configuration.notifications.importantEventsEnabled else { return }
        let state = await importantNotificationCenter.authorizationState()
        notificationAuthorizationState = state
        let result = await importantNotificationCenter.post(
            report: report,
            planID: planID
        )
        recordNotificationFailure(result, planID: planID)
    }

    private func recordNotificationFailure(_ result: NotificationDeliveryResult, planID: UUID) {
        guard let failure = result.failureDescription else { return }
        let runID = activityEntries.last(where: { $0.planID == planID })?.runID
        let entry = LogEntry(
            level: .warning,
            message: "重要通知未送达：\(failure)",
            runID: runID,
            phase: .completed,
            progress: 1,
            planID: planID
        )
        historyStore.append(entry)
        activityEntries.append(entry)
        if activityEntries.count > 1_000 { activityEntries.removeFirst(activityEntries.count - 1_000) }
    }

    func refreshMAAStatus(showResult: Bool = false) {
        guard !isCheckingMAAEnvironment else { return }
        guard FileManager.default.isExecutableFile(atPath: configuration.cliPath) else {
            maaVersionSummary = "未找到 maa-cli"
            if showResult { showBanner("找不到可执行的 maa-cli") }
            return
        }
        isCheckingMAAEnvironment = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.commandRunner.run(
                    executable: self.configuration.cliPath,
                    arguments: ["version", "--batch"],
                    timeout: 20
                )
                let output = SensitiveDataRedactor.redact(result.combinedOutput)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.maaVersionSummary = result.exitCode == 0 && !output.isEmpty
                    ? output
                    : "检测失败：\(output.isEmpty ? "退出码 \(result.exitCode)" : output)"
                if showResult {
                    self.showBanner(result.exitCode == 0 ? "MAA 环境检测完成" : "MAA 环境检测失败")
                }
            } catch {
                self.maaVersionSummary = "检测失败：\(error.localizedDescription)"
                if showResult { self.showBanner("MAA 环境检测失败：\(error.localizedDescription)") }
            }
            self.isCheckingMAAEnvironment = false
        }
    }

    func updateMAACore() {
        reloadActivityHistory()
        guard !isWorkflowRunning, !applicationUpdateState.blocksWorkflow else { return }
        guard FileManager.default.isExecutableFile(atPath: configuration.cliPath) else {
            showBanner("找不到可执行的 maa-cli")
            return
        }
        recordMAACoreUpdateAttempt()
        isRunning = true
        let runner = WorkflowRunner(directories: directories) { [weak self] event in
            self?.consume(event)
        }
        workflowTask = Task { [weak self] in
            guard let self else { return }
            _ = await runner.updateCore(cliPath: self.configuration.cliPath)
            self.isRunning = false
            self.workflowTask = nil
            self.showBanner(self.statusMessage)
            self.refreshMAAStatus()
            self.resumeAutomaticApplicationUpdateIfNeeded()
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    func setAutomaticMAAUpdatesEnabled(_ enabled: Bool) {
        configuration.maaUpdates.automaticallyUpdatesCoreAndResources = enabled
        scheduleSave()
        if enabled {
            resumeAutomaticMAAUpdateIfNeeded()
        } else {
            automaticMAAUpdateWakeTask?.cancel()
            automaticMAAUpdateWakeTask = nil
        }
    }

    private func synchronizeSchedules() {
        enqueueScheduleSynchronization(debounce: false)
    }

    private func restorePreparedApplicationUpdateOrCheck() {
        guard !applicationUpdateState.isBusy else { return }
        applicationUpdateState = .checking
        applicationUpdateTask = Task { [weak self] in
            guard let self else { return }
            if let prepared = await self.softwareUpdateService.restorePreparedUpdate(directories: self.directories) {
                self.applicationUpdateState = .ready(prepared)
            } else {
                await self.performApplicationUpdateCheck(showResult: false)
            }
            self.applicationUpdateTask = nil
            self.resumeAutomaticApplicationUpdateIfNeeded()
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    private func performApplicationUpdateCheck(showResult: Bool) async {
        do {
            if let release = try await softwareUpdateService.check() {
                applicationUpdateState = .available(release)
                if configuration.applicationUpdates.automaticallyDownloadsUpdates {
                    if isWorkflowRunning {
                        showBanner("发现 AutoMAA v\(release.version)，将在当前流程结束后自动下载")
                    } else {
                        showBanner("发现 AutoMAA v\(release.version)，正在自动下载并校验")
                        await prepareApplicationUpdate(release)
                    }
                } else {
                    showBanner("发现 AutoMAA v\(release.version)，可在全局设置中更新")
                }
            } else {
                applicationUpdateState = .upToDate
                if showResult { showBanner("AutoMAA 已是最新版本") }
            }
        } catch is CancellationError {
            applicationUpdateState = .idle
        } catch {
            applicationUpdateState = showResult ? .failed(error.localizedDescription) : .idle
            if showResult { showBanner("检查更新失败：\(error.localizedDescription)") }
        }
    }

    private func prepareApplicationUpdate(_ release: SoftwareUpdateRelease) async {
        do {
            try validateAutomaticUpdateAvailability()
            applicationUpdateState = .downloading(release)
            let prepared = try await softwareUpdateService.prepare(release, directories: directories)
            applicationUpdateState = .ready(prepared)
            showBanner("v\(release.version) 已下载并通过校验，可以重启更新")
        } catch is CancellationError {
            applicationUpdateState = .available(release)
        } catch {
            applicationUpdateState = .failed(error.localizedDescription)
            showBanner("下载更新失败：\(error.localizedDescription)")
        }
    }

    private func resumeAutomaticApplicationUpdateIfNeeded() {
        guard configuration.applicationUpdates.automaticallyDownloadsUpdates,
              !isWorkflowRunning,
              applicationUpdateTask == nil,
              case let .available(release) = applicationUpdateState
        else { return }
        downloadApplicationUpdate(release)
    }

    private func resumeAutomaticMAAUpdateIfNeeded(now: Date = Date()) {
        automaticMAAUpdateWakeTask?.cancel()
        automaticMAAUpdateWakeTask = nil
        guard configuration.maaUpdates.automaticallyUpdatesCoreAndResources,
              automaticMAAUpdateTask == nil,
              workflowTask == nil,
              applicationUpdateTask == nil,
              !applicationUpdateState.isBusy,
              !isWorkflowRunning
        else { return }

        let persistedAttempt = maaMaintenanceStore.load().lastCoreUpdateAttempt
        let lastAttempt = [persistedAttempt, lastMAACoreUpdateAttempt].compactMap { $0 }.max()
        let nextAttempt = AutomaticMAAUpdatePolicy.nextAttemptDate(
            lastAttempt: lastAttempt,
            now: now
        )
        guard nextAttempt <= now else {
            scheduleAutomaticMAAUpdateWake(at: nextAttempt, now: now)
            return
        }

        let nextScheduledRun = configuration.plans.compactMap {
            PlanScheduleFormatter.nextRunDate($0.schedule, after: now)
        }.min()
        guard AutomaticMAAUpdatePolicy.canStart(
            enabled: true,
            lastAttempt: lastAttempt,
            nextScheduledRun: nextScheduledRun,
            now: now
        ) else {
            if let nextScheduledRun {
                scheduleAutomaticMAAUpdateWake(
                    at: nextScheduledRun.addingTimeInterval(
                        AutomaticMAAUpdatePolicy.scheduledRunSafetyWindow
                    ),
                    now: now
                )
            }
            return
        }
        guard !ProcessLock.isHeld(at: directories.lock) else {
            scheduleAutomaticMAAUpdateWake(at: now.addingTimeInterval(15 * 60), now: now)
            return
        }
        guard FileManager.default.isExecutableFile(atPath: configuration.cliPath) else {
            scheduleAutomaticMAAUpdateWake(at: now.addingTimeInterval(60 * 60), now: now)
            return
        }

        recordMAACoreUpdateAttempt(at: now)
        isRunning = true
        let cliPath = configuration.cliPath
        let runner = WorkflowRunner(directories: directories) { [weak self] event in
            self?.consume(event)
        }
        automaticMAAUpdateTask = Task { [weak self] in
            let succeeded = await runner.updateCore(cliPath: cliPath)
            guard let self else { return }
            let cancelled = Task.isCancelled
            self.isRunning = false
            self.automaticMAAUpdateTask = nil
            self.refreshMAAStatus()
            if !succeeded, !cancelled {
                self.showBanner("MAA 自动更新未完成；已记录到活动记录，稍后可以在全局设置中重试")
            }
            self.resumeAutomaticApplicationUpdateIfNeeded()
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    private func scheduleAutomaticMAAUpdateWake(at date: Date, now: Date) {
        guard configuration.maaUpdates.automaticallyUpdatesCoreAndResources else { return }
        let delay = max(1, date.timeIntervalSince(now))
        automaticMAAUpdateWakeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.automaticMAAUpdateWakeTask = nil
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    private func recordMAACoreUpdateAttempt(at date: Date = Date()) {
        lastMAACoreUpdateAttempt = date
        try? maaMaintenanceStore.save(.init(lastCoreUpdateAttempt: date))
    }

    func checkForApplicationUpdate(showResult: Bool = true) {
        guard !applicationUpdateState.isBusy else { return }
        applicationUpdateTask?.cancel()
        applicationUpdateState = .checking
        applicationUpdateTask = Task { [weak self] in
            guard let self else { return }
            await self.performApplicationUpdateCheck(showResult: showResult)
            self.applicationUpdateTask = nil
            self.resumeAutomaticApplicationUpdateIfNeeded()
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    func setAutomaticApplicationUpdatesEnabled(_ enabled: Bool) {
        configuration.applicationUpdates.automaticallyDownloadsUpdates = enabled
        scheduleSave()
        if enabled { resumeAutomaticApplicationUpdateIfNeeded() }
    }

    func copySupportDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(supportDiagnostics.text, forType: .string) {
            showBanner("诊断信息已复制，不含账号、路径和运行日志")
        } else {
            showBanner("无法复制诊断信息，请稍后重试")
        }
    }

    func downloadApplicationUpdate(_ release: SoftwareUpdateRelease) {
        reloadActivityHistory()
        guard !isWorkflowRunning, !applicationUpdateState.isBusy else { return }
        applicationUpdateTask?.cancel()
        applicationUpdateTask = Task { [weak self] in
            guard let self else { return }
            await self.prepareApplicationUpdate(release)
            self.applicationUpdateTask = nil
            self.resumeAutomaticMAAUpdateIfNeeded()
        }
    }

    func cancelApplicationUpdateDownload() {
        guard case .downloading = applicationUpdateState else { return }
        applicationUpdateTask?.cancel()
    }

    func restartAndInstallApplicationUpdate(_ prepared: PreparedSoftwareUpdate) {
        reloadActivityHistory()
        guard !isWorkflowRunning, !applicationUpdateState.isBusy else { return }
        do {
            saveNow(showConfirmation: false)
            try validateAutomaticUpdateAvailability()
            do {
                applicationUpdateInstallLock = try ProcessLock(url: directories.lock)
            } catch {
                throw SoftwareUpdateError.workflowRunning
            }
            let helperSource = bundledUpdaterURL
            guard FileManager.default.isExecutableFile(atPath: helperSource.path) else {
                throw SoftwareUpdateError.installerUnavailable
            }
            let helper = prepared.workingDirectory.appending(path: "AutoMAAUpdater")
            if FileManager.default.fileExists(atPath: helper.path) {
                try FileManager.default.removeItem(at: helper)
            }
            try FileManager.default.copyItem(at: helperSource, to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

            let logURL = prepared.workingDirectory.appending(path: "updater.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let logHandle = try FileHandle(forWritingTo: logURL)
            let process = Process()
            process.executableURL = helper
            process.arguments = [
                "--pid", String(ProcessInfo.processInfo.processIdentifier),
                "--current-app", Bundle.main.bundleURL.path,
                "--new-app", prepared.applicationURL.path,
                "--expected-version", prepared.release.version.description,
                "--result", softwareUpdateResultStore.url.path,
                "--lock", directories.lock.path,
            ]
            process.standardOutput = logHandle
            process.standardError = logHandle
            do {
                try process.run()
            } catch {
                try? logHandle.close()
                throw SoftwareUpdateError.installerLaunchFailed(error.localizedDescription)
            }
            try? logHandle.close()
            applicationUpdateState = .installing(prepared.release)
            NSApplication.shared.terminate(nil)
        } catch {
            applicationUpdateInstallLock = nil
            applicationUpdateState = .failed(error.localizedDescription)
            showBanner("无法开始更新：\(error.localizedDescription)")
        }
    }

    func cancelRun() {
        guard isRunning, let workflowTask else { return }
        if runningPlanID == nil {
            statusMessage = "正在停止当前更新操作"
        } else {
            statusMessage = "正在安全停止并释放当前连接"
            phase = .closing
        }
        workflowTask.cancel()
    }

    func resetToday() {
        do {
            try executionStateStore.reset()
            showBanner("今日完成记录已重置")
        } catch {
            showBanner("重置失败：\(error.localizedDescription)")
        }
    }

    func clearActivityHistory() {
        do {
            try historyStore.clear()
            activityEntries = []
        } catch {
            showBanner("清理活动记录失败：\(error.localizedDescription)")
        }
    }

    func reloadActivityHistory() {
        let entries = historyStore.load()
        if entries != activityEntries {
            activityEntries = entries
        }
        refreshExternalRunState()
    }

    func monitorExternalActivity() async {
        while !Task.isCancelled {
            reloadActivityHistory()
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    func addAccount(to clientID: UUID) {
        guard let index = configuration.clients.firstIndex(where: { $0.id == clientID }) else { return }
        let name = uniqueName(
            "新账号",
            among: configuration.clients[index].accounts.map(\.name)
        )
        let account = AccountConfiguration(name: name)
        configuration.clients[index].accounts.append(account)
        selection = .account(clientID, account.id)
    }

    func addPlan(_ template: AutomationPlan = .lightRoutine) {
        var plan = template
        plan.id = UUID()
        plan.name = uniqueName(template.displayName, among: configuration.plans.map(\.name))
        plan.schedule.enabled = false
        configuration.plans.append(plan)
        selection = .plan(plan.id)
    }

    func duplicatePlan(_ planID: UUID) {
        guard var plan = configuration.plans.first(where: { $0.id == planID }) else { return }
        plan.id = UUID()
        plan.name = uniqueName("\(plan.displayName) 副本", among: configuration.plans.map(\.name))
        plan.schedule.enabled = false
        configuration.plans.append(plan)
        selection = .plan(plan.id)
    }

    func deletePlan(_ planID: UUID) {
        configuration.plans.removeAll { $0.id == planID }
        if currentPlanID == planID {
            currentPlanID = configuration.plans.first?.id
        }
        selection = .overview
        guard saveNow(showConfirmation: false) else { return }
        enqueueScheduleSynchronization(debounce: false)
    }

    func movePlan(_ planID: UUID, by offset: Int) {
        guard let index = configuration.plans.firstIndex(where: { $0.id == planID }) else { return }
        let destination = index + offset
        guard configuration.plans.indices.contains(destination) else { return }
        configuration.plans.swapAt(index, destination)
    }

    func addClient() {
        let client = ClientConfiguration(
            name: uniqueName("新客户端", among: configuration.clients.map(\.name)),
            kind: .official,
            appPath: "",
            profileName: uniqueProfileName(),
            accounts: []
        )
        configuration.clients.append(client)
        selection = .client(client.id)
    }

    func deleteClient(_ clientID: UUID) {
        let accountIDs = Set(configuration.clients.first(where: { $0.id == clientID })?.accounts.map(\.id) ?? [])
        configuration.clients.removeAll { $0.id == clientID }
        for index in configuration.plans.indices {
            configuration.plans[index].accountIDs.subtract(accountIDs)
        }
        selection = .overview
        saveNow(showConfirmation: false)
    }

    func moveClient(_ clientID: UUID, by offset: Int) {
        guard let index = configuration.clients.firstIndex(where: { $0.id == clientID }) else { return }
        let destination = index + offset
        guard configuration.clients.indices.contains(destination) else { return }
        configuration.clients.swapAt(index, destination)
    }

    func moveAccount(clientID: UUID, accountID: UUID, by offset: Int) {
        guard let clientIndex = configuration.clients.firstIndex(where: { $0.id == clientID }),
              let accountIndex = configuration.clients[clientIndex].accounts.firstIndex(where: { $0.id == accountID })
        else { return }
        let destination = accountIndex + offset
        guard configuration.clients[clientIndex].accounts.indices.contains(destination) else { return }
        configuration.clients[clientIndex].accounts.swapAt(accountIndex, destination)
    }

    func deleteAccount(clientID: UUID, accountID: UUID) {
        guard let index = configuration.clients.firstIndex(where: { $0.id == clientID }) else { return }
        configuration.clients[index].accounts.removeAll { $0.id == accountID }
        for planIndex in configuration.plans.indices {
            configuration.plans[planIndex].accountIDs.remove(accountID)
        }
        selection = .client(clientID)
    }

    func setPlanScheduleEnabled(_ planID: UUID, _ enabled: Bool) {
        reloadActivityHistory()
        guard !isWorkflowRunning else { return }
        if enabled,
           let issue = readinessIssues(for: planID).first(where: { $0.severity == .error }) {
            if let index = configuration.plans.firstIndex(where: { $0.id == planID }) {
                configuration.plans[index].schedule.enabled = false
            }
            showBanner("暂时无法启用定时运行：\(issue.message)")
            return
        }
        guard let index = configuration.plans.firstIndex(where: { $0.id == planID }) else { return }
        let schedule = configuration.plans[index].schedule
        if enabled, let problem = PlanScheduleValidator.problem(in: schedule) {
            showBanner("暂时无法启用定时运行：\(problem.message(planName: configuration.plans[index].displayName))")
            return
        }
        if enabled, let conflict = scheduleConflict(planID: planID, schedule: schedule) {
            showBanner("暂时无法启用：与「\(conflict.firstPlanName)」的\(conflict.slot.weekday.title)定时运行冲突")
            return
        }
        configuration.plans[index].schedule.enabled = enabled
        guard saveNow(showConfirmation: false) else { return }
        enqueueScheduleSynchronization(
            feedback: enabled ? .enabled(planID) : .disabled(planID),
            debounce: false
        )
    }

    func setPlanScheduleRuleTime(_ planID: UUID, ruleID: UUID, hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
        updatePlanSchedule(planID) { schedule in
            guard let index = schedule.rules.firstIndex(where: { $0.id == ruleID }) else { return }
            schedule.rules[index].hour = hour
            schedule.rules[index].minute = minute
        }
    }

    func togglePlanScheduleWeekday(_ planID: UUID, ruleID: UUID, weekday: ScheduleWeekday) {
        updatePlanSchedule(planID) { schedule in
            guard let index = schedule.rules.firstIndex(where: { $0.id == ruleID }) else { return }
            if schedule.rules[index].weekdays.contains(weekday) {
                schedule.rules[index].weekdays.remove(weekday)
            } else {
                schedule.rules[index].weekdays.insert(weekday)
            }
        }
    }

    func addPlanScheduleRule(_ planID: UUID) {
        guard let plan = configuration.plans.first(where: { $0.id == planID }),
              let weekday = ScheduleWeekday.allCases.first(where: { !plan.schedule.scheduledWeekdays.contains($0) })
        else {
            showBanner("每个星期都已有定时时段；同一方案每天最多运行一次")
            return
        }
        let reference = plan.schedule.rules.last
        updatePlanSchedule(planID, debounce: false) { schedule in
            schedule.rules.append(.init(
                weekdays: [weekday],
                hour: reference?.hour ?? 8,
                minute: reference?.minute ?? 0
            ))
        }
    }

    func removePlanScheduleRule(_ planID: UUID, ruleID: UUID) {
        guard let plan = configuration.plans.first(where: { $0.id == planID }), plan.schedule.rules.count > 1 else {
            showBanner("至少需要保留一个定时时段")
            return
        }
        updatePlanSchedule(planID, debounce: false) { schedule in
            schedule.rules.removeAll { $0.id == ruleID }
        }
    }

    private func updatePlanSchedule(
        _ planID: UUID,
        debounce: Bool = true,
        _ update: (inout PlanSchedule) -> Void
    ) {
        reloadActivityHistory()
        guard !isWorkflowRunning,
              let index = configuration.plans.firstIndex(where: { $0.id == planID })
        else { return }
        var schedule = configuration.plans[index].schedule
        update(&schedule)
        guard schedule != configuration.plans[index].schedule else { return }
        if let problem = PlanScheduleValidator.problem(in: schedule) {
            showBanner(problem.message(planName: configuration.plans[index].displayName))
            return
        }
        if schedule.enabled, let conflict = scheduleConflict(planID: planID, schedule: schedule) {
            let time = PlanScheduleFormatter.time(hour: conflict.slot.hour, minute: conflict.slot.minute)
            showBanner("无法应用：与「\(conflict.firstPlanName)」的\(conflict.slot.weekday.title) \(time) 冲突")
            return
        }
        configuration.plans[index].schedule = schedule
        guard saveNow(showConfirmation: false) else { return }
        if schedule.enabled || installedPlanIDs.contains(planID) {
            enqueueScheduleSynchronization(feedback: .changed(planID), debounce: debounce)
        }
    }

    private func enqueueScheduleSynchronization(
        feedback: ScheduleSynchronizationFeedback? = nil,
        debounce: Bool
    ) {
        guard FileManager.default.isExecutableFile(atPath: runnerExecutableURL.path) else {
            if feedback != nil { showBanner("找不到 AutoMAARunner，无法配置定时运行") }
            return
        }
        scheduleSynchronizationRevision += 1
        let revision = scheduleSynchronizationRevision
        let predecessor = scheduleSynchronizationTask
        isSynchronizingSchedules = true
        scheduleSynchronizationTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(350))
            }
            if let predecessor { await predecessor.value }
            guard !Task.isCancelled, let self,
                  revision == self.scheduleSynchronizationRevision
            else { return }
            while self.isRunning || ProcessLock.isHeld(at: self.directories.lock) {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard revision == self.scheduleSynchronizationRevision else { return }
            }
            do {
                try await self.launchAgentManager.synchronize(
                    runnerURL: self.runnerExecutableURL,
                    plans: self.configuration.plans
                )
                guard revision == self.scheduleSynchronizationRevision else { return }
                self.installedPlanIDs = self.launchAgentManager.installedPlanIDs
                if let feedback { self.showScheduleSynchronizationFeedback(feedback) }
            } catch {
                guard revision == self.scheduleSynchronizationRevision else { return }
                self.installedPlanIDs = self.launchAgentManager.installedPlanIDs
                self.showBanner("定时任务同步失败：\(error.localizedDescription)")
            }
            guard revision == self.scheduleSynchronizationRevision else { return }
            self.isSynchronizingSchedules = false
            self.scheduleSynchronizationTask = nil
        }
    }

    private func showScheduleSynchronizationFeedback(_ feedback: ScheduleSynchronizationFeedback) {
        let planID = switch feedback {
        case let .enabled(id), let .disabled(id), let .changed(id): id
        }
        let name = configuration.plans.first(where: { $0.id == planID })?.displayName ?? "方案"
        switch feedback {
        case .enabled:
            showBanner("「\(name)」定时运行已启用")
        case .disabled:
            showBanner("「\(name)」定时运行已关闭")
        case .changed:
            let schedule = configuration.plans.first(where: { $0.id == planID })?.schedule
            showBanner("「\(name)」已改为 \(schedule.map(PlanScheduleFormatter.summary) ?? "新的周计划")")
        }
    }

    private var runnerExecutableURL: URL {
        if let configuredRunnerExecutableURL { return configuredRunnerExecutableURL }
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/MacOS/AutoMAARunner")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        if let executable = Bundle.main.executableURL {
            let sibling = executable.deletingLastPathComponent().appending(path: "AutoMAARunner")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        return bundled
    }

    private var bundledUpdaterURL: URL {
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/MacOS/AutoMAAUpdater")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        if let executable = Bundle.main.executableURL {
            let sibling = executable.deletingLastPathComponent().appending(path: "AutoMAAUpdater")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        return bundled
    }

    private func validateAutomaticUpdateAvailability() throws {
        if let applicationUpdateAvailabilityValidator {
            try applicationUpdateAvailabilityValidator()
            return
        }
        try SoftwareUpdateInstaller.validateInstallLocation(Bundle.main.bundleURL)
        guard FileManager.default.isExecutableFile(atPath: bundledUpdaterURL.path) else {
            throw SoftwareUpdateError.installerUnavailable
        }
    }

    private func consume(_ event: RunnerEvent) {
        externalRunState = nil
        phase = event.phase
        statusMessage = event.message
        progress = event.progress
        activityEntries.append(event.log)
        if activityEntries.count > 1_000 { activityEntries.removeFirst(activityEntries.count - 1_000) }
    }

    private func refreshExternalRunState() {
        guard !isRunning else {
            externalRunState = nil
            return
        }
        guard ProcessLock.isHeld(at: directories.lock) else {
            let ended = externalRunState != nil
            externalRunState = nil
            if ended {
                resumeAutomaticApplicationUpdateIfNeeded()
                resumeAutomaticMAAUpdateIfNeeded()
            }
            return
        }
        let latest = latestExternalRunEntry()
        externalRunState = ExternalRunState(
            runID: latest?.runID,
            planID: latest?.planID,
            phase: latest?.phase ?? .preparing,
            message: latest?.message ?? "定时任务正在启动",
            progress: latest?.progress ?? 0
        )
    }

    private func latestExternalRunEntry() -> LogEntry? {
        guard let latest = activityEntries.last else { return nil }
        guard let lockDate = try? directories.lock
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        else { return latest }
        return latest.timestamp >= lockDate.addingTimeInterval(-1) ? latest : nil
    }

    private func normalizedProfile(_ value: String) -> String {
        MAAProfileName.normalize(value)
    }

    private func attentionBanner(_ messages: [String]) -> String {
        guard let first = messages.first else { return "流程完成" }
        let firstLine = first.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? first
        let suffix = messages.count > 1 ? "（另有 \(messages.count - 1) 项，请查看活动记录）" : ""
        return "需要手动处理：\(String(firstLine.prefix(180)))\(suffix)"
    }

    private func noticeBanner(_ notices: [WorkflowNotice]) -> String {
        guard let first = notices.first else { return "流程已完成" }
        let suffix = notices.count > 1 ? "（另有 \(notices.count - 1) 项，请查看活动记录）" : ""
        return "\(String(first.message.prefix(180)))\(suffix)"
    }

    private func uniqueProfileName() -> String {
        var index = configuration.clients.count + 1
        let used = Set(configuration.clients.map { normalizedProfile($0.profileName) })
        while used.contains("client-\(index)") { index += 1 }
        return "client-\(index)"
    }

    private func uniqueName(_ base: String, among names: [String]) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmedBase.isEmpty ? "未命名" : trimmedBase
        let used = Set(names.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        if !used.contains(candidate.lowercased()) { return candidate }
        var index = 2
        while used.contains("\(candidate) \(index)".lowercased()) { index += 1 }
        return "\(candidate) \(index)"
    }

    private func showBanner(_ message: String) {
        bannerMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.bannerMessage == message else { return }
            self?.bannerMessage = nil
        }
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
