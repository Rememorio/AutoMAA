import Foundation
import XCTest
@testable import AutoMAAKit

final class UpdateInformationTests: XCTestCase {
    func testMarkdownPreservesSectionsListsAndUpstreamDetails() {
        let blocks = ReleaseNotesMarkdown.blocks("""
        ## 改进

        - 第一项 **变化**
        - 第二项 [说明](https://example.invalid)

        <details open>
        <summary><b>完整说明</b></summary>

        保留完整段落。
        </details>
        ```text
        原始输出
        ```
        """)
        XCTAssertEqual(blocks, [.heading("改进", 2), .bullet("第一项 **变化**"),
                                .bullet("第二项 [说明](https://example.invalid)"), .heading("完整说明", 3),
                                .paragraph("保留完整段落。"), .code("原始输出")])
    }

    func testBundledNotesExcludeUnreleasedAndKeepVersionsSeparate() {
        let notes = ReleaseNotesMarkdown.bundledVersions("""
        # 更新日志
        ## 未发布
        - 还未发布的内容
        ## 1.2.0 - 2026-01-02
        ### 修复
        - 当前版本修复
        ## 1.1.0 - 2026-01-01
        - 之前的变化
        """, repository: "example/utility")
        XCTAssertEqual(notes.map(\.version), ["1.2.0", "1.1.0"])
        XCTAssertEqual(notes[0].highlights, ["当前版本修复"])
        XCTAssertFalse(notes[0].body.contains("未发布"))
        XCTAssertFalse(notes[0].body.contains("之前的变化"))
    }

    func testResourceRevisionReadsPackedRefsAndRejectsCredentialURLs() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "resource"), withIntermediateDirectories: true)
        let revision = String(repeating: "a", count: 40)
        try Data("ref: refs/heads/main\n".utf8).write(to: root.appending(path: ".git/HEAD"))
        try Data("# pack-refs\n\(revision) refs/heads/main\n".utf8).write(to: root.appending(path: ".git/packed-refs"))
        try Data("[remote \"origin\"]\nurl = git@github.com:example/resources.git\n".utf8).write(to: root.appending(path: ".git/config"))
        try Data(#"{"last_updated":"2026-01-02 12:00:00","activity":{"name":"示例活动"}}"#.utf8)
            .write(to: root.appending(path: "resource/version.json"))
        let version = MAAResourceVersion.read(at: root, repository: true)
        XCTAssertEqual(version.revision, revision)
        XCTAssertEqual(version.activity, "示例活动")
        XCTAssertEqual(version.repositoryURL?.absoluteString, "https://github.com/example/resources")
        XCTAssertNil(MAAResourceVersion.githubRepository("https://user:secret@github.com/example/resources"))
        XCTAssertNil(MAAResourceVersion.githubRepository("https://example.invalid/resources"))
        XCTAssertNil(ReleaseNotes.safePageURL(URL(string: "file:///tmp/private")!))
    }

    func testResourceComparisonRequiresActivatedRevisionsFromTheSameSource() {
        let old = MAAInstalledVersions(core: "1.0.0", baseResources: .init(), recognitionData: .init(
            revision: String(repeating: "a", count: 40), repositoryURL: URL(string: "https://github.com/example/resources")))
        var information = MAAUpdateInformation(title: "识别数据", before: old)
        XCTAssertNil(information.resourceComparisonURL)
        information.after = old
        XCTAssertNil(information.resourceComparisonURL)
        information.after?.recognitionData.revision = String(repeating: "b", count: 40)
        XCTAssertNotNil(information.resourceComparisonURL)
        information.after?.recognitionData.repositoryURL = URL(string: "https://github.com/another/resources")
        XCTAssertNil(information.resourceComparisonURL)
    }

    func testReleaseNotesCacheRetainsFullTextAndReadStateAcrossLaunches() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ReleaseNotesCache(directories: AppDirectories(root: root))
        var state = ReleaseNotesCache.State()
        state.releases = [.init(version: "1.2.0", body: "## 修复\n\n- 完整说明", pageURL: URL(string: "https://example.invalid/release"))]
        state.lastOpenedVersion = "1.2.0"
        state.unreadVersion = "1.2.0"
        try cache.save(state)
        XCTAssertEqual(cache.load().releases, state.releases)
        XCTAssertEqual(cache.load().unreadVersion, "1.2.0")
        state.unreadVersion = nil
        try cache.save(state)
        XCTAssertNil(cache.load().unreadVersion)
    }

    func testLegacyLogsRemainReadableWithoutUpdateInformation() throws {
        let entry = LogEntry(level: .info, message: "已有活动")
        let decoded = try JSONDecoder().decode(LogEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertNil(decoded.updateInformation)
        XCTAssertEqual(decoded.message, entry.message)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "automaa-update-information-\(UUID())")
    }
}

private final class NotesProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: Data] = [:]
    private var requests: [String] = []
    func install(_ values: [String: Data]) { lock.withLock { routes = values; requests = [] } }
    func response(_ request: URLRequest) -> Data? {
        lock.withLock {
            let path = request.url!.path
            requests.append(path)
            return routes[path]
        }
    }
    func requestedPaths() -> [String] { lock.withLock { requests } }
}

