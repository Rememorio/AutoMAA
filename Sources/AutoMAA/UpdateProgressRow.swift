import AutoMAAKit
import SwiftUI

struct UpdateProgressRow: View {
    let message: String
    var progress: DownloadProgress? = nil
    let startedAt: Date?
    var isCancelling = false
    var showsTransferRate = false
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if progress?.fractionCompleted == nil || isCancelling {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                    }
                    Text(isCancelling ? "正在取消并清理更新文件…" : message)
                        .font(.subheadline)
                    if let startedAt, progress == nil, !isCancelling {
                        Spacer(minLength: 4)
                        Text("已用 \(Text(startedAt, style: .timer))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .frame(minHeight: 26, alignment: .leading)
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
                    if showsTransferRate, let transfer = transferSummary(download) {
                        Text(transfer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActionIconButton(title: isCancelling ? "正在取消更新" : "取消更新", symbol: "xmark.circle",
                             help: isCancelling ? "正在结束传输并清理临时文件" : "取消更新并清理临时文件", action: cancel)
            .disabled(isCancelling)
            .opacity(isCancelling ? 0 : 1)
            .accessibilityHidden(isCancelling)
        }
        .accessibilityElement(children: .contain)
    }

    private func downloadSummary(_ download: DownloadProgress) -> String {
        let received = ByteCountFormatter.string(fromByteCount: download.receivedBytes, countStyle: .file)
        if let total = download.totalBytes {
            let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "已下载 \(received) / \(size)"
        }
        return "已下载 \(received)"
    }

    private func transferSummary(_ download: DownloadProgress) -> String? {
        guard let speed = download.bytesPerSecond else { return nil }
        guard speed > 0 else { return "暂无新增下载数据" }
        let rate = ByteCountFormatter.string(fromByteCount: Int64(exactly: speed.rounded()) ?? .max, countStyle: .file)
        guard let remaining = download.estimatedRemainingTime, remaining.isFinite, remaining > 0 else { return "\(rate)/s" }
        if remaining < 60 { return "\(rate)/s · 下载剩余不到 1 分钟" }
        let minutes = Int64(exactly: ceil(remaining / 60)) ?? .max
        return "\(rate)/s · 下载约剩余 \(max(1, minutes)) 分钟"
    }
}
