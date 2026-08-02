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
}

private enum ScheduleSynchronizationFeedback {
    case enabled(UUID)
    case disabled(UUID)
    case timeChanged(UUID, hour: Int, minute: Int)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published var selection: SidebarSelection = .overview
    @Published var activityEntries: [LogEntry]
    @Published var phase: RunnerPhase = .idle
    @Published var statusMessage = "等待开始"
    @Published var progress = 0.0
    @Published var isRunning = false
    @Published var runningPlanID: UUID?
    @Published var bannerMessage: String?
    @Published var installedPlanIDs: Set<UUID>
    @Published var lastReport: WorkflowReport?
    @Published private(set) var isSynchronizingSchedules = false
    @Published private(set) var maaVersionSummary = "尚未检测"
    @Published private(set) var isCheckingMAAEnvironment = false
    @Published private(set) var applicationUpdateState: ApplicationUpdateState = .idle

    let directories: AppDirectories
    let currentApplicationVersion: String
    let currentApplicationBuild: String
    let applicationUpdateRepository: String
    private let configurationStore: ConfigurationStore
    private let historyStore: HistoryStore
    private let executionStateStore: ExecutionStateStore
    private let launchAgentManager: LaunchAgentManager
    private let softwareUpdateService: SoftwareUpdateService
    private let softwareUpdateResultStore: SoftwareUpdateResultStore
    private let commandRunner = CommandRunner()
    private let configuredRunnerExecutableURL: URL?
    private var saveTask: Task<Void, Never>?
    private var workflowTask: Task<Void, Never>?
    private var applicationUpdateTask: Task<Void, Never>?
    private var scheduleSynchronizationTask: Task<Void, Never>?
    private var scheduleSynchronizationRevision = 0
    private var didPrepareApplication = false
    private let startupNotice: String?
    private let checksForUpdatesAutomatically: Bool

    init(
        directories: AppDirectories = .init(),
        launchAgentsDirectory: URL? = nil,
        managesSystemLaunchAgents: Bool = true,
        checksForUpdatesAutomatically: Bool = true,
        runnerExecutableURL: URL? = nil
    ) {
        self.directories = directories
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        configuredRunnerExecutableURL = runnerExecutableURL
        configurationStore = ConfigurationStore(directories: directories)
        historyStore = HistoryStore(directories: directories)
        executionStateStore = ExecutionStateStore(directories: directories)
        launchAgentManager = LaunchAgentManager(
            directories: directories,
            launchAgentsDirectory: launchAgentsDirectory,
            systemIntegrationEnabled: managesSystemLaunchAgents
        )
        currentApplicationVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发构建"
        currentApplicationBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "local"
        applicationUpdateRepository = Bundle.main.object(forInfoDictionaryKey: "AutoMAAUpdateRepository") as? String
            ?? SoftwareUpdateService.defaultRepository
        softwareUpdateService = SoftwareUpdateService(
            currentVersion: currentApplicationVersion,
            repository: applicationUpdateRepository
        )
        softwareUpdateResultStore = SoftwareUpdateResultStore(directories: directories)
        do {
            configuration = try configurationStore.load()
            startupNotice = nil
        } catch ConfigurationStoreError.unsupportedSchema {
            if let recovery = try? configurationStore.resetIncompatibleConfiguration() {
                configuration = recovery.configuration
                startupNotice = "配置协议已升级；旧配置已备份为 \(recovery.backupURL.lastPathComponent)"
            } else {
                configuration = .defaults
                startupNotice = "旧配置与当前版本不兼容，且无法创建备份；当前使用空配置"
            }
        } catch {
            if let recovery = try? configurationStore.resetIncompatibleConfiguration() {
                configuration = recovery.configuration
                startupNotice = "配置文件无法读取，已备份为 \(recovery.backupURL.lastPathComponent) 并恢复空配置"
            } else {
                configuration = .defaults
                startupNotice = "读取配置失败：\(error.localizedDescription)"
            }
        }
        activityEntries = historyStore.load()
        installedPlanIDs = launchAgentManager.installedPlanIDs
        try? MAAConfigurationWriter(directories: directories).prepare(configuration)
    }

