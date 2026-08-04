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
        XCTAssertEqual(next.description, "0.2.1")
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

    private func releaseJSON(version: String, host: String = "github.com") -> Data {
        Data(
            """
            {
              "tag_name": "v\(version)",
              "html_url": "https://github.com/Rememorio/AutoMAA/releases/tag/v\(version)",
              "body": "更新说明",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "AutoMAA-\(version)-macOS-arm64.dmg",
                  "size": 4096,
                  "browser_download_url": "https://\(host)/Rememorio/AutoMAA/releases/download/v\(version)/AutoMAA-\(version)-macOS-arm64.dmg"
                },
                {
                  "name": "AutoMAA-\(version)-macOS-arm64.dmg.sha256",
                  "size": 96,
                  "browser_download_url": "https://github.com/Rememorio/AutoMAA/releases/download/v\(version)/AutoMAA-\(version)-macOS-arm64.dmg.sha256"
                }
              ]
            }
            """.utf8
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "automaa-update-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
