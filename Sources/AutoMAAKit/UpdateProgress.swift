import Foundation
import os

public struct DownloadProgress: Equatable, Sendable {
    public let receivedBytes: Int64
    public let totalBytes: Int64?

    public init(receivedBytes: Int64, totalBytes: Int64?) {
        self.receivedBytes = max(0, receivedBytes)
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
    }

    public var fractionCompleted: Double? {
        totalBytes.map { min(1, Double(receivedBytes) / Double($0)) }
    }
}

public struct UpdateProgress: Equatable, Sendable {
    public let message: String
    public let download: DownloadProgress?

    public init(message: String, download: DownloadProgress? = nil) {
        self.message = message
        self.download = download
    }
}

final class UpdateDownloadDelegate: NSObject, URLSessionTaskDelegate {
    let updates: AsyncStream<DownloadProgress>.Continuation
    let expectedSize: Int64
    private let observation = OSAllocatedUnfairLock<NSKeyValueObservation?>(uncheckedState: nil)

    init(updates: AsyncStream<DownloadProgress>.Continuation, expectedSize: Int64) {
        self.updates = updates
        self.expectedSize = expectedSize
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        // The async download API forwards task lifecycle callbacks, not download delegate progress.
        let observer = task.observe(\.countOfBytesReceived, options: [.initial, .new]) { [updates, expectedSize] task, _ in
            updates.yield(.init(receivedBytes: task.countOfBytesReceived, totalBytes: expectedSize))
        }
        observation.withLock { $0 = observer }
    }

    func stopObserving() {
        let observer = observation.withLock { value in
            let observer = value
            value = nil
            return observer
        }
        observer?.invalidate()
    }
}

struct MAAUpdateProgressReader: Sendable {
    let cache: URL
    let channel: MAAUpdateChannel

    func read() -> UpdateProgress? {
        // maa-cli writes the manifest and growing .partial archive to this isolated cache.
        // Inspect only download files; extracted resources are not transferred bytes.
        let manifestURL = cache.appending(path: "core-manifest-\(channel.rawValue).json")
        guard let asset = MAACoreReleaseManifest.read(at: manifestURL)?.macOSAsset else { return nil }
        let archive = cache.appending(path: asset.name)
        if let received = MAADownloadCache.regularFileSize(archive.appendingPathExtension("partial")) {
            return .init(message: "正在下载 MAA 引擎与基础识别数据…",
                         download: .init(receivedBytes: received, totalBytes: asset.size))
        }
        if MAADownloadCache.regularFileSize(archive) == asset.size {
            return .init(message: "下载完成，正在解压与同步识别数据…")
        }
        return nil
    }

}
