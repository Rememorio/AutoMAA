import Foundation
import os

public struct DownloadProgress: Equatable, Sendable {
    public let receivedBytes: Int64
    public let totalBytes: Int64?
    public let bytesPerSecond: Double?

    public init(receivedBytes: Int64, totalBytes: Int64?, bytesPerSecond: Double? = nil) {
        self.receivedBytes = max(0, receivedBytes)
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
        self.bytesPerSecond = bytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    public var fractionCompleted: Double? {
        totalBytes.map { min(1, Double(receivedBytes) / Double($0)) }
    }

    public var estimatedRemainingTime: TimeInterval? {
        guard let totalBytes, let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        return Double(max(0, totalBytes - receivedBytes)) / bytesPerSecond
    }
}

struct MAADownloadTracker {
    private struct Sample {
        let time: ContinuousClock.Instant
        let bytes: Int64
    }

    private var samples: [Sample] = []
    private var totalBytes: Int64?
    private var lastGrowth: ContinuousClock.Instant?

    init(initial: UpdateProgress? = nil, at now: ContinuousClock.Instant = .now) {
        if let download = initial?.download {
            samples = [.init(time: now, bytes: download.receivedBytes)]
            totalBytes = download.totalBytes
        }
    }

    mutating func observe(_ update: UpdateProgress?, at now: ContinuousClock.Instant = .now) -> UpdateProgress? {
        guard let update, let download = update.download else {
            self = .init()
            return update
        }
        if let previous = samples.last,
           download.receivedBytes < previous.bytes || totalBytes != download.totalBytes {
            self = .init(initial: update, at: now)
            return update
        }
        if download.receivedBytes > (samples.last?.bytes ?? 0) { lastGrowth = now }
        totalBytes = download.totalBytes
        samples.append(.init(time: now, bytes: download.receivedBytes))
        while samples.count > 2, seconds(from: samples[1].time, to: now) >= 15 { samples.removeFirst() }
        let first = samples[0]
        let elapsed = seconds(from: first.time, to: now)
        var speed: Double?
        if elapsed >= 3 {
            speed = Double(download.receivedBytes - first.bytes) / elapsed
            if let lastGrowth, seconds(from: lastGrowth, to: now) >= 5 { speed = 0 }
        }
        return .init(message: update.message, download: .init(receivedBytes: download.receivedBytes,
                     totalBytes: download.totalBytes, bytesPerSecond: speed))
    }

    func isStalled(at now: ContinuousClock.Instant = .now, timeout: TimeInterval) -> Bool {
        guard let lastGrowth else { return false }
        return seconds(from: lastGrowth, to: now) >= timeout
    }

    private func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: end).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
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