    deinit {
        saveTask?.cancel()
        workflowTask?.cancel()
        applicationUpdateTask?.cancel()
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
        readinessIssues(for: selectedPlanID)
    }

    var selectedPlanID: UUID? {
        if case let .plan(id) = selection, configuration.plans.contains(where: { $0.id == id }) {
            return id
        }
        return configuration.plans.first?.id
    }

    var selectedPlan: AutomationPlan? {
        guard let selectedPlanID else { return nil }
        return configuration.plans.first(where: { $0.id == selectedPlanID })
    }

    func readinessIssues(for planID: UUID?) -> [ReadinessIssue] {
        ConfigurationValidator.readinessProblems(in: configuration, planID: planID)
    }

    var canRun: Bool {
        canRun(planID: selectedPlanID)
    }

    func canRun(planID: UUID?) -> Bool {
        planRunState(planID: planID) == .ready
    }

    func planRunState(planID: UUID?) -> PlanRunState {
        PlanRunState.resolve(
            planID: planID,
            isRunning: isRunning,
            runningPlanID: runningPlanID,
            hasReadinessError: readinessIssues(for: planID).contains { $0.severity == .error }
        )
    }

    func isPlanScheduleCurrent(_ plan: AutomationPlan) -> Bool {
        plan.schedule.enabled && launchAgentManager.isCurrent(runnerURL: runnerExecutableURL, plan: plan)
    }

    func scheduleConflict(planID: UUID, hour: Int, minute: Int) -> AutomationPlan? {
        configuration.plans.first {
            $0.id != planID
                && $0.schedule.enabled
                && $0.schedule.hour == hour
                && $0.schedule.minute == minute
        }
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
            if !isRunning {
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
        let runner = WorkflowRunner(directories: directories) { [weak self] event in
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
            if let fatalError = report.fatalError {
                self.showBanner(fatalError)
            } else if report.cancelled {
                self.showBanner("流程已安全停止，当前客户端和连接已清理")
            } else if report.isSuccess {
                let name = snapshot.plans.first(where: { $0.id == planID })?.displayName ?? "方案"
                self.showBanner("「\(name)」已全部完成")
            } else if !report.attentionMessages.isEmpty {
                self.showBanner(self.attentionBanner(report.attentionMessages))
            } else {
                self.showBanner("流程完成，但有 \(report.failedSteps) 个步骤失败")
            }
        }
    }

    func runSelectedPlan(resumeToday: Bool = true) {
        guard let selectedPlanID else {
            showBanner("请先创建自动化方案")
            return
        }
        runPlan(selectedPlanID, resumeToday: resumeToday)
    }

    func hotUpdate() {
        guard !isRunning else { return }
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
        }
    }

