import Darwin
import Foundation

public enum LaunchAgentError: LocalizedError, Equatable {
    case invalidSchedule(plan: String, problem: PlanScheduleProblem)
    case duplicateSchedule(first: String, second: String, slot: WeeklyScheduleSlot)
    case transientRunner
    case systemTimeout(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSchedule(plan, problem):
            problem.message(planName: plan)
        case let .duplicateSchedule(first, second, slot):
            "「\(first)」与「\(second)」都设置为\(slot.weekday.title) \(PlanScheduleFormatter.time(hour: slot.hour, minute: slot.minute))，请错开运行时间"
        case .transientRunner:
            "AutoMAARunner 位于临时目录，不能注册系统定时任务；请先将 AutoMAA 移到稳定位置"
        case let .systemTimeout(operation):
            "系统定时服务\(operation)超时，请重试同步"
        }
    }
}

public struct LaunchAgentManager: Sendable {
    public static let labelPrefix = "com.rememorio.AutoMAA.runner"

    private var service: LaunchAgentService?
    private let directories: AppDirectories
    private let launchAgentsDirectory: URL
    private let systemIntegrationEnabled: Bool
    private let runnerIdentity: String

    public init(
        directories: AppDirectories = .init(),
        launchAgentsDirectory: URL? = nil,
        systemIntegrationEnabled: Bool = true,
        runnerIdentity: String = "development"
    ) {
        self.directories = directories
        self.systemIntegrationEnabled = systemIntegrationEnabled
        self.runnerIdentity = runnerIdentity
        if systemIntegrationEnabled {
            service = LaunchAgentService { arguments in
                try await CommandRunner().run(executable: "/bin/launchctl", arguments: arguments,
                                              environment: ["LC_ALL": "C"], timeout: 10)
            }
        }
        self.launchAgentsDirectory = launchAgentsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    }

    init(directories: AppDirectories, launchAgentsDirectory: URL,
         launchctl: @escaping @Sendable ([String]) async throws -> CommandResult) {
        self.init(directories: directories, launchAgentsDirectory: launchAgentsDirectory, systemIntegrationEnabled: false)
        self.service = LaunchAgentService(run: launchctl)
    }

    public func label(planID: UUID) -> String {
        "\(Self.labelPrefix).\(planID.uuidString.lowercased())"
    }

    public func plistURL(planID: UUID) -> URL {
        launchAgentsDirectory.appending(path: "\(label(planID: planID)).plist")
    }

    public func install(runnerURL: URL, plan: AutomationPlan) async throws {
        try validate(runnerURL: runnerURL)
        try validate(plan)
        try directories.prepare()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plistURL = plistURL(planID: plan.id)
        var definition = propertyList(runnerURL: runnerURL, plan: plan)
        func writeDefinition() throws {
            let data = try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        }
        try await service?.bootOut(label: label(planID: plan.id))
        try writeDefinition()
        if let service {
            do {
                let result = try await service.command(["bootstrap", service.domain, plistURL.path], operation: "注册")
                guard result.succeeded else { throw CommandRunnerError.launchFailed(result.combinedOutput) }
            } catch {
                // launchd may already have received the request. Keep the label discoverable for removal or retry.
                definition["Disabled"] = true
                try writeDefinition()
                throw error
            }
        }
    }

    func propertyList(runnerURL: URL, plan: AutomationPlan) -> [String: Any] {
        [
            "Label": label(planID: plan.id),
            "ProgramArguments": [runnerURL.path, "--plan", plan.id.uuidString.lowercased()],
            "StartCalendarInterval": plan.schedule.slots.map {
                ["Weekday": $0.weekday.launchdValue, "Hour": $0.hour, "Minute": $0.minute]
            },
            "RunAtLoad": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "EnvironmentVariables": ["AUTOMAA_RUNNER_IDENTITY": runnerIdentity],
            "StandardOutPath": directories.logs.appending(path: "launchd-\(plan.id.uuidString.lowercased()).out.log").path,
            "StandardErrorPath": directories.logs.appending(path: "launchd-\(plan.id.uuidString.lowercased()).err.log").path,
        ]
    }

    public func uninstall(planID: UUID) async throws {
        try await uninstall(plistURL: plistURL(planID: planID))
    }

    public func synchronize(runnerURL: URL, plans: [AutomationPlan]) async throws {
        try validate(runnerURL: runnerURL)
        try validate(plans)
        let desired = Set(plans.filter(\.schedule.enabled).map(\.id))
        for planID in installedPlanIDs.subtracting(desired) {
            try await uninstall(planID: planID)
        }
        try await uninstallLegacyAgentIfNeeded()
        for plan in plans where plan.schedule.enabled {
            let current = isCurrent(runnerURL: runnerURL, plan: plan)
            let loaded = try await service?.isLoaded(label: label(planID: plan.id)) ?? true
            if !current || !loaded {
                try await install(runnerURL: runnerURL, plan: plan)
            }
        }
    }

