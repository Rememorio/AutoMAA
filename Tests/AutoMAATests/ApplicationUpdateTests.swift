import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

private struct UnavailableReleaseNotesService: ReleaseNotesServing {
    func application(repository: String, from: String, through: String) async throws -> ReleaseNotesCollection { throw URLError(.notConnectedToInternet) }
    func maa(manifestURL: URL, version: String?) async throws -> ReleaseNotesCollection { throw URLError(.notConnectedToInternet) }
    func resources(comparisonURL: URL) async throws -> ReleaseNotesCollection { throw URLError(.notConnectedToInternet) }
}

@MainActor
private final class InstallerValidationSpy {
    var rejectsInstallerStart = false
    private(set) var reachedInstallerValidation = false

    func validate() throws {
        if rejectsInstallerStart {
            reachedInstallerValidation = true
            throw SoftwareUpdateError.installerUnavailable
        }
    }
}

private actor StubSoftwareUpdateService: SoftwareUpdateServing {
    let release: SoftwareUpdateRelease
    let prepared: PreparedSoftwareUpdate
    var restored: PreparedSoftwareUpdate?
    private(set) var checkCount = 0
    private(set) var checkedChannels: [SoftwareUpdateChannel] = []
    var savesLateDownload = false
    var returnsLateRestoration = false
    private(set) var prepareCount = 0
    private(set) var restorationCount = 0
    var slowChecks = false
    var slowDownloads = false
    var returnsLateResult = false
    var slowRestoration = false
    var restorationFails = false
    var downloadFails = false
    var hasUpdate = true
    var checkFails = false
    private var progressHandlers: [@Sendable (UpdateProgress) async -> Void] = []

    init(release: SoftwareUpdateRelease, prepared: PreparedSoftwareUpdate, restored: PreparedSoftwareUpdate? = nil) {
        self.release = release
        self.prepared = prepared
        self.restored = restored
    }

    func check(channel: SoftwareUpdateChannel) async throws -> SoftwareUpdateRelease? {
        checkCount += 1
        checkedChannels.append(channel)
        if checkFails { throw URLError(.notConnectedToInternet) }
        if slowChecks {
            slowChecks = false
            do { try await Task.sleep(for: .seconds(30)) }
            catch { if !returnsLateResult { throw URLError(.cancelled) } }
        }
        return hasUpdate && channel.accepts(release) ? release : nil
    }

    func prepare(
        _ release: SoftwareUpdateRelease,
        directories: AppDirectories,
        channel: SoftwareUpdateChannel,
        progress: @escaping @Sendable (UpdateProgress) async -> Void
    ) async throws -> PreparedSoftwareUpdate {
        prepareCount += 1
        progressHandlers.append(progress)
        await progress(.init(message: "正在下载更新包", download: .init(receivedBytes: 25, totalBytes: 100)))
        if downloadFails { throw URLError(.cannotConnectToHost) }
        if slowDownloads {
            if returnsLateResult {
                try? await Task.sleep(for: .seconds(30))
            } else {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { throw URLError(.cancelled) }
            }
        }
        if savesLateDownload {
            try FileManager.default.createDirectory(at: prepared.applicationURL, withIntermediateDirectories: true)
            try PreparedSoftwareUpdateStore(directories: directories).save(prepared)
        }
        return prepared
    }

    func saveDownloadAfterCancellation() { savesLateDownload = true }
    func restore(_ prepared: PreparedSoftwareUpdate?, late: Bool = false) {
        restored = prepared
        slowRestoration = late
        returnsLateRestoration = late
    }

    func restorePreparedUpdate(directories: AppDirectories, channel: SoftwareUpdateChannel) async throws -> PreparedSoftwareUpdate? {
        restorationCount += 1
        let result = restored
        if slowRestoration {
            slowRestoration = false
            do { try await Task.sleep(for: .seconds(30)) }
            catch { if !returnsLateRestoration { throw error } }
        }
        if restorationFails { throw URLError(.timedOut) }
        return result
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

    func failDownload() { downloadFails = true }

    func checkResult(hasUpdate: Bool, fails: Bool = false) {
        self.hasUpdate = hasUpdate
        checkFails = fails
    }

    func reportProgress(_ update: UpdateProgress, attempt: Int) async {
        await progressHandlers[attempt](update)
    }
}

@Suite("Application updates")
struct ApplicationUpdateTests {
    @Test("termination confirmation also defers checks after empty cache restoration")
    @MainActor
    func terminationDefersCheckAfterRestoration() async throws {
        let fixture = try makeFixture(automaticallyDownloads: false, startup: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.model.prepareApplication()
        fixture.model.setTerminationPreparationActive(true)
        let scope = ApplicationTerminationScope.capture(fixture.model)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(scope.contains(.capture(fixture.model)))
        #expect(await fixture.service.counts().checks == 0)
        fixture.model.setTerminationPreparationActive(false)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(await fixture.service.counts().checks == 1)
    }

    @Test("termination confirmation defers a pending channel check until quitting is cancelled")
    @MainActor
    func terminationDefersChannelRecheck() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, receivesPrereleases: true, releaseVersion: "0.16.0-beta.2")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(downloads: true, lateResult: true)
        await fixture.service.saveDownloadAfterCancellation()
        fixture.model.checkForApplicationUpdate()
        try await waitUntil { fixture.model.applicationUpdateProgress != nil }
        fixture.model.setPrereleaseApplicationUpdatesEnabled(false)
        fixture.model.setTerminationPreparationActive(true)
        let scope = ApplicationTerminationScope.capture(fixture.model)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(scope.contains(.capture(fixture.model)))
        #expect(await fixture.service.counts().checks == 1)
        #expect(try PreparedSoftwareUpdateStore(directories: fixture.model.directories).load() == nil)
        #expect(!fixture.model.canChangeApplicationUpdateChannel)
        fixture.model.setTerminationPreparationActive(false)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(await fixture.service.checkedChannels == [.preview, .stable])
        #expect(fixture.model.canChangeApplicationUpdateChannel)
    }

    @Test("switching channels discards late checks and uses the last preference")
    @MainActor
    func switchingChannelsDuringCheck() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, receivesPrereleases: true, releaseVersion: "0.16.0-beta.2")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(checks: true, lateResult: true)
        fixture.model.checkForApplicationUpdate()
        try await waitUntilAsync { await fixture.service.counts().checks == 1 }
        fixture.model.setPrereleaseApplicationUpdatesEnabled(false)
        fixture.model.setPrereleaseApplicationUpdatesEnabled(true)
        fixture.model.setPrereleaseApplicationUpdatesEnabled(false)
        if case .cancelling = fixture.model.applicationUpdateState {} else { Issue.record("旧检查应先退出") }
        await fixture.service.delay()
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(await fixture.service.checkedChannels == [.preview, .stable])
        #expect(await fixture.service.counts().prepares == 0)
        #expect(fixture.model.applicationUpdateRelease == nil)
        #expect(!fixture.model.configuration.applicationUpdates.receivesPrereleaseUpdates)
    }

    @Test("leaving preview waits for a late saved download before removing its manifest")
    @MainActor
    func switchingChannelsDuringDownload() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, receivesPrereleases: true, releaseVersion: "0.16.0-beta.2")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(downloads: true, lateResult: true)
        await fixture.service.saveDownloadAfterCancellation()
        fixture.model.checkForApplicationUpdate()
        try await waitUntil { fixture.model.applicationUpdateProgress != nil }
        fixture.model.setPrereleaseApplicationUpdatesEnabled(false)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(fixture.model.applicationUpdateRelease == nil)
        #expect(fixture.model.applicationUpdateProgress == nil)
        #expect(await fixture.service.counts().prepares == 1)
        #expect(try PreparedSoftwareUpdateStore(directories: fixture.model.directories).load() == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.service.prepared.workingDirectory.path))
        await fixture.service.reportProgress(.init(message: "过期回调"), attempt: 0)
        #expect(fixture.model.applicationUpdateProgress == nil)
        fixture.model.downloadApplicationUpdate(fixture.service.release)
        #expect(await fixture.service.counts().prepares == 1)
    }

    @Test("leaving preview invalidates an installed candidate and stale installation actions")
    @MainActor
    func switchingChannelsWhenReady() async throws {
        let installer = InstallerValidationSpy()
        let fixture = try makeFixture(automaticallyDownloads: true, receivesPrereleases: true,
                                      releaseVersion: "0.16.0-beta.2", availabilityValidator: { try installer.validate() })
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.saveDownloadAfterCancellation()
        fixture.model.checkForApplicationUpdate()
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }; return false
        }
        installer.rejectsInstallerStart = true
        fixture.model.setPrereleaseApplicationUpdatesEnabled(false)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        fixture.model.restartAndInstallApplicationUpdate(fixture.service.prepared)
        #expect(!installer.reachedInstallerValidation)
        #expect(fixture.model.applicationUpdateRelease == nil)
        #expect(try PreparedSoftwareUpdateStore(directories: fixture.model.directories).load() == nil)
    }

    @Test("switching channels while restoring ignores a late preview candidate")
    @MainActor
    func switchingChannelsDuringRestoration() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, startup: true,
                                      receivesPrereleases: true, releaseVersion: "0.16.0-beta.2")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.restore(fixture.service.prepared, late: true)
        fixture.model.prepareApplication()
        try await waitUntilAsync { await fixture.service.restorationCount == 1 }
        fixture.model.setPrereleaseApplicationUpdatesEnabled(false)
        await fixture.service.restore(nil)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(fixture.model.applicationUpdateRelease == nil)
        #expect(await fixture.service.counts().prepares == 0)
        #expect(await fixture.service.checkedChannels.last == .stable)
    }

    @Test("installed previews can wait for stable without accepting a downgrade")
    @MainActor
    func installedPreviewWaitsForStable() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, releaseVersion: "0.15.10", currentVersion: "0.16.0-beta.1")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.checkResult(hasUpdate: false)
        fixture.model.checkForApplicationUpdate()
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        #expect(fixture.model.applicationUpdateCurrentStatus == "暂无更新的正式版本")
        fixture.model.downloadApplicationUpdate(fixture.service.release)
        #expect(await fixture.service.counts().prepares == 0)
    }

    @Test("enabling preview persists the preference and prepares a newer beta")
    @MainActor
    func enablingPreviewChecksImmediately() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true, releaseVersion: "0.16.0-beta.2", currentVersion: "0.16.0-beta.1")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.model.setPrereleaseApplicationUpdatesEnabled(true)
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }; return false
        }
        #expect(fixture.model.saveNow(showConfirmation: false))
        let configuration = try ConfigurationStore(directories: fixture.model.directories).load()
        #expect(configuration.applicationUpdates.receivesPrereleaseUpdates)
        #expect(await fixture.service.checkedChannels == [.preview])
        #expect(fixture.model.applicationUpdateRelease?.version.description == "0.16.0-beta.2")
    }

    @Test("update checks keep their result on the update page without global feedback", arguments: [false, true])
    @MainActor
    func checkResultIsInline(fails: Bool) async throws {
        let fixture = try makeFixture(automaticallyDownloads: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.checkResult(hasUpdate: false, fails: fails)
        fixture.model.checkForApplicationUpdate()
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        if fails {
            if case .failed = fixture.model.applicationUpdateState {} else { Issue.record("检查失败应保留错误") }
            #expect(fixture.model.applicationUpdateCheckedAt == nil)
        } else {
            if case .upToDate = fixture.model.applicationUpdateState {} else { Issue.record("应显示已是最新版本") }
            #expect(fixture.model.applicationUpdateCheckedAt != nil)
        }
        #expect(fixture.model.feedback.notice == nil)
    }

    @Test("download progress clears on cancellation and ignores callbacks from an earlier attempt")
    @MainActor
    func progressLifecycle() async throws {
        let fixture = try makeFixture(automaticallyDownloads: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(downloads: true)
        fixture.model.downloadApplicationUpdate(fixture.service.release)
        try await waitUntil { fixture.model.applicationUpdateProgress?.download?.receivedBytes == 25 }
        fixture.model.cancelApplicationUpdate()
        #expect(fixture.model.applicationUpdateProgress == nil)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        let stale = UpdateProgress(message: "过期进度", download: .init(receivedBytes: 90, totalBytes: 100))
        await fixture.service.reportProgress(stale, attempt: 0)
        #expect(fixture.model.applicationUpdateProgress == nil)

        fixture.model.downloadApplicationUpdate(fixture.service.release)
        try await waitUntil { fixture.model.applicationUpdateProgress?.download?.receivedBytes == 25 }
        await fixture.service.reportProgress(stale, attempt: 0)
        #expect(fixture.model.applicationUpdateProgress?.download?.receivedBytes == 25)
        await fixture.service.reportProgress(.init(message: "正在校验更新包"), attempt: 1)
        #expect(fixture.model.applicationUpdateProgress?.message == "正在校验更新包")
        #expect(fixture.model.applicationUpdateProgress?.download == nil)
        fixture.model.cancelApplicationUpdate()
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
    }

    @Test("restarting for an update preserves unsaved edits until saving succeeds")
    @MainActor
    func failedSavePreventsUpdateRestart() async throws {
        let installer = InstallerValidationSpy()
        let fixture = try makeFixture(automaticallyDownloads: true, availabilityValidator: {
            try installer.validate()
        })
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.model.checkForApplicationUpdate()
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }
            return false
        }
        fixture.model.configuration.plans[0].name = "尚未保存的方案"
        installer.rejectsInstallerStart = true
        let configurationURL = fixture.model.directories.configuration
        try FileManager.default.removeItem(at: configurationURL)
        try FileManager.default.createDirectory(at: configurationURL, withIntermediateDirectories: false)

        fixture.model.restartAndInstallApplicationUpdate(fixture.service.prepared)

        #expect(fixture.model.configurationSaveError != nil)
        #expect(fixture.model.configuration.plans[0].name == "尚未保存的方案")
        #expect(!installer.reachedInstallerValidation)
        if case .ready = fixture.model.applicationUpdateState {} else { Issue.record("保存失败后应保留已准备好的更新") }
    }

    @Test("notes failures leave automatic downloads and their cancellation available")
    @MainActor
    func unavailableNotesDoNotInterruptUpdates() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(downloads: true)
        fixture.model.checkForApplicationUpdate()
        try await waitUntil {
            if case .downloading = fixture.model.applicationUpdateState { return true }
            return false
        }
        await #expect(throws: URLError.self) {
            try await fixture.model.loadReleaseNotes(for: .application("9.9.9"))
        }
        if case .downloading = fixture.model.applicationUpdateState {} else { Issue.record("说明读取影响了下载") }
        #expect(fixture.model.applicationUpdateProgress?.download?.receivedBytes == 25)
        #expect(fixture.model.applicationUpdateState.canCancel)
        fixture.model.cancelApplicationUpdate()
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
    }

    @Test("an open MAA details request follows only its own activated installation")
    @MainActor
    func maaDetailsFollowActivation() throws {
        let fixture = try makeFixture(automaticallyDownloads: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = MAAInstalledVersions(core: "1.0.0", baseResources: .init(), recognitionData: .init())
        let pending = MAAUpdateInformation(title: "MAA", before: before)
        #expect(fixture.model.resolvedUpdateDetails(.maa(pending)) == .maa(pending))
        var activated = pending
        activated.after = .init(core: "1.1.0", baseResources: .init(), recognitionData: .init())
        fixture.model.activityEntries = [
            .init(level: .info, message: "准备更新", updateInformation: pending),
            .init(level: .info, message: "已启用", updateInformation: activated),
            .init(level: .info, message: "另一次更新", updateInformation: .init(title: "MAA", before: before))
        ]
        #expect(fixture.model.resolvedUpdateDetails(.maa(pending)) == .maa(activated))
    }

    @Test("release notes survive automatic download, cancellation and preparation failure")
    @MainActor
    func releaseNotesSurviveOperationStates() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.service.delay(downloads: true)
        fixture.model.checkForApplicationUpdate()
        try await waitUntil {
            if case .downloading = fixture.model.applicationUpdateState { return true }
            return false
        }
        #expect(fixture.model.applicationUpdateRelease == fixture.service.release)
        fixture.model.showApplicationNotes()
        #expect(fixture.model.updateDetailsRequest?.id == "application-9.9.9")
        #expect(fixture.model.initialReleaseNotes(for: .application("9.9.9")).first?.body == "测试更新")
        fixture.model.cancelApplicationUpdate()
        #expect(fixture.model.applicationUpdateRelease == fixture.service.release)
        try await waitUntil { !fixture.model.applicationUpdateState.isBusy }
        await fixture.service.failDownload()
        fixture.model.downloadApplicationUpdate(fixture.service.release)
        try await waitUntil {
            if case .failed = fixture.model.applicationUpdateState { return true }
            return false
        }
        #expect(fixture.model.applicationUpdateRelease == fixture.service.release)
        let cache = ReleaseNotesCache(directories: AppDirectories(root: fixture.root)).load()
        #expect(cache.releases.first?.body == "测试更新")
    }

    @Test("update success retains a readable notice until the current version notes are opened")
    @MainActor
    func successfulUpdateHasPersistentNotesEntry() async throws {
        let fixture = try makeFixture(automaticallyDownloads: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try SoftwareUpdateResultStore(directories: AppDirectories(root: fixture.root)).save(.init(
            status: .success, version: fixture.model.currentApplicationVersion, message: "更新成功"))
        fixture.model.prepareApplication()
        #expect(fixture.model.releaseNotesState.unreadVersion == fixture.model.currentApplicationVersion)
        fixture.model.showApplicationNotes(currentVersion: true)
        #expect(fixture.model.releaseNotesState.unreadVersion == nil)
        #expect(ReleaseNotesCache(directories: AppDirectories(root: fixture.root)).load().unreadVersion == nil)
    }

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
        #expect(fixture.model.applicationUpdateNotice?.contains("已取消检查") == true)
        #expect(fixture.model.feedback.notice == nil)
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
        #expect(fixture.model.applicationUpdateNotice?.contains("下载已取消") == true)
        #expect(fixture.model.feedback.notice == nil)
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

        fixture.model.checkForApplicationUpdate()
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

        fixture.model.checkForApplicationUpdate()
        try await waitUntil {
            if case .ready = fixture.model.applicationUpdateState { return true }
            return false
        }

        let counts = await fixture.service.counts()
        #expect(counts.checks == 1)
        #expect(counts.prepares == 1)
        #expect(fixture.model.feedback.notice == nil)
        #expect(fixture.model.applicationUpdateNotice == nil)
    }

    @Test("automatic downloads wait until the current workflow is idle")
    @MainActor
    func automaticDownloadsWaitForIdle() async throws {
        let fixture = try makeFixture(automaticallyDownloads: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.model.isRunning = true

        fixture.model.checkForApplicationUpdate()
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

        fixture.model.checkForApplicationUpdate()
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
        startup: Bool = false,
        receivesPrereleases: Bool = false,
        releaseVersion: String = "9.9.9",
        currentVersion: String = "0.15.10",
        availabilityValidator: @escaping @MainActor () throws -> Void = {}
    ) throws -> (root: URL, model: AppModel, service: StubSoftwareUpdateService) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-application-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directories = AppDirectories(root: root)
        var configuration = AppConfiguration.defaults
        configuration.cliPath = "/usr/bin/true"
        configuration.maaUpdates.automaticallyUpdatesCoreAndResources = false
        configuration.applicationUpdates.automaticallyDownloadsUpdates = automaticallyDownloads
        configuration.applicationUpdates.receivesPrereleaseUpdates = receivesPrereleases
        try ConfigurationStore(directories: directories).save(configuration)
        let version = try #require(SoftwareVersion(releaseVersion))
        let diskImageName = "AutoMAA-\(releaseVersion)-macOS-arm64.dmg"
        let release = SoftwareUpdateRelease(
            version: version,
            tagName: "v\(releaseVersion)",
            releaseNotes: "测试更新",
            pageURL: URL(string: "https://github.com/Rememorio/AutoMAA/releases/tag/v\(releaseVersion)")!,
            diskImage: SoftwareUpdateAsset(
                name: diskImageName,
                size: 1,
                downloadURL: URL(string: "https://github.com/Rememorio/AutoMAA/releases/download/v\(releaseVersion)/\(diskImageName)")!
            ),
            checksum: SoftwareUpdateAsset(
                name: "\(diskImageName).sha256",
                size: 1,
                downloadURL: URL(string: "https://github.com/Rememorio/AutoMAA/releases/download/v\(releaseVersion)/\(diskImageName).sha256")!
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
            applicationVersion: currentVersion,
            softwareUpdateService: service,
            applicationUpdateAvailabilityValidator: availabilityValidator,
            releaseNotesService: UnavailableReleaseNotesService()
        )
        return (root, model, service)
    }

    @MainActor
    private func waitUntilAsync(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待更新服务超时")
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
