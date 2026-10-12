import AutoMAAKit
import SwiftUI

struct UpdateProgressRow: View {
    let message: String
    var progress: DownloadProgress? = nil
    let startedAt: Date?
    let limit: String
    var isCancelling = false
    var showsTransferRate = false
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(isCancelling ? "正在结束传输并整理更新文件…" : message)
                        .font(.subheadline)
                }
                if !isCancelling, let download = progress {
                    if let fraction = download.fractionCompleted {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .accessibilityLabel("下载进度")
                    }
                    HStack {
                        Text(downloadSummary(download))
                        Spacer(minLength: 8)
                        if let fraction = download.fractionCompleted {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    if showsTransferRate {
                        Text(transferSummary(download))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let startedAt {
                        Text("已用时")
                        Text(startedAt, style: .timer)
                            .monospacedDigit()
                            .fixedSize()
                        Text("·")
                    }
                    Text(limit)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: cancel) {
                Text(isCancelling ? "正在取消…" : "取消更新")
                    .frame(minWidth: 64)
            }
            .disabled(isCancelling)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
    }

    private func downloadSummary(_ download: DownloadProgress) -> String {
        let received = ByteCountFormatter.string(fromByteCount: download.receivedBytes, countStyle: .file)
        if let total = download.totalBytes {
            let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "已下载 \(received) / \(size)"
        }
        return "已下载 \(received) · 总大小未知"
    }

    private func transferSummary(_ download: DownloadProgress) -> String {
        guard let speed = download.bytesPerSecond else { return "正在估算下载速度…" }
        guard speed > 0 else { return "暂无新增下载数据" }
        let rate = ByteCountFormatter.string(fromByteCount: Int64(exactly: speed.rounded()) ?? .max, countStyle: .file)
        guard let remaining = download.estimatedRemainingTime, remaining.isFinite else { return "\(rate)/s" }
        let minutes = Int64(exactly: ceil(remaining / 60)) ?? .max
        return "\(rate)/s · 下载约剩余 \(max(1, minutes)) 分钟"
    }
}
