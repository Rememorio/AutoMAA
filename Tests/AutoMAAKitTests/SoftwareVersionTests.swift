import Foundation
import XCTest
@testable import AutoMAAKit

final class SoftwareVersionTests: XCTestCase {
    func testRejectsMalformedSemanticVersions() {
        let invalid = ["", " ", "v", "+metadata", "1.2", "1.2.3.4", "-1.2.3", "01.2.3", "1.02.3", "1.2.03",
                       "1.2.3-", "1.2.3+", "1.2.3-beta..1", "1.2.3-beta.01", "1.2.3-01", "1.2.3-beta_1",
                       "1.2.3-测试", "1.2.3+build..1", "1.2.3+build+other", "1.2.3 beta", "999999999999999999999999.0.0"]
        for value in invalid { XCTAssertNil(SoftwareVersion(value), value) }
    }

    func testPreservesReleaseIdentityWhileIgnoringBuildMetadataInPrecedence() throws {
        let first = try XCTUnwrap(SoftwareVersion(" v0.16.0-beta.1+build.001 \n"))
        let second = try XCTUnwrap(SoftwareVersion("0.16.0-beta.1+different"))
        XCTAssertEqual(first.description, "0.16.0-beta.1+build.001")
        XCTAssertEqual(first.coreVersion, "0.16.0")
        XCTAssertTrue(first.isPrerelease)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first < second)
        XCTAssertFalse(second < first)
        XCTAssertFalse(try XCTUnwrap(SoftwareVersion("V0.16.0+build.001")).isPrerelease)
        let decoded = try JSONDecoder().decode(SoftwareVersion.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(decoded.description, first.description)
    }

    func testSemanticVersionPrecedenceAndArbitrarilyLongNumericIdentifiers() throws {
        let strings = ["0.15.10", "0.16.0-alpha", "0.16.0-alpha.1", "0.16.0-alpha.beta", "0.16.0-beta",
                       "0.16.0-beta.2", "0.16.0-beta.10", "0.16.0-beta.999999999999999999999999999999",
                       "0.16.0-beta.1000000000000000000000000000000", "0.16.0-rc.1", "0.16.0", "0.16.1-alpha"]
        let versions = try strings.map { try XCTUnwrap(SoftwareVersion($0)) }
        for (left, right) in zip(versions, versions.dropFirst()) { XCTAssertLessThan(left, right) }
        XCTAssertEqual(versions.reversed().sorted().map(\.description), strings)
    }

    func testOldVersionJSONDecodesAndCorruptVersionsAreRejected() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(SoftwareVersion.self, from: Data(#"{"major":0,"minor":15,"patch":10}"#.utf8))
        XCTAssertEqual(old.description, "0.15.10")
        for value in [#"{"major":-1,"minor":0,"patch":0}"#,
                      #"{"major":1,"minor":0,"patch":0,"prerelease":["01"]}"#,
                      #"{"major":1,"minor":0,"patch":0,"buildMetadata":[""]}"#] {
            XCTAssertThrowsError(try decoder.decode(SoftwareVersion.self, from: Data(value.utf8)))
        }
    }

    func testExistingConfigurationKeepsPlansAndDefaultsToStableChannel() throws {
        var original = AppConfiguration(clients: [], plans: [.init(name: "保留的方案")])
        original.applicationUpdates.automaticallyDownloadsUpdates = true
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["applicationUpdates"] = ["automaticallyDownloadsUpdates": true]
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.applicationUpdates.channel, .stable)
        var preview = decoded
        preview.applicationUpdates.receivesPrereleaseUpdates = true
        let restored = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(preview))
        XCTAssertEqual(restored, preview)
        XCTAssertEqual(restored.applicationUpdates.channel, .preview)
    }

    func testApplicationVersionValidationChecksFullIdentityAndNumericCore() throws {
        let preview: [String: Any] = ["AutoMAAReleaseVersion": "0.16.0-beta.1", "CFBundleShortVersionString": "0.16.0"]
        XCTAssertNoThrow(try ApplicationReleaseVersion.validate(info: preview, expectedVersion: "0.16.0-beta.1"))
        for expected in ["0.16.0-beta.2", "0.16.0"] {
            XCTAssertThrowsError(try ApplicationReleaseVersion.validate(info: preview, expectedVersion: expected))
        }
        let invalid: [[String: Any]] = [
            ["AutoMAAReleaseVersion": "0.16.0-beta.1", "CFBundleShortVersionString": "0.15.10"],
            ["AutoMAAReleaseVersion": "0.16.0-beta.1", "CFBundleShortVersionString": "0.16.0-beta.1"],
            ["AutoMAAReleaseVersion": "v0.16.0", "CFBundleShortVersionString": "0.16.0"],
            ["AutoMAAReleaseVersion": "invalid", "CFBundleShortVersionString": "0.16.0"],
            ["AutoMAAReleaseVersion": 16, "CFBundleShortVersionString": "0.16.0"],
            ["AutoMAAReleaseVersion": "0.16.0"],
            ["CFBundleShortVersionString": "0.16.0-beta.1"],
        ]
        for info in invalid { XCTAssertThrowsError(try ApplicationReleaseVersion.validate(info: info, expectedVersion: nil)) }
        XCTAssertNoThrow(try ApplicationReleaseVersion.validate(info: ["CFBundleShortVersionString": "0.15.10"], expectedVersion: "0.15.10"))
        XCTAssertThrowsError(try ApplicationReleaseVersion.validate(info: ["CFBundleShortVersionString": "0.16.0"], expectedVersion: "0.16.0-beta.1"))
    }
}
