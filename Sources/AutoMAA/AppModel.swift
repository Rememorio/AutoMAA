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
    case logs
    case settings
}

struct ReadinessIssue: Identifiable {
    enum Severity {
        case warning
        case error
    }

    let id = UUID()
    let severity: Severity
    let message: String
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

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published var selection: SidebarSelection = .overview
    @Published var logs: [LogEntry]
    @Published var phase: RunnerPhase = .idle
    @Published var statusMessage = "等待开始"
    @Published var progress = 0.0
    @Published var isRunning = false
    @Published var runningPlanID: UUID?
    @Published var bannerMessage: String?
    @Published var installedPlanIDs: Set<UUID>
    @Published var lastReport: WorkflowReport?
    @Published private(set) var applicationUpdateState: ApplicationUpdateState = .idle

    let directories: AppDirectories
    let currentApplicationVersion: String
    let applicationUpdateRepository: String
    private let configurationStore: ConfigurationStore
    private let historyStore: HistoryStore
    private let executionStateStore: ExecutionStateStore
    private let launchAgentManager: LaunchAgentManager
    private let softwareUpdateService: SoftwareUpdateService
    private let softwareUpdateResultStore: SoftwareUpdateResultStore
    private var saveTask: Task<Void, Never>?
    private var workflowTask: Task<Void, Never>?
    private var applicationUpdateTask: Task<Void, Never>?
    private var didPrepareApplication = false

    init(directories: AppDirectories = .init()) {
        self.directories = directories
        configurationStore = ConfigurationStore(directories: directories)
        historyStore = HistoryStore(directories: directories)
        executionStateStore = ExecutionStateStore(directories: directories)
        launchAgentManager = LaunchAgentManager(directories: directories)
        currentApplicationVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发构建"
        applicationUpdateRepository = Bundle.main.object(forInfoDictionaryKey: "AutoMAAUpdateRepository") as? String
            ?? SoftwareUpdateService.defaultRepository
        softwareUpdateService = SoftwareUpdateService(
            currentVersion: currentApplicationVersion,
            repository: applicationUpdateRepository
        )
        softwareUpdateResultStore = SoftwareUpdateResultStore(directories: directories)
        configuration = (try? configurationStore.load()) ?? .defaults
        logs = historyStore.load()
        installedPlanIDs = launchAgentManager.installedPlanIDs
        try? MAAConfigurationWriter(directories: directories).prepare(configuration)
    }

