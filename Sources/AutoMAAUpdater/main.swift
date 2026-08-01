import AutoMAAKit
import Darwin
import Foundation

@main
enum AutoMAAUpdaterMain {
    static func main() async {
        let arguments: UpdaterArguments
        do {
            arguments = try UpdaterArguments(CommandLine.arguments)
        } catch {
            fputs("AutoMAA Updater: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }

        let resultStore = SoftwareUpdateResultStore(url: arguments.resultURL)
        do {
            try await waitForExit(pid: arguments.parentPID)
            try await SoftwareUpdateInstaller().install(
                SoftwareUpdateInstallationRequest(
                    currentApplicationURL: arguments.currentApplicationURL,
                    stagedApplicationURL: arguments.stagedApplicationURL,
                    expectedVersion: arguments.expectedVersion,
                    relaunch: arguments.relaunch
                )
            ) {
                try resultStore.save(
                    SoftwareUpdateResult(
                        status: .success,
                        version: arguments.expectedVersion,
                        message: "AutoMAA 已更新到 v\(arguments.expectedVersion)"
                    )
                )
            }
            exit(EXIT_SUCCESS)
        } catch {
            let message = error.localizedDescription
            try? resultStore.save(
                SoftwareUpdateResult(
                    status: .failure,
                    version: arguments.expectedVersion,
                    message: "自动更新失败：\(message)"
                )
            )
            if arguments.relaunch,
               FileManager.default.fileExists(atPath: arguments.currentApplicationURL.path) {
                _ = try? await CommandRunner().run(
                    executable: "/usr/bin/open",
                    arguments: [arguments.currentApplicationURL.path],
                    timeout: 30,
                    observeCancellation: false
                )
            }
            fputs("AutoMAA Updater: \(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func waitForExit(pid: pid_t) async throws {
        guard pid > 1 else { return }
        let deadline = Date().addingTimeInterval(60)
        while processIsAlive(pid), Date() < deadline {
            try await Task.sleep(for: .milliseconds(150))
        }
        guard !processIsAlive(pid) else { throw SoftwareUpdateError.updateTimedOut }
    }

    private static func processIsAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

private struct UpdaterArguments {
    let parentPID: pid_t
    let currentApplicationURL: URL
    let stagedApplicationURL: URL
    let expectedVersion: String
    let resultURL: URL
    let relaunch: Bool

    init(_ arguments: [String]) throws {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        guard let pidValue = value(after: "--pid"),
              let parentPID = pid_t(pidValue),
              let currentPath = value(after: "--current-app"),
              let stagedPath = value(after: "--new-app"),
              let expectedVersion = value(after: "--expected-version"),
              SoftwareVersion(expectedVersion) != nil,
              let resultPath = value(after: "--result")
        else {
            throw SoftwareUpdateError.invalidApplication("更新辅助程序参数不完整")
        }
        self.parentPID = parentPID
        currentApplicationURL = URL(filePath: currentPath).standardizedFileURL
        stagedApplicationURL = URL(filePath: stagedPath).standardizedFileURL
        self.expectedVersion = expectedVersion
        resultURL = URL(filePath: resultPath).standardizedFileURL
        relaunch = !arguments.contains("--no-relaunch")
    }
}
