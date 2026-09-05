import SwiftUI

struct UpdateProgressRow: View {
    let message: String
    let startedAt: Date?
    let limit: String
    var isCancelling = false
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(isCancelling ? "正在取消更新并清理临时文件…" : message)
                    .font(.subheadline)
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
            Spacer(minLength: 8)
            Button(action: cancel) {
                Text(isCancelling ? "正在取消…" : "取消更新")
                    .frame(minWidth: 64)
            }
            .disabled(isCancelling)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
    }
}
