import XCTest
@testable import AutoMAAKit

final class SupportDiagnosticsTests: XCTestCase {
    func testTextContainsUsefulEnvironmentInformation() {
        let diagnostics = SupportDiagnostics(
            applicationVersion: "0.3.1",
            applicationBuild: "20260802010101",
            operatingSystem: "Version 26.0 (Build 25A123)",
            architecture: "arm64",
            maaVersionSummary: "maa-cli v0.7.5\nMaaCore v6.16.1",
            configurationSchemaVersion: 4,
            updateRepository: "Rememorio/AutoMAA"
        )

        XCTAssertEqual(
            diagnostics.text,
            """
            AutoMAA: v0.3.1 (build 20260802010101)
            macOS: Version 26.0 (Build 25A123)
            架构: arm64
            maa-cli v0.7.5
            MaaCore v6.16.1
            配置协议: v4
            更新源: Rememorio/AutoMAA
            """
        )
    }

    func testTextDoesNotCopyEnvironmentErrorsOrPrivatePaths() {
        let diagnostics = SupportDiagnostics(
            applicationVersion: "0.3.1",
            applicationBuild: "local",
            operatingSystem: "Version 14.0",
            architecture: "arm64",
            maaVersionSummary: "maa-cli /Users/example/private/maa\n检测失败：/Users/example/private/maa 不存在",
            configurationSchemaVersion: 4,
            updateRepository: "Rememorio/AutoMAA"
        )

        XCTAssertTrue(diagnostics.text.contains("MAA 环境: 未检测或不可用"))
        XCTAssertFalse(diagnostics.text.contains("/Users/example"))
    }
}