    deinit {
        saveTask?.cancel()
        workflowTask?.cancel()
        applicationUpdateTask?.cancel()
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
        var result: [ReadinessIssue] = []
        let clientIDs = configuration.clients.map(\.id)
        let accountIDs = configuration.clients.flatMap { $0.accounts.map(\.id) }
        let planIDs = configuration.plans.map(\.id)
        if Set(clientIDs).count != clientIDs.count {
            result.append(.init(severity: .error, message: "客户端标识重复，请删除并重新添加重复项"))
        }
        if Set(accountIDs).count != accountIDs.count {
            result.append(.init(severity: .error, message: "账号标识重复，请删除并重新添加重复项"))
        }
        if Set(planIDs).count != planIDs.count {
            result.append(.init(severity: .error, message: "自动化方案标识重复，请删除并重新添加重复项"))
        }
        if !FileManager.default.isExecutableFile(atPath: configuration.cliPath) {
            result.append(.init(severity: .error, message: "找不到可执行的 maa-cli：\(configuration.cliPath)"))
        }
        guard let planID, let plan = configuration.plans.first(where: { $0.id == planID }) else {
            result.append(.init(severity: .error, message: "至少需要创建一个自动化方案"))
            return result
        }
        if plan.enabledTasks.isEmpty {
            result.append(.init(severity: .error, message: "「\(plan.name)」没有启用任何步骤"))
        }
        let activeClients = configuration.clients.filter { client in
            client.enabled && client.accounts.contains(where: plan.includes)
        }
        if activeClients.isEmpty {
            result.append(.init(severity: .error, message: "「\(plan.name)」没有可执行的账号"))
        }
        for client in activeClients {
            if !FileManager.default.fileExists(atPath: client.appPath) {
                result.append(.init(severity: .warning, message: "\(client.name) 的应用路径不存在，运行时会跳过该客户端"))
            }
            if client.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(severity: .warning, message: "\(client.name) 缺少 Bundle Identifier，运行时会跳过该客户端"))
            }
            if (try? PortAddress(client.address)) == nil {
                result.append(.init(severity: .warning, message: "\(client.name) 的 MaaTools 地址无效，运行时会跳过该客户端"))
            }
            let enabledAccounts = client.accounts.filter(\.enabled)
            let targetAccounts = client.accounts.filter(plan.includes)
            if targetAccounts.isEmpty {
                result.append(.init(severity: .warning, message: "\(client.name) 没有启用的账号"))
            }
            if enabledAccounts.count > 1 {
                for account in targetAccounts where account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(severity: .warning, message: "\(account.name) 缺少唯一账号片段，运行时会跳过该账号"))
                }
                let selectors = enabledAccounts
                    .map { $0.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                if Set(selectors).count != selectors.count {
                    result.append(.init(severity: .error, message: "\(client.name) 的账号片段不能重复"))
                }
            }
        }
        let profileNames = configuration.clients.map { normalizedProfile($0.profileName) }
        if Set(profileNames).count != profileNames.count {
            result.append(.init(severity: .error, message: "每个客户端需要使用不同的 MAA Profile 名称"))
        }
        return result
    }

    var canRun: Bool {
        canRun(planID: selectedPlanID)
    }

    func canRun(planID: UUID?) -> Bool {
        !isRunning && !readinessIssues(for: planID).contains { $0.severity == .error }
    }

    func isPlanScheduleCurrent(_ plan: AutomationPlan) -> Bool {
        guard let installed = launchAgentManager.installedTime(planID: plan.id) else { return false }
        return installed.hour == plan.schedule.hour && installed.minute == plan.schedule.minute
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
            try MAAConfigurationWriter(directories: directories).prepare(configuration)
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
            if let fatalError = report.fatalError {
                self.showBanner(fatalError)
            } else if report.cancelled {
                self.showBanner("流程已安全停止，当前客户端和连接已清理")
            } else if report.isSuccess {
                let name = snapshot.plans.first(where: { $0.id == planID })?.name ?? "方案"
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
        if let result = softwareUpdateResultStore.loadAndClear() {
            applicationUpdateState = result.status == .success ? .upToDate : .failed(result.message)
            showBanner(result.message)
            return
        }
        checkForApplicationUpdate(showResult: false)
    }

    private func synchronizeSchedules() {
        guard FileManager.default.isExecutableFile(atPath: runnerExecutableURL.path) else { return }
        let plans = configuration.plans
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.launchAgentManager.synchronize(runnerURL: self.runnerExecutableURL, plans: plans)
                self.installedPlanIDs = self.launchAgentManager.installedPlanIDs
            } catch {
                self.showBanner("定时任务同步失败：\(error.localizedDescription)")
            }
        }
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
        statusMessage = "正在安全停止并释放当前连接"
        phase = .closing
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

    func clearLogs() {
        do {
            try historyStore.clear()
            logs = []
        } catch {
            showBanner("清理日志失败：\(error.localizedDescription)")
        }
    }

    func addAccount(to clientID: UUID) {
        guard let index = configuration.clients.firstIndex(where: { $0.id == clientID }) else { return }
        let number = configuration.clients[index].accounts.count + 1
        let name = number == 1 ? "新账号" : "新账号 \(number)"
        let account = AccountConfiguration(name: name)
        configuration.clients[index].accounts.append(account)
        selection = .account(clientID, account.id)
    }

    func addPlan(_ template: AutomationPlan = .lightRoutine) {
        var plan = template
        plan.id = UUID()
        plan.name = uniquePlanName(template.name)
        plan.schedule.enabled = false
        configuration.plans.append(plan)
        selection = .plan(plan.id)
    }

    func duplicatePlan(_ planID: UUID) {
        guard var plan = configuration.plans.first(where: { $0.id == planID }) else { return }
        plan.id = UUID()
        plan.name = uniquePlanName("\(plan.name) 副本")
        plan.schedule.enabled = false
        configuration.plans.append(plan)
        selection = .plan(plan.id)
    }

    func deletePlan(_ planID: UUID) {
        configuration.plans.removeAll { $0.id == planID }
        selection = .overview
        guard saveNow(showConfirmation: false) else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await self.launchAgentManager.uninstall(planID: planID)
            self.installedPlanIDs = self.launchAgentManager.installedPlanIDs
        }
    }

    func movePlan(_ planID: UUID, by offset: Int) {
        guard let index = configuration.plans.firstIndex(where: { $0.id == planID }) else { return }
        let destination = index + offset
        guard configuration.plans.indices.contains(destination) else { return }
        configuration.plans.swapAt(index, destination)
    }

    func addClient() {
        let client = ClientConfiguration(
            name: "新客户端",
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
        configuration.plans[index].schedule.enabled = enabled
        let plan = configuration.plans[index]
        guard saveNow(showConfirmation: false) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                if enabled {
                    try await self.launchAgentManager.install(
                        runnerURL: self.runnerExecutableURL,
                        plan: plan
                    )
                } else {
                    try await self.launchAgentManager.uninstall(planID: planID)
                }
                self.installedPlanIDs = self.launchAgentManager.installedPlanIDs
                let name = self.configuration.plans.first(where: { $0.id == planID })?.name ?? "方案"
                self.showBanner(enabled ? "「\(name)」定时运行已启用" : "「\(name)」定时运行已关闭")
            } catch {
                if let index = self.configuration.plans.firstIndex(where: { $0.id == planID }) {
                    self.configuration.plans[index].schedule.enabled = false
                }
                self.installedPlanIDs = self.launchAgentManager.installedPlanIDs
                self.saveNow(showConfirmation: false)
                self.showBanner("定时任务配置失败：\(error.localizedDescription)")
            }
        }
    }

    func applyPlanSchedule(_ planID: UUID) {
        guard configuration.plans.first(where: { $0.id == planID })?.schedule.enabled == true else { return }
        setPlanScheduleEnabled(planID, true)
    }

    private var runnerExecutableURL: URL {
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
        logs.append(event.log)
        if logs.count > 1_000 { logs.removeFirst(logs.count - 1_000) }
    }

    private func normalizedProfile(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func attentionBanner(_ messages: [String]) -> String {
        guard let first = messages.first else { return "流程完成" }
        let firstLine = first.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? first
        let suffix = messages.count > 1 ? "（另有 \(messages.count - 1) 项，请查看日志）" : ""
        return "需要手动处理：\(String(firstLine.prefix(180)))\(suffix)"
    }

    private func uniqueProfileName() -> String {
        var index = configuration.clients.count + 1
        let used = Set(configuration.clients.map { normalizedProfile($0.profileName) })
        while used.contains("client-\(index)") { index += 1 }
        return "client-\(index)"
    }

    private func uniquePlanName(_ base: String) -> String {
        let used = Set(configuration.plans.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
        if !used.contains(base) { return base }
        var index = 2
        while used.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func showBanner(_ message: String) {
        bannerMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.bannerMessage == message else { return }
            self?.bannerMessage = nil
        }
    }
}
