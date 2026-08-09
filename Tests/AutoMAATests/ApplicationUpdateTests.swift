import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

private actor StubSoftwareUpdateService: SoftwareUpdateServing {
    let release: SoftwareUpdateRelease
    let prepared: PreparedSoftwareUpdate
    let restored: PreparedSoftwareUpdate?
    private(set) var checkCount = 0
    private(set) var prepareCount = 0

    init(release: SoftwareUpdateRelease, prepared: PreparedSoftwareUpdate, restored: PreparedSoftwareUpdate? = nil) {
        self.release = release
        self.prepared = prepared
        self.restored = restored
    }

    func check() async throws -> SoftwareUpdateRelease? {
        checkCount += 1
        return release
    }

    func prepare(
        _ release: SoftwareUpdateRelease,
        directories: AppDirectories
    ) async throws -> PreparedSoftwareUpdate {
        prepareCount += 1
        return prepared
    }

    func restorePreparedUpdate(directories: AppDirectories) async -> PreparedSoftwareUpdate? {
        restored
    }

    func counts() -> (checks: Int, prepares: Int) {
        (checkCount, prepareCount)
    }
}

@Suite("Application updates")
struct ApplicationUpdateTests {
    @Test("automatic downloads remain opt-in")
    @MainActor
    func automaticDownloadsRemainOptIn() async throws {
        let fixture = try makeFixture(automaticallyDownloads: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        fixture.model.checkForApplicationUpdate(showResult: false)
        try await waitUntil {
            if case .available = fixture.model.applicationUpdateState { return true }
            return false
        }

        let counts = await fixture.service.counts()
        #expect(counts.checks == 1)
        #expect(counts.prepares == 0)
    }

    @Test("enabled automatic downloads prepare an available release")
    @MainActor
    func enabledAutomaticDownloadsPrepareRelease() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        fixture.model.checkForApplicationUpdate(showResult: false)
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }
            return false
        }

        let counts = await fixture.service.counts()
        #expect(counts.checks == 1)
        #expect(counts.prepares == 1)
    }

    @Test("automatic downloads wait until the current workflow is idle")
    @MainActor
    func automaticDownloadsWaitForIdle() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.model.isRunning = true

        fixture.model.checkForApplicationUpdate(showResult: false)
        try await waitUntil {
            if case .available = fixture.model.applicationUpdateState { return true }
            return false
        }
        var counts = await fixture.service.counts()
        #expect(counts.prepares == 0)

        fixture.model.isRunning = false
        fixture.model.setAutomaticApplicationUpdatesEnabled(true)
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }
            return false
        }
        counts = await fixture.service.counts()
        #expect(counts.prepares == 1)
    }

    @Test("automatic downloads resume after a background runner exits")
    @MainActor
    func automaticDownloadsResumeAfterBackgroundRunner() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var lock: ProcessLock? = try ProcessLock(url: fixture.model.directories.lock)
        #expect(lock != nil)
        fixture.model.reloadActivityHistory()

        fixture.model.checkForApplicationUpdate(showResult: false)
        try await waitUntil {
            if case .available = fixture.model.applicationUpdateState { return true }
            return false
        }
        var counts = await fixture.service.counts()
        #expect(counts.prepares == 0)

        lock = nil
        fixture.model.reloadActivityHistory()
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }
            return false
        }
        counts = await fixture.service.counts()
        #expect(counts.prepares == 1)
    }

    @MainActor
    private func makeFixture(
        automaticallyDownloads: Bool
    ) throws -> (root: URL, model: AppModel, service: StubSoftwareUpdateService) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-application-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directories = AppDirectories(root: root)
        var configuration = AppConfiguration.defaults
        configuration.applicationUpdates.automaticallyDownloadsUpdates = automaticallyDownloads
        try ConfigurationStore(directories: directories).save(configuration)
        let version = try #require(SoftwareVersion("9.9.9"))
        let diskImageName = "AutoMAA-9.9.9-macOS-arm64.dmg"
        let release = SoftwareUpdateRelease(
            version: version,
            tagName: "v9.9.9",
            releaseNotes: "测试更新",
            pageURL: URL(string: "https://github.com/Rememorio/AutoMAA/releases/tag/v9.9.9")!,
            diskImage: SoftwareUpdateAsset(
                name: diskImageName,
                size: 1,
                downloadURL: URL(string: "https://github.com/Rememorio/AutoMAA/releases/download/v9.9.9/\(diskImageName)")!
            ),
            checksum: SoftwareUpdateAsset(
                name: "\(diskImageName).sha256",
                size: 1,
                downloadURL: URL(string: "https://github.com/Rememorio/AutoMAA/releases/download/v9.9.9/\(diskImageName).sha256")!
            )
        )
        let workingDirectory = root
            .appending(path: "Updates", directoryHint: .isDirectory)
            .appending(path: "prepared", directoryHint: .isDirectory)
        let prepared = PreparedSoftwareUpdate(
            release: release,
            applicationURL: workingDirectory.appending(path: "AutoMAA.app", directoryHint: .isDirectory),
            workingDirectory: workingDirectory
        )
        let service = StubSoftwareUpdateService(release: release, prepared: prepared)
        let model = AppModel(
            directories: directories,
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false,
            softwareUpdateService: service,
            applicationUpdateAvailabilityValidator: {}
        )
        return (root, model, service)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待应用更新状态超时")
    }
}
