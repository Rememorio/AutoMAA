import Foundation
import XCTest
@testable import AutoMAAKit

final class SoftwareUpdateTests: XCTestCase {
    func testSoftwareVersionComparison() throws {
        let old = try XCTUnwrap(SoftwareVersion("v0.1.9"))
        let current = try XCTUnwrap(SoftwareVersion("0.2.0"))
        let next = try XCTUnwrap(SoftwareVersion("0.2.1-beta.1"))

        XCTAssertLessThan(old, current)
        XCTAssertLessThan(current, next)
        XCTAssertEqual(next.description, "0.2.1-beta.1")
        XCTAssertNil(SoftwareVersion("latest"))
        XCTAssertNil(SoftwareVersion("1.2"))
    }

    func testReleaseResolverSelectsExactArm64Assets() throws {
        let data = releaseJSON(version: "0.2.0")

        let release = try XCTUnwrap(
            SoftwareUpdateReleaseResolver.newerRelease(from: data, currentVersion: "0.1.1")
        )

        XCTAssertEqual(release.version.description, "0.2.0")
        XCTAssertEqual(release.diskImage.name, "AutoMAA-0.2.0-macOS-arm64.dmg")
        XCTAssertEqual(release.checksum.name, "AutoMAA-0.2.0-macOS-arm64.dmg.sha256")
        XCTAssertEqual(release.releaseNotes, "更新说明")
    }

    func testReleaseResolverIgnoresCurrentOrOlderVersion() throws {
        XCTAssertNil(
            try SoftwareUpdateReleaseResolver.newerRelease(
                from: releaseJSON(version: "0.1.1"),
                currentVersion: "0.1.1"
            )
        )
        XCTAssertNil(
            try SoftwareUpdateReleaseResolver.newerRelease(
                from: releaseJSON(version: "0.1.0"),
                currentVersion: "0.1.1"
            )
        )
    }