private final class NotesURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = NotesProtocolState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let data = Self.state.response(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ReleaseNotesServiceTests: XCTestCase {
    func testApplicationHistoryIncludesOnlyTheUpgradeRange() async throws {
        let releases = [release("1.3.0"), release("1.2.1"), release("1.2.0"), release("1.1.0"), release("1.2.2", prerelease: true)]
        let service = try service(routes: ["/repos/example/utility/releases": releases])
        let result = try await service.application(repository: "example/utility", from: "1.1.0", through: "1.2.1")
        XCTAssertEqual(result.releases.map(\.version), ["1.2.1", "1.2.0"])
        XCTAssertNil(result.notice)
    }

    func testCurrentVersionNotesDoNotRequireDownloadAssets() async throws {
        let service = try service(routes: ["/repos/example/utility/releases/tags/v1.2.0": release("1.2.0")])
        let result = try await service.application(repository: "example/utility", from: "1.2.0", through: "1.2.0")
        XCTAssertEqual(result.releases.first?.body, "### 修复\n- 版本 1.2.0 的变化")
        XCTAssertNotNil(result.releases.first?.publishedAt)
    }

    func testCurrentVersionNotesRejectMismatchedTagsAndPrereleases() async throws {
        for response in [release("1.3.0"), release("1.2.0", prerelease: true)] {
            let service = try service(routes: ["/repos/example/utility/releases/tags/v1.2.0": response])
            do {
                _ = try await service.application(repository: "example/utility", from: "1.2.0", through: "1.2.0")
                XCTFail("正式版本说明不能替换成其他版本")
            } catch {}
        }
    }

    func testMAANotesFollowTheConfiguredSourceAndActualInstalledVersion() async throws {
        let manifest: [String: Any] = ["version": "v2.0.0", "details": ["body": "新版本说明", "html_url": "https://github.com/custom/engine/releases/tag/v2.0.0"]]
        var previous = release("1.9.0")
        previous["html_url"] = "https://github.com/custom/engine/releases/tag/v1.9.0"
        let service = try service(routes: ["/custom/stable.json": manifest, "/repos/custom/engine/releases/tags/v1.9.0": previous])
        let source = URL(string: "https://mirror.example/custom/stable.json")!
        let result = try await service.maa(manifestURL: source, version: "1.9.0")
        XCTAssertEqual(result.releases.first?.version, "1.9.0")
        XCTAssertEqual(result.releases.first?.sourceURL, source)
        XCTAssertEqual(NotesURLProtocol.state.requestedPaths(), ["/custom/stable.json", "/repos/custom/engine/releases/tags/v1.9.0"])
    }

    func testMAANotesNeverSubstituteAnUnrelatedVersion() async throws {
        let manifest: [String: Any] = ["version": "v2.0.0", "details": ["body": "新版本说明", "html_url": "https://custom.example/releases/2.0.0"]]
        let service = try service(routes: ["/stable.json": manifest])
        do {
            _ = try await service.maa(manifestURL: URL(string: "https://custom.example/stable.json")!, version: "1.9.0")
            XCTFail("不同版本的说明不能被当作本次变化")
        } catch {}
    }

    func testOfflineLatestMAANotesUseOnlyTheConfiguredSourceCache() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-notes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try MAACoreReleaseManifestEndpoint.url(channel: .stable, configurationData: nil)
        let service = try service(routes: [:])
        let cached = [ReleaseNotes(version: "6.17.0", body: "已保存的说明", sourceURL: source),
                      ReleaseNotes(version: "9.9.9", body: "其他来源", sourceURL: URL(string: "https://example.invalid/stable.json"))]
        let result = try await service.latestMAA(cliPath: "/usr/bin/true", directories: .init(root: root), channel: .stable, cachedNotes: cached)
        XCTAssertEqual(result.releases.map(\.version), ["6.17.0"])
        XCTAssertTrue(result.notice?.contains("无法确认最新说明") == true)
    }

    func testResourceChangesKeepCommitTitlesAndDisclosePartialResults() async throws {
        let old = String(repeating: "a", count: 40), new = String(repeating: "b", count: 40)
        let response: [String: Any] = ["status": "ahead", "total_commits": 25,
                                       "commits": [["commit": ["message": "修复活动关卡识别\n\n更长的提交正文"]]]]
        let service = try service(routes: ["/repos/example/resources/compare/\(old)...\(new)": response])
        let result = try await service.resources(comparisonURL: URL(string: "https://github.com/example/resources/compare/\(old)...\(new)")!)
        XCTAssertEqual(result.releases.first?.body, "- 修复活动关卡识别")
        XCTAssertTrue(result.notice?.contains("25") == true)
    }

    private func release(_ version: String, prerelease: Bool = false) -> [String: Any] {
        ["tag_name": "v\(version)", "body": "### 修复\n- 版本 \(version) 的变化", "html_url": "https://github.com/example/utility/releases/tag/v\(version)",
         "published_at": "2026-01-02T00:00:00Z", "draft": false, "prerelease": prerelease]
    }
    private func service(routes: [String: Any]) throws -> ReleaseNotesService {
        NotesURLProtocol.state.install(try routes.mapValues { try JSONSerialization.data(withJSONObject: $0) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotesURLProtocol.self]
        return ReleaseNotesService(session: URLSession(configuration: configuration))
    }
}
