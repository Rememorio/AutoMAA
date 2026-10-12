import Foundation
import Testing
@testable import AutoMAAKit

private struct CacheManifestFetcher: MAACoreReleaseManifestFetching {
    var value: MAACoreReleaseManifest
    var fails = false

    func manifest(at url: URL) async throws -> MAACoreReleaseManifest {
        if fails { throw URLError(.networkConnectionLost) }
        return value
    }
}

@Suite("MAA persistent download cache")
struct MAADownloadCacheTests {
    @Test("partial and complete archives survive a new updater instance", arguments: [false, true])
    func reuse(complete: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var cache: MAADownloadCache? = try fixture.cache()
        let file = try fixture.writeDownload(in: cache!, complete: complete)
        try Data("unverified resource".utf8).write(to: cache!.directory.appending(path: "StageActivityV2.json"))
        try cache!.finish()
        cache = nil
        let next = try fixture.cache()
        let identity = try await next.prepare(fetcher: CacheManifestFetcher(value: fixture.manifest()))
        #expect(identity?.name == Fixture.archive)
        #expect(try Data(contentsOf: file).count == (complete ? 100 : 25))
        #expect(!FileManager.default.fileExists(atPath: next.directory.appending(path: "StageActivityV2.json").path))
        #expect(next.retainedMessage()?.contains(complete ? "完整引擎包" : "续传") == true)
    }

    @Test("an interrupted process keeps partial bytes without a completion callback")
    func abruptExit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var cache: MAADownloadCache? = try fixture.cache()
        let file = try fixture.writeDownload(in: cache!, complete: false)
        cache = nil
        let next = try fixture.cache()
        #expect(try await next.prepare(fetcher: CacheManifestFetcher(value: fixture.manifest())) != nil)
        #expect(try Data(contentsOf: file).count == 25)
    }

    @Test("changed version, size, URL or mirrors invalidate the cached archive", arguments: ["version", "size", "source", "mirrors"])
    func changedIdentity(field: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = try fixture.cache()
        let file = try fixture.writeDownload(in: cache, complete: false)
        let value = fixture.manifest(version: field == "version" ? "1.2.4" : "1.2.3",
                                     size: field == "size" ? 101 : 100,
                                     source: field == "source" ? "https://other.invalid/core.zip" : Fixture.source,
                                     mirrors: field == "mirrors" ? ["https://mirror.invalid/core.zip"] : [])
        #expect(try await cache.prepare(fetcher: CacheManifestFetcher(value: value)) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("network failure during revalidation preserves existing progress")
    func offline() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = try fixture.cache()
        let file = try fixture.writeDownload(in: cache, complete: false)
        await #expect(throws: URLError.self) {
            try await cache.prepare(fetcher: CacheManifestFetcher(value: fixture.manifest(), fails: true))
        }
        #expect(try Data(contentsOf: file).count == 25)
    }

    @Test("same-sized corrupted archives are discarded", arguments: [false, true])
    func corrupted(complete: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = try fixture.cache()
        let file = try fixture.writeDownload(in: cache, complete: complete)
        try cache.finish()
        try Data(repeating: 99, count: complete ? 100 : 25).write(to: file)
        #expect(try await cache.prepare(fetcher: CacheManifestFetcher(value: fixture.manifest())) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("symbolic links cannot become reusable downloads or escape cleanup")
    func symbolicLinks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = try fixture.cache()
        let file = try fixture.writeDownload(in: cache, complete: false)
        try FileManager.default.removeItem(at: file)
        let outside = fixture.root.appending(path: "user-file")
        try Data(repeating: 1, count: 25).write(to: outside)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        #expect(try await cache.prepare(fetcher: CacheManifestFetcher(value: fixture.manifest())) == nil)
        #expect(try Data(contentsOf: outside).count == 25)
    }

    @Test("source, channel and installation each have an independent cache")
    func scopes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var locations: Set<URL> = []
        for index in 0..<4 {
            let paths = fixture.paths(data: index == 3 ? "second-installation" : "data")
            let cache = try MAADownloadCache(paths: paths,
                manifestURL: URL(string: index == 1 ? "https://other.invalid/stable.json" : Fixture.manifestURL)!,
                channel: index == 2 ? .beta : .stable)
            locations.insert(cache.directory)
        }
        #expect(locations.count == 4)
    }

    @Test("expired owned caches are removed without deleting unrelated files")
    func expiration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var cache: MAADownloadCache? = try fixture.cache()
        let directory = cache!.directory
        _ = try fixture.writeDownload(in: cache!, complete: false)
        let unrelated = directory.deletingLastPathComponent().appending(path: "user-file")
        try Data("keep".utf8).write(to: unrelated)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-MAADownloadCache.retention - 1)],
                                             ofItemAtPath: directory.path)
        cache = nil
        let next = try fixture.cache()
        #expect(next.cachedDownload() == nil)
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    }

    @Test("the cache quota also covers abandoned downloads after a process exit")
    func quota() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var cache: MAADownloadCache? = try fixture.cache()
        let file = try fixture.writeDownload(in: cache!, complete: false)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(MAADownloadCache.maximumBytes))
        try handle.close()
        cache = nil
        let next = try fixture.cache()
        #expect(next.cachedDownload() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("concurrent maintenance cannot prune or rewrite another active cache")
    func lock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = try fixture.cache()
        _ = withExtendedLifetime(cache) {
            #expect(throws: RuntimeError.self) { try fixture.cache() }
        }
    }

    private struct Fixture {
        static let archive = "MAA-v1.2.3-macos-runtime-universal.zip"
        static let source = "https://download.invalid/core.zip"
        static let manifestURL = "https://manifest.invalid/stable.json"
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "automaa-download-cache-tests-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func paths(data: String = "data") -> MAAInstallationPaths {
            .init(data: root.appending(path: data), cache: root.appending(path: "cache"),
                  library: root.appending(path: "lib"), resource: root.appending(path: "resource"),
                  hotUpdate: root.appending(path: "MaaResource"))
        }

        func cache() throws -> MAADownloadCache {
            try .init(paths: paths(), manifestURL: URL(string: Self.manifestURL)!, channel: .stable)
        }

        func manifest(version: String = "1.2.3", size: Int64 = 100,
                      source: String = Self.source, mirrors: [String] = []) -> MAACoreReleaseManifest {
            .init(version: "v\(version)", details: .init(assets: [
                .init(name: "MAA-v\(version)-macos-runtime-universal.zip", size: size,
                      browserDownloadURL: source, mirrors: mirrors)
            ]))
        }

        func writeDownload(in cache: MAADownloadCache, complete: Bool) throws -> URL {
            let value: [String: Any] = ["version": "v1.2.3", "details": ["assets": [
                ["name": Self.archive, "size": 100, "browser_download_url": Self.source]
            ]]]
            try JSONSerialization.data(withJSONObject: value).write(to: cache.manifestFile)
            let file = cache.directory.appending(path: Self.archive + (complete ? "" : ".partial"))
            try Data(repeating: 1, count: complete ? 100 : 25).write(to: file)
            return file
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