    public var installedPlanIDs: Set<UUID> {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: launchAgentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let prefix = "\(Self.labelPrefix)."
        return Set(files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: String(name.dropFirst(prefix.count)))
        })
    }

    public func isInstalled(planID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: plistURL(planID: planID).path)
    }

    public func installedSlots(planID: UUID) -> Set<WeeklyScheduleSlot>? {
        guard let data = try? Data(contentsOf: plistURL(planID: planID)),
              let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let intervals: [[String: Any]]
        if let values = payload["StartCalendarInterval"] as? [[String: Any]] {
            intervals = values
        } else if let value = payload["StartCalendarInterval"] as? [String: Any] {
            intervals = [value]
        } else {
            return nil
        }
        let slots = intervals.compactMap { interval -> WeeklyScheduleSlot? in
            guard let weekdayValue = interval["Weekday"] as? Int,
                  let weekday = ScheduleWeekday.allCases.first(where: { $0.launchdValue == weekdayValue }),
                  let hour = interval["Hour"] as? Int,
                  let minute = interval["Minute"] as? Int
            else { return nil }
            return WeeklyScheduleSlot(weekday: weekday, hour: hour, minute: minute)
        }
        guard slots.count == intervals.count else { return nil }
        return Set(slots)
    }

    public func isCurrent(runnerURL: URL, plan: AutomationPlan) -> Bool {
        guard let data = try? Data(contentsOf: plistURL(planID: plan.id)),
              let installed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return NSDictionary(dictionary: installed).isEqual(to: propertyList(runnerURL: runnerURL, plan: plan))
    }

    private func validate(_ plans: [AutomationPlan]) throws {
        for plan in plans where plan.schedule.enabled {
            try validate(plan)
        }
        if let conflict = PlanScheduleValidator.firstConflict(in: plans) {
            throw LaunchAgentError.duplicateSchedule(
                first: conflict.firstPlanName,
                second: conflict.secondPlanName,
                slot: conflict.slot
            )
        }
    }

    private func validate(_ plan: AutomationPlan) throws {
        guard let problem = PlanScheduleValidator.problem(in: plan.schedule) else { return }
        throw LaunchAgentError.invalidSchedule(plan: plan.displayName, problem: problem)
    }

    private func validate(runnerURL: URL) throws {
        guard systemIntegrationEnabled else { return }
        let runnerURL = runnerURL.resolvingSymlinksInPath().standardizedFileURL
        let transientDirectories = [
            FileManager.default.temporaryDirectory,
            URL(filePath: "/private/tmp", directoryHint: .isDirectory),
            URL(filePath: "/private/var/folders", directoryHint: .isDirectory),
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL }
        guard transientDirectories.contains(where: { runnerURL.isDescendant(of: $0) }) else { return }
        throw LaunchAgentError.transientRunner
    }

    private func uninstallLegacyAgentIfNeeded() async throws {
        let url = launchAgentsDirectory.appending(path: "\(Self.labelPrefix).plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try await uninstall(plistURL: url)
    }

    private func uninstall(plistURL: URL) async throws {
        try await service?.bootOut(label: plistURL.deletingPathExtension().lastPathComponent)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}

private struct LaunchAgentService: Sendable {
    let run: @Sendable ([String]) async throws -> CommandResult
    var domain: String { "gui/\(getuid())" }

    func bootOut(label: String) async throws {
        let result = try await command(["bootout", "\(domain)/\(label)"], operation: "卸载")
        if !result.succeeded, try await isLoaded(label: label) {
            throw CommandRunnerError.launchFailed(result.combinedOutput)
        }
    }

    func isLoaded(label: String) async throws -> Bool {
        let result = try await command(["print", "\(domain)/\(label)"], operation: "查询")
        if result.succeeded { return true }
        if result.combinedOutput.contains("Could not find service \"\(label)\"") { return false }
        throw CommandRunnerError.launchFailed(result.combinedOutput)
    }

    func command(_ arguments: [String], operation: String) async throws -> CommandResult {
        let result = try await run(arguments)
        if result.cancelled { throw CancellationError() }
        if result.timedOut { throw LaunchAgentError.systemTimeout(operation) }
        return result
    }
}

private extension URL {
    func isDescendant(of directory: URL) -> Bool {
        let directoryPath = directory.path.hasSuffix("/") ? directory.path : "\(directory.path)/"
        return path.hasPrefix(directoryPath)
    }
}