    func prepareApplication() {
        guard !didPrepareApplication else { return }
        didPrepareApplication = true
        synchronizeSchedules()
        if let startupNotice {
            showBanner(startupNotice)
        }
        if let result = softwareUpdateResultStore.loadAndClear() {
            applicationUpdateState = result.status == .success ? .upToDate : .failed(result.message)
            showBanner(result.message)
            refreshMAAStatus()
            return
        }
        refreshMAAStatus()
        if checksForUpdatesAutomatically {
            checkForApplicationUpdate(showResult: false)
        }
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
        guard !isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: configuration.cliPath) else {
            showBanner("找不到可执行的 maa-cli")
            return
        }
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
        }
    }

    private func synchronizeSchedules() {
        enqueueScheduleSynchronization(debounce: false)
    }

    func checkForApplicationUpdate(showResult: Bool = true) {
        guard !applicationUpdateState.isBusy else { return }
        applicationUpdateTask?.cancel()
        applicationUpdateState = .checking
        applicationUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let release = try await self.softwareUpdateService.check() {
                    self.applicationUpdateState = .available(release)
                    self.showBanner("发现 AutoMAA v\(release.version)，可在全局设置中更新")
                } else {
                    self.applicationUpdateState = .upToDate
                    if showResult { self.showBanner("AutoMAA 已是最新版本") }
                }
            } catch is CancellationError {
                self.applicationUpdateState = .idle
            } catch {
                self.applicationUpdateState = showResult ? .failed(error.localizedDescription) : .idle
                if showResult { self.showBanner("检查更新失败：\(error.localizedDescription)") }
            }
            self.applicationUpdateTask = nil
        }
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
        guard !isRunning, !applicationUpdateState.isBusy else { return }
        do {
            try validateAutomaticUpdateAvailability()
        } catch {
            applicationUpdateState = .failed(error.localizedDescription)
            showBanner(error.localizedDescription)
            return
        }
        applicationUpdateState = .downloading(release)
        applicationUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await self.softwareUpdateService.prepare(release, directories: self.directories)
                self.applicationUpdateState = .ready(prepared)
                self.showBanner("v\(release.version) 已下载并通过校验，可以重启更新")
            } catch is CancellationError {
                self.applicationUpdateState = .available(release)
            } catch {
                self.applicationUpdateState = .failed(error.localizedDescription)
                self.showBanner("下载更新失败：\(error.localizedDescription)")
            }
            self.applicationUpdateTask = nil
        }
    }

    func restartAndInstallApplicationUpdate(_ prepared: PreparedSoftwareUpdate) {
        guard !isRunning, !applicationUpdateState.isBusy else { return }
        do {
            saveNow(showConfirmation: false)
            try validateAutomaticUpdateAvailability()
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
        guard !isRunning else { return }
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
        if enabled, let conflict = scheduleConflict(
            planID: planID,
            hour: schedule.hour,
            minute: schedule.minute
        ) {
            showBanner("暂时无法启用：与「\(conflict.displayName)」的定时时间相同")
            return
        }
        configuration.plans[index].schedule.enabled = enabled
        guard saveNow(showConfirmation: false) else { return }
        enqueueScheduleSynchronization(
            feedback: enabled ? .enabled(planID) : .disabled(planID),
            debounce: false
        )
    }

    func setPlanScheduleTime(_ planID: UUID, hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute),
              let index = configuration.plans.firstIndex(where: { $0.id == planID })
        else { return }
        if configuration.plans[index].schedule.enabled,
           let conflict = scheduleConflict(planID: planID, hour: hour, minute: minute) {
            showBanner("无法使用该时间：与「\(conflict.displayName)」的定时运行冲突")
            return
        }
        guard configuration.plans[index].schedule.hour != hour
                || configuration.plans[index].schedule.minute != minute
        else { return }
        configuration.plans[index].schedule.hour = hour
        configuration.plans[index].schedule.minute = minute
        guard saveNow(showConfirmation: false) else { return }
        if configuration.plans[index].schedule.enabled || installedPlanIDs.contains(planID) {
            enqueueScheduleSynchronization(
                feedback: .timeChanged(planID, hour: hour, minute: minute),
                debounce: true
            )
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
        case let .enabled(id), let .disabled(id), let .timeChanged(id, _, _): id
        }
        let name = configuration.plans.first(where: { $0.id == planID })?.displayName ?? "方案"
        switch feedback {
        case .enabled:
            showBanner("「\(name)」定时运行已启用")
        case .disabled:
            showBanner("「\(name)」定时运行已关闭")
        case let .timeChanged(_, hour, minute):
            showBanner("「\(name)」已改为每天 \(String(format: "%02d:%02d", hour, minute)) 运行")
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
        try SoftwareUpdateInstaller.validateInstallLocation(Bundle.main.bundleURL)
        guard FileManager.default.isExecutableFile(atPath: bundledUpdaterURL.path) else {
            throw SoftwareUpdateError.installerUnavailable
        }
    }

    private func consume(_ event: RunnerEvent) {
        phase = event.phase
        statusMessage = event.message
        progress = event.progress
        activityEntries.append(event.log)
        if activityEntries.count > 1_000 { activityEntries.removeFirst(activityEntries.count - 1_000) }
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
