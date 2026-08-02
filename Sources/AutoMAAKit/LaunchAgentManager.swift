import Darwin
import Foundation

public enum LaunchAgentError: LocalizedError, Equatable {
    case invalidSchedule(plan: String)
    case duplicateSchedule(first: String, second: String, hour: Int, minute: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidSchedule(plan):
            "「\(plan)」的定时时间无效"
        case let .duplicateSchedule(first, second, hour, minute):
            "「\(first)」与「\(second)」都设置为每天 \(String(format: "%02d:%02d", hour, minute))，请错开运行时间"
        }
    }
}

public struct LaunchAgentManager: Sendable {
    public static let labelPrefix = "com.rememorio.AutoMAA.runner"

    private let commandRunner = CommandRunner()
    private let directories: AppDirectories
    private let launchAgentsDirectory: URL
    private let systemIntegrationEnabled: Bool

    public init(
        directories: AppDirectories = .init(),
        launchAgentsDirectory: URL? = nil,
        systemIntegrationEnabled: Bool = true
    ) {
        self.directories = directories
        self.systemIntegrationEnabled = systemIntegrationEnabled
        self.launchAgentsDirectory = launchAgentsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    }

    public func label(planID: UUID) -> String {
        "\(Self.labelPrefix).\(planID.uuidString.lowercased())"
    }

    public func plistURL(planID: UUID) -> URL {
        launchAgentsDirectory.appending(path: "\(label(planID: planID)).plist")
    }

    public func install(runnerURL: URL, plan: AutomationPlan) async throws {
        try validate(plan)
        try directories.prepare()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plistURL = plistURL(planID: plan.id)
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList(runnerURL: runnerURL, plan: plan),
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
        guard systemIntegrationEnabled else { return }

        let domain = launchdDomain
        try await bootOut(plistURL: plistURL)
        let result = try await commandRunner.run(
            executable: "/bin/launchctl",
            arguments: ["bootstrap", domain, plistURL.path],
            timeout: 10
        )
        guard result.exitCode == 0 else {
            try? FileManager.default.removeItem(at: plistURL)
            throw CommandRunnerError.launchFailed(result.combinedOutput)
        }
    }

    func propertyList(runnerURL: URL, plan: AutomationPlan) -> [String: Any] {
        [
            "Label": label(planID: plan.id),
            "ProgramArguments": [runnerURL.path, "--plan", plan.id.uuidString.lowercased()],
            "StartCalendarInterval": [
                "Hour": min(max(plan.schedule.hour, 0), 23),
                "Minute": min(max(plan.schedule.minute, 0), 59),
            ],
            "RunAtLoad": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": directories.logs.appending(path: "launchd-\(plan.id.uuidString.lowercased()).out.log").path,
            "StandardErrorPath": directories.logs.appending(path: "launchd-\(plan.id.uuidString.lowercased()).err.log").path,
        ]
    }

    public func uninstall(planID: UUID) async throws {
        try await uninstall(plistURL: plistURL(planID: planID))
    }

    public func synchronize(runnerURL: URL, plans: [AutomationPlan]) async throws {
        try validate(plans)
        let desired = Set(plans.filter(\.schedule.enabled).map(\.id))
        for planID in installedPlanIDs.subtracting(desired) {
            try await uninstall(planID: planID)
        }
        try await uninstallLegacyAgentIfNeeded()
        for plan in plans where plan.schedule.enabled {
            let current = isCurrent(runnerURL: runnerURL, plan: plan)
            let loaded: Bool
            if systemIntegrationEnabled {
                loaded = await isLoaded(label: label(planID: plan.id))
            } else {
                loaded = true
            }
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

    public func installedTime(planID: UUID) -> (hour: Int, minute: Int)? {
        guard let data = try? Data(contentsOf: plistURL(planID: planID)),
              let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let interval = payload["StartCalendarInterval"] as? [String: Any],
              let hour = interval["Hour"] as? Int,
              let minute = interval["Minute"] as? Int
        else { return nil }
        return (hour, minute)
    }

    public func isCurrent(runnerURL: URL, plan: AutomationPlan) -> Bool {
        guard let data = try? Data(contentsOf: plistURL(planID: plan.id)),
              let installed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return NSDictionary(dictionary: installed).isEqual(to: propertyList(runnerURL: runnerURL, plan: plan))
    }

    private func validate(_ plans: [AutomationPlan]) throws {
        var occupied: [Int: AutomationPlan] = [:]
        for plan in plans where plan.schedule.enabled {
            try validate(plan)
            let key = plan.schedule.hour * 60 + plan.schedule.minute
            if let existing = occupied[key] {
                throw LaunchAgentError.duplicateSchedule(
                    first: existing.displayName,
                    second: plan.displayName,
                    hour: plan.schedule.hour,
                    minute: plan.schedule.minute
                )
            }
            occupied[key] = plan
        }
    }

    private func validate(_ plan: AutomationPlan) throws {
        guard (0...23).contains(plan.schedule.hour), (0...59).contains(plan.schedule.minute) else {
            throw LaunchAgentError.invalidSchedule(plan: plan.displayName)
        }
    }

    private func uninstallLegacyAgentIfNeeded() async throws {
        let url = launchAgentsDirectory.appending(path: "\(Self.labelPrefix).plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try await uninstall(plistURL: url)
    }

    private func uninstall(plistURL: URL) async throws {
        if systemIntegrationEnabled {
            try await bootOut(plistURL: plistURL)
        }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private var launchdDomain: String {
        "gui/\(getuid())"
    }

    private func bootOut(plistURL: URL) async throws {
        let label = plistURL.deletingPathExtension().lastPathComponent
        do {
            let result = try await commandRunner.run(
                executable: "/bin/launchctl",
                arguments: ["bootout", launchdDomain, plistURL.path],
                timeout: 10
            )
            if result.exitCode != 0, await isLoaded(label: label) {
                throw CommandRunnerError.launchFailed(result.combinedOutput)
            }
        } catch {
            if await isLoaded(label: label) { throw error }
        }
    }

    private func isLoaded(label: String) async -> Bool {
        guard let result = try? await commandRunner.run(
            executable: "/bin/launchctl",
            arguments: ["print", "\(launchdDomain)/\(label)"],
            timeout: 10
        ) else { return false }
        return result.exitCode == 0
    }
}
