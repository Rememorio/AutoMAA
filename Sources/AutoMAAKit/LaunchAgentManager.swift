import Darwin
import Foundation

public struct LaunchAgentManager: Sendable {
    public static let label = "com.rememorio.AutoMAA.runner"

    private let commandRunner = CommandRunner()
    private let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
            .appending(path: "\(Self.label).plist")
    }

    public func install(runnerURL: URL, schedule: ScheduleConfiguration) async throws {
        try directories.prepare()
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [runnerURL.path],
            "StartCalendarInterval": [
                "Hour": schedule.hour,
                "Minute": schedule.minute,
            ],
            "RunAtLoad": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": directories.logs.appending(path: "launchd.out.log").path,
            "StandardErrorPath": directories.logs.appending(path: "launchd.err.log").path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
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

    public func uninstall() async throws {
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

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }
}
