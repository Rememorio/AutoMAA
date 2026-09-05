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
    var slowChecks = false
    var slowDownloads = false
    var returnsLateResult = false
    var slowRestoration = false
    var restorationFails = false

    init(release: SoftwareUpdateRelease, prepared: PreparedSoftwareUpdate, restored: PreparedSoftwareUpdate? = nil) {
        self.release = release
        self.prepared = prepared
        self.restored = restored
    }

    func check() async throws -> SoftwareUpdateRelease? {
        checkCount += 1
        if slowChecks {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { throw URLError(.cancelled) }
        }
        return release
    }

    func prepare(
        _ release: SoftwareUpdateRelease,
        directories: AppDirectories
    ) async throws -> PreparedSoftwareUpdate {
        prepareCount += 1
        if slowDownloads {
            if returnsLateResult {
                try? await Task.sleep(for: .seconds(30))
            } else {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { throw URLError(.cancelled) }
            }
        }
        return prepared
    }

    func restorePreparedUpdate(directories: AppDirectories) async throws -> PreparedSoftwareUpdate? {
        if slowRestoration { try await Task.sleep(for: .seconds(30)) }
        if restorationFails { throw URLError(.timedOut) }
        return restored
    }

    func counts() -> (checks: Int, prepares: Int) {
        (checkCount, prepareCount)
    }

    func delay(checks: Bool = false, downloads: Bool = false, lateResult: Bool = false) {
        slowChecks = checks
        slowDownloads = downloads
        returnsLateResult = lateResult
    }

    func restoreBehavior(cancel: Bool) {
        slowRestoration = cancel
        restorationFails = !cancel
    }
}

@Suite("Application updates")
struct ApplicationUpdateTests {
    @Test("interrupted prepared-update validation does not start a new download", arguments: [true, false])
    @MainActor
    func interruptedRestorationStopsChecking(cancel: Bool) async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, startup: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.restoreBehavior(cancel: cancel)
        fixture.model.prepareApplication()
        if case .restoring = fixture.model.applicationUpdateState {} else { Issue.record("未显示本地校验阶段") }
        #expect(fixture.model.applicationUpdateState.canCancel)
        if cancel { fixture.model.cancelApplicationUpdate() }
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        if cancel {
            if case .idle = fixture.model.applicationUpdateState {} else { Issue.record("取消后未回到空闲状态") }
        } else {
            if case .failed = fixture.model.applicationUpdateState {} else { Issue.record("校验错误未保留") }
        }
        let counts = await fixture.service.counts()
        #expect(counts.checks == 0)
        #expect(counts.prepares == 0)
    }

    @Test("checking is cancellable and URLSession cancellation is not a failure")
    @MainActor
    func checkCancellationIsNotFailure() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(checks: true)
        fixture.model.checkForApplicationUpdate()
        #expect(fixture.model.applicationUpdateState.canCancel)
        fixture.model.cancelApplicationUpdate()
        #expect(!fixture.model.applicationUpdateState.canCancel)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        if case .idle = fixture.model.applicationUpdateState {} else { Issue.record("检查取消后未回到空闲状态") }
        #expect(await fixture.service.counts().prepares == 0)
    }

    @Test("cancelled downloads do not restart automatically or accept a late success", arguments: [true, false])
    @MainActor
    func cancelledDownloadStaysPaused(lateResult: Bool) async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(downloads: true, lateResult: lateResult)
        fixture.model.checkForApplicationUpdate()
        try await waitUntil {
            if case .downloading = fixture.model.applicationUpdateState { return true }
            return false
        }
        fixture.model.cancelApplicationUpdate()
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(fixture.model.configuration.applicationUpdates.automaticallyDownloadsUpdates)
        if case .available = fixture.model.applicationUpdateState {} else { Issue.record("取消后没有保留可下载版本") }
        // Finishing another job and reloading history must not undo an explicit cancellation.
        var lock: ProcessLock? = try ProcessLock(url: fixture.model.directories.lock)
        #expect(lock != nil)
        fixture.model.reloadActivityHistory()
        lock = nil
        fixture.model.reloadActivityHistory()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await fixture.service.counts().prepares == 1)
        await fixture.service.delay()
        fixture.model.downloadApplicationUpdate(fixture.service.release)
        // Repeated activation in the same event loop must not enqueue a second download.
        fixture.model.downloadApplicationUpdate(fixture.service.release)
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }
            return false
        }
        #expect(await fixture.service.counts().prepares == 2)
    }

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
        automaticallyDownloads: Bool,
        startup: Bool = false
    ) throws -> (root: URL, model: AppModel, service: StubSoftwareUpdateService) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-application-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directories = AppDirectories(root: root)
        var configuration = AppConfiguration.defaults
        configuration.cliPath = "/usr/bin/true"
        configuration.maaUpdates.automaticallyUpdatesCoreAndResources = false
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
            checksForUpdatesAutomatically: startup,
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
