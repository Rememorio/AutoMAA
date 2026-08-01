import Darwin
import Foundation

public struct LaunchAgentManager: Sendable {
    public static let labelPrefix = "com.rememorio.AutoMAA.runner"

    private let commandRunner = CommandRunner()
    private let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func label(planID: UUID) -> String {
        "\(Self.labelPrefix).\(planID.uuidString.lowercased())"
    }

    public func plistURL(planID: UUID) -> URL {
        launchAgentsDirectory.appending(path: "\(label(planID: planID)).plist")
    }

    public func install(runnerURL: URL, plan: AutomationPlan) async throws {
        try directories.prepare()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plistURL = plistURL(planID: plan.id)
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList(runnerURL: runnerURL, plan: plan),
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        let domain = "gui/\(getuid())"
        _ = try? await commandRunner.run(
            executable: "/bin/launchctl",
            arguments: ["bootout", domain, plistURL.path],
            timeout: 10
        )
        let result = try await commandRunner.run(
            executable: "/bin/launchctl",
            arguments: ["bootstrap", domain, plistURL.path],
            timeout: 10
        )
        guard result.exitCode == 0 else {
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
        let desired = Set(plans.filter(\.schedule.enabled).map(\.id))
        for planID in installedPlanIDs.subtracting(desired) {
            try await uninstall(planID: planID)
        }
        try await uninstallLegacyAgentIfNeeded()
        for plan in plans where plan.schedule.enabled {
            try await install(runnerURL: runnerURL, plan: plan)
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

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    }

    private func uninstallLegacyAgentIfNeeded() async throws {
        let url = launchAgentsDirectory.appending(path: "\(Self.labelPrefix).plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try await uninstall(plistURL: url)
    }

    private func uninstall(plistURL: URL) async throws {
        let domain = "gui/\(getuid())"
        _ = try? await commandRunner.run(
            executable: "/bin/launchctl",
            arguments: ["bootout", domain, plistURL.path],
            timeout: 10
        )
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
