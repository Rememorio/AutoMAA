import Foundation
import os
import Testing
@testable import AutoMAAKit

private actor DownloadSamples {
    var values: [DownloadProgress] = []
    func append(_ value: DownloadProgress) { values.append(value) }
}

private final class ChunkedDownloadProtocol: URLProtocol, @unchecked Sendable {
    static let chunk = Data(repeating: 42, count: 256 * 1_024)
    static let size = chunk.count * 8
    private let worker = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "update.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let task = Task {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Length": String(Self.size)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for _ in 0..<8 {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didLoad: Self.chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        worker.withLock { $0 = task }
    }

    override func stopLoading() { worker.withLock { $0?.cancel() } }
}

@Suite("Update download progress")
struct UpdateProgressTests {
    @Test("unknown or invalid lengths never fabricate a percentage")
    func unknownLength() {
        #expect(DownloadProgress(receivedBytes: -10, totalBytes: 0).receivedBytes == 0)
        #expect(DownloadProgress(receivedBytes: 42, totalBytes: nil).fractionCompleted == nil)
        #expect(DownloadProgress(receivedBytes: 42, totalBytes: -1).fractionCompleted == nil)
        #expect(DownloadProgress(receivedBytes: 150, totalBytes: 100).fractionCompleted == 1)
    }

    @Test("URLSession reports transferred bytes before the download completes")
    func liveDownload() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, session, asset) = downloadFixture()
        defer { session.invalidateAndCancel() }
        let samples = DownloadSamples()
        let destination = root.appending(path: "download")
        try await service.downloadOnce(asset, to: destination) { await samples.append($0) }
        let values = await samples.values
        #expect(values.contains { $0.receivedBytes > 0 && $0.receivedBytes < Int64(asset.size) })
        #expect(values.last?.receivedBytes == Int64(asset.size))
        #expect(values.allSatisfy { $0.totalBytes == Int64(asset.size) })
        #expect(try Data(contentsOf: destination).count == asset.size)
    }

    @Test("cancelling a download stops progress and does not install a partial file")
    func cancelledDownload() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, session, asset) = downloadFixture()
        defer { session.invalidateAndCancel() }
        let samples = DownloadSamples()
        let destination = root.appending(path: "download")
        let task = Task {
            try await service.downloadOnce(asset, to: destination) { await samples.append($0) }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !samples.values.contains(where: { $0.receivedBytes > 0 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await samples.values.contains { $0.receivedBytes > 0 })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let count = await samples.values.count
        try await Task.sleep(for: .milliseconds(150))
        #expect(await samples.values.count == count)
    }

    @Test("MAA progress follows the partial archive, then switches away from percentage while extracting")
    func stagedMAADownload() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = MAAUpdateProgressReader(cache: root, channel: .stable)
        try writeManifest(in: root)
        let archive = root.appending(path: "MAA-v1.2.3-macos-runtime-universal.zip")
        let partial = archive.appendingPathExtension("partial")
        #expect(reader.read() == nil)
        try Data(repeating: 0, count: 250).write(to: partial)
        #expect(reader.read()?.download?.fractionCompleted == 0.25)
        // A retry restarts from the new file size instead of preserving stale progress.
        try Data(repeating: 0, count: 100).write(to: partial)
        #expect(reader.read()?.download?.fractionCompleted == 0.1)
        try Data(repeating: 0, count: 1_000).write(to: partial)
        try FileManager.default.moveItem(at: partial, to: archive)
        #expect(reader.read()?.download == nil)
        #expect(reader.read()?.message.contains("解压") == true)
    }

    @Test("MAA progress ignores extracted resources, malformed manifests and symbolic links")
    func unrelatedFiles() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = MAAUpdateProgressReader(cache: root, channel: .stable)
        let manifest = root.appending(path: "core-manifest-stable.json")
        try Data("{}".utf8).write(to: manifest)
        #expect(reader.read() == nil)
        try writeManifest(in: root)
        try Data(repeating: 0, count: 500).write(to: root.appending(path: "resource.json"))
        #expect(reader.read() == nil)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "MAA-v1.2.3-macos-runtime-universal.zip.partial"),
            withDestinationURL: root.appending(path: "resource.json"))
        #expect(reader.read() == nil)
        try Data("{\"version\":\"../../outside\",\"details\":{\"assets\":[]}}".utf8).write(to: manifest)
        #expect(reader.read() == nil)
    }

    private func downloadFixture() -> (SoftwareUpdateService, URLSession, SoftwareUpdateAsset) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedDownloadProtocol.self]
        let session = URLSession(configuration: configuration)
        return (SoftwareUpdateService(currentVersion: "1.0.0", session: session), session,
                .init(name: "test.dmg", size: ChunkedDownloadProtocol.size,
                      downloadURL: URL(string: "https://update.invalid/download")!))
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-progress-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeManifest(in root: URL) throws {
        try Data("""
        {"version":"v1.2.3","details":{"assets":[{"name":"MAA-v1.2.3-macos-runtime-universal.zip","size":1000}]}}
        """.utf8).write(to: root.appending(path: "core-manifest-stable.json"))
    }
}