    func testReleaseResolverRejectsUntrustedAssetURL() {
        let data = releaseJSON(version: "0.2.0", host: "example.invalid")

        XCTAssertThrowsError(
            try SoftwareUpdateReleaseResolver.newerRelease(from: data, currentVersion: "0.1.1")
        ) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .invalidDownloadURL)
        }
    }

    func testChecksumParsingAndStreamingHash() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "AutoMAA-0.2.0-macOS-arm64.dmg")
        try Data("hello".utf8).write(to: file)
        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let checksum = Data("\(expected)  \(file.lastPathComponent)\n".utf8)

        XCTAssertEqual(
            try SoftwareUpdateVerifier.expectedSHA256(from: checksum, fileName: file.lastPathComponent),
            expected
        )
        XCTAssertEqual(try SoftwareUpdateVerifier.sha256(of: file), expected)
    }

    func testUpdateResultStoreConsumesResultOnce() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SoftwareUpdateResultStore(directories: AppDirectories(root: root))
        let result = SoftwareUpdateResult(
            status: .success,
            version: "0.2.0",
            message: "更新成功",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try store.save(result)

        XCTAssertEqual(store.loadAndClear(), result)
        XCTAssertNil(store.loadAndClear())
    }

    func testPreparedUpdateStoreRoundTripsOnlyInsideUpdatesDirectory() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let release = try XCTUnwrap(
            SoftwareUpdateReleaseResolver.newerRelease(from: releaseJSON(version: "0.2.0"), currentVersion: "0.1.1")
        )
        let workingDirectory = root
            .appending(path: "Updates", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let applicationURL = workingDirectory.appending(path: "AutoMAA.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        let prepared = PreparedSoftwareUpdate(
            release: release,
            applicationURL: applicationURL,
            workingDirectory: workingDirectory
        )
        let store = PreparedSoftwareUpdateStore(directories: directories)

        try store.save(prepared)

        XCTAssertEqual(try store.load(), prepared)
    }

    func testPreparedUpdateStoreRejectsWorkingDirectoryOutsideUpdatesRoot() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let release = try XCTUnwrap(
            SoftwareUpdateReleaseResolver.newerRelease(from: releaseJSON(version: "0.2.0"), currentVersion: "0.1.1")
        )
        let workingDirectory = root.appending(path: "Outside", directoryHint: .isDirectory)
        let prepared = PreparedSoftwareUpdate(
            release: release,
            applicationURL: workingDirectory.appending(path: "AutoMAA.app", directoryHint: .isDirectory),
            workingDirectory: workingDirectory
        )

        XCTAssertThrowsError(try PreparedSoftwareUpdateStore(directories: directories).save(prepared))
    }

    func testStableChannelRejectsPrereleasesRegardlessOfGitHubFlag() throws {
        for markedPrerelease in [false, true] {
            XCTAssertThrowsError(try SoftwareUpdateReleaseResolver.newerRelease(
                from: releaseJSON(version: "0.16.0-beta.1", prerelease: markedPrerelease), currentVersion: "0.15.10"))
        }
        let releases = [releaseObject(version: "0.16.0-beta.1", prerelease: true), releaseObject(version: "0.15.11")]
        let stable = try SoftwareUpdateReleaseResolver.newestRelease(
            from: JSONSerialization.data(withJSONObject: releases), currentVersion: "0.15.10", channel: .stable)
        XCTAssertEqual(stable?.version.description, "0.15.11")
    }

    func testPreviewChannelSelectsHighestSemanticVersionAndNeverDowngrades() throws {
        let releases = [releaseObject(version: "0.16.0-beta.10", prerelease: true),
                        releaseObject(version: "0.16.0"), releaseObject(version: "0.16.0-rc.1", prerelease: true),
                        releaseObject(version: "0.16.0-beta.2", prerelease: true)]
        let data = try JSONSerialization.data(withJSONObject: releases)
        let newest = try SoftwareUpdateReleaseResolver.newestRelease(from: data, currentVersion: "0.15.10", channel: .preview)
        XCTAssertEqual(newest?.version.description, "0.16.0")
        XCTAssertNil(try SoftwareUpdateReleaseResolver.newestRelease(from: data, currentVersion: "0.16.0", channel: .preview))
        XCTAssertNil(try SoftwareUpdateReleaseResolver.newestRelease(
            from: JSONSerialization.data(withJSONObject: [releaseObject(version: "0.15.10")]),
            currentVersion: "0.16.0-beta.1", channel: .stable))
        let beta = try XCTUnwrap(SoftwareUpdateReleaseResolver.newerRelease(
            from: releaseJSON(version: "0.16.0-beta.10", prerelease: true), currentVersion: "0.16.0-beta.2", channel: .preview))
        XCTAssertFalse(SoftwareUpdateChannel.stable.accepts(beta))
        XCTAssertTrue(SoftwareUpdateChannel.preview.allows(beta, currentVersion: "0.16.0-beta.2"))
        XCTAssertFalse(SoftwareUpdateChannel.preview.allows(beta, currentVersion: "0.16.0"))
    }

    func testPreviewIgnoresDraftsAndInconsistentReleaseMetadata() throws {
        let releases = [releaseObject(version: "99.0.0-beta.1", prerelease: true, draft: true),
                        releaseObject(version: "98.0.0", prerelease: true),
                        releaseObject(version: "invalid"), releaseObject(version: "0.16.0-beta.1", prerelease: true)]
        let selected = try SoftwareUpdateReleaseResolver.newestRelease(
            from: JSONSerialization.data(withJSONObject: releases), currentVersion: "0.15.10", channel: .preview)
        XCTAssertEqual(selected?.version.description, "0.16.0-beta.1")
        XCTAssertThrowsError(try SoftwareUpdateReleaseResolver.newerRelease(
            from: releaseJSON(version: "0.16.0", prerelease: true), currentVersion: "0.15.10", channel: .preview))
    }

    func testMissingAssetsFallBackToNewestCompleteReleaseAndRemainAnErrorWhenAllAreMissing() throws {
        let missing = releaseObject(version: "0.17.0-beta.1", prerelease: true, hasAssets: false)
        let complete = releaseObject(version: "0.16.0-beta.1", prerelease: true)
        let selected = try SoftwareUpdateReleaseResolver.newestRelease(
            from: JSONSerialization.data(withJSONObject: [complete, missing]), currentVersion: "0.15.10", channel: .preview)
        XCTAssertEqual(selected?.version.description, "0.16.0-beta.1")
        XCTAssertThrowsError(try SoftwareUpdateReleaseResolver.newestRelease(
            from: JSONSerialization.data(withJSONObject: [missing]), currentVersion: "0.15.10", channel: .preview)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .missingAssets("0.17.0-beta.1"))
        }
    }

    func testPreviewDoesNotHideUntrustedAssetErrorsBehindAnOlderRelease() throws {
        let releases = [releaseObject(version: "0.17.0-beta.1", host: "example.invalid", prerelease: true),
                        releaseObject(version: "0.16.0")]
        XCTAssertThrowsError(try SoftwareUpdateReleaseResolver.newestRelease(
            from: JSONSerialization.data(withJSONObject: releases), currentVersion: "0.15.10", channel: .preview)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .invalidDownloadURL)
        }
    }

    func testValidationRequiresExactBuildMetadataIdentity() throws {
        let original = try XCTUnwrap(SoftwareUpdateReleaseResolver.newerRelease(
            from: releaseJSON(version: "0.16.0-beta.1+build.1", prerelease: true), currentVersion: "0.15.10", channel: .preview))
        XCTAssertEqual(original.diskImage.name, "AutoMAA-0.16.0-beta.1+build.1-macOS-arm64.dmg")
        let mismatch = SoftwareUpdateRelease(version: original.version, tagName: "v0.16.0-beta.1+build.2",
            releaseNotes: original.releaseNotes, pageURL: original.pageURL, diskImage: original.diskImage, checksum: original.checksum)
        XCTAssertThrowsError(try SoftwareUpdateReleaseResolver.validate(mismatch))
        XCTAssertNil(try SoftwareUpdateReleaseResolver.newerRelease(
            from: releaseJSON(version: "0.16.0-beta.1+build.2", prerelease: true),
            currentVersion: "0.16.0-beta.1+build.1", channel: .preview))
    }

    func testStableServiceUsesLatestEndpoint() async throws {
        let path = "/repos/Rememorio/AutoMAA/releases/latest"
        let service = updateService(routes: [path: releaseJSON(version: "0.16.0")])
        let release = try await service.check()
        XCTAssertEqual(release?.version.description, "0.16.0")
        XCTAssertEqual(ReleaseUpdateURLProtocol.state.requestedPaths(), [path])
    }

    func testPreviewServiceReadsAllPagesBeforeChoosingVersion() async throws {
        let base = "/repos/Rememorio/AutoMAA/releases"
        let firstPage = Array(repeating: releaseObject(version: "0.16.0-beta.2", prerelease: true), count: 100)
        let secondPage = [releaseObject(version: "0.16.0-beta.10", prerelease: true), releaseObject(version: "0.16.0-rc.1", prerelease: true)]
        let service = updateService(routes: [
            "\(base)?per_page=100&page=1": try JSONSerialization.data(withJSONObject: firstPage),
            "\(base)?per_page=100&page=2": try JSONSerialization.data(withJSONObject: secondPage),
        ])
        let release = try await service.check(channel: .preview)
        XCTAssertEqual(release?.version.description, "0.16.0-rc.1")
        XCTAssertEqual(ReleaseUpdateURLProtocol.state.requestedPaths(), ["\(base)?per_page=100&page=1", "\(base)?per_page=100&page=2"])
    }

    func testStableRestorationRemovesPreviouslyPreparedPreview() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let release = try XCTUnwrap(SoftwareUpdateReleaseResolver.newerRelease(
            from: releaseJSON(version: "0.16.0-beta.1", prerelease: true), currentVersion: "0.15.10", channel: .preview))
        let workingDirectory = root.appending(path: "Updates/candidate")
        let application = workingDirectory.appending(path: "AutoMAA.app")
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        let store = PreparedSoftwareUpdateStore(directories: directories)
        try store.save(.init(release: release, applicationURL: application, workingDirectory: workingDirectory))
        let service = updateService(routes: [:])
        let restored = try await service.restorePreparedUpdate(directories: directories, channel: .stable)
        XCTAssertNil(restored)
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: workingDirectory.path))
        XCTAssertTrue(ReleaseUpdateURLProtocol.state.requestedPaths().isEmpty)
    }

    private func releaseJSON(version: String, host: String = "github.com", prerelease: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: releaseObject(version: version, host: host, prerelease: prerelease))
    }

    private func releaseObject(version: String, host: String = "github.com", prerelease: Bool = false,
                               draft: Bool = false, hasAssets: Bool = true) -> [String: Any] {
        let fileName = "AutoMAA-\(version)-macOS-arm64.dmg"
        return ["tag_name": "v\(version)", "html_url": "https://github.com/Rememorio/AutoMAA/releases/tag/v\(version)",
                "body": "更新说明", "draft": draft, "prerelease": prerelease,
                "assets": hasAssets ? [
                    ["name": fileName, "size": 4096, "browser_download_url": "https://\(host)/Rememorio/AutoMAA/releases/download/v\(version)/\(fileName)"],
                    ["name": "\(fileName).sha256", "size": 96, "browser_download_url": "https://github.com/Rememorio/AutoMAA/releases/download/v\(version)/\(fileName).sha256"],
                ] : []]
    }

    private func updateService(routes: [String: Data]) -> SoftwareUpdateService {
        ReleaseUpdateURLProtocol.state.install(routes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseUpdateURLProtocol.self]
        return SoftwareUpdateService(currentVersion: "0.15.10", session: URLSession(configuration: configuration))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "automaa-update-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private final class ReleaseUpdateProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: Data] = [:]
    private var requests: [String] = []

    func install(_ values: [String: Data]) { lock.withLock { routes = values; requests = [] } }
    func response(_ request: URLRequest) -> Data? {
        lock.withLock {
            guard let url = request.url else { return nil }
            let key = url.path + (url.query.map { "?" + $0 } ?? "")
            requests.append(key)
            return routes[key]
        }
    }
    func requestedPaths() -> [String] { lock.withLock { requests } }
}

private final class ReleaseUpdateURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = ReleaseUpdateProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let data = Self.state.response(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
