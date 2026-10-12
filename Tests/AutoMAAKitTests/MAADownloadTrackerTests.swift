import Foundation
import Testing
@testable import AutoMAAKit

@Suite("MAA download rate and liveness")
struct MAADownloadTrackerTests {
    @Test("resumed bytes do not inflate speed or the remaining-time estimate")
    func resumedRate() {
        let start = ContinuousClock.now
        var tracker = MAADownloadTracker(initial: sample(500), at: start)
        #expect(tracker.observe(sample(550), at: start + .seconds(1))?.download?.bytesPerSecond == nil)
        let progress = tracker.observe(sample(650), at: start + .seconds(3))?.download
        #expect(progress?.bytesPerSecond == 50)
        #expect(progress?.estimatedRemainingTime == 7)
    }

    @Test("slow but growing downloads do not trip the stall deadline")
    func slowTransfer() {
        let start = ContinuousClock.now
        var tracker = MAADownloadTracker()
        for second in 0...1_000 {
            _ = tracker.observe(sample(Int64(second)), at: start + .seconds(second))
            #expect(!tracker.isStalled(at: start + .seconds(second), timeout: 300))
        }
    }

    @Test("stalls require observed download growth and never apply to extraction or Git")
    func stages() {
        let start = ContinuousClock.now
        var tracker = MAADownloadTracker(initial: sample(500), at: start)
        _ = tracker.observe(sample(500), at: start + .seconds(600))
        #expect(!tracker.isStalled(at: start + .seconds(600), timeout: 300))
        _ = tracker.observe(sample(550), at: start + .seconds(601))
        let paused = tracker.observe(sample(550), at: start + .seconds(610))
        #expect(paused?.download?.bytesPerSecond == 0)
        #expect(paused?.download?.estimatedRemainingTime == nil)
        #expect(tracker.isStalled(at: start + .seconds(901), timeout: 300))
        _ = tracker.observe(.init(message: "正在解压与同步识别数据"), at: start + .seconds(902))
        #expect(!tracker.isStalled(at: start + .seconds(2_000), timeout: 300))
    }

    @Test("restart and total-size changes reset stale rate samples")
    func restartedTransfer() {
        let start = ContinuousClock.now
        var tracker = MAADownloadTracker(initial: sample(100), at: start)
        _ = tracker.observe(sample(400), at: start + .seconds(3))
        #expect(tracker.observe(sample(20), at: start + .seconds(4))?.download?.bytesPerSecond == nil)
        #expect(!tracker.isStalled(at: start + .seconds(500), timeout: 300))
        #expect(tracker.observe(sample(600, total: 2_000), at: start + .seconds(501))?.download?.bytesPerSecond == nil)
    }

    @Test("invalid rates and unknown totals never fabricate an ETA")
    func unknownRate() {
        for rate in [Double.nan, .infinity, -1] {
            #expect(DownloadProgress(receivedBytes: 100, totalBytes: 200, bytesPerSecond: rate).estimatedRemainingTime == nil)
        }
        #expect(DownloadProgress(receivedBytes: 100, totalBytes: nil, bytesPerSecond: 50).estimatedRemainingTime == nil)
        #expect(DownloadProgress(receivedBytes: 100, totalBytes: 200, bytesPerSecond: 0).estimatedRemainingTime == nil)
    }

    private func sample(_ bytes: Int64, total: Int64 = 1_000) -> UpdateProgress {
        .init(message: "下载中", download: .init(receivedBytes: bytes, totalBytes: total))
    }
}
