import AutoMAAKit
import SwiftUI

struct ActivitySessionDetail: View {
    let session: ActivitySession
    let context: (LogEntry) -> String?
    @State private var onlyAttention = false

    private var attentionEntries: [LogEntry] { session.entries.filter { $0.level == .warning || $0.level == .error } }
    private var notices: [LogEntry] { attentionEntries.filter { $0.phase != .completed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = session.runSummary {
                Text(summary.completionDescription)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ActivityAccountSummary.groups(in: session)) { account in
                VStack(alignment: .leading, spacing: 8) {
                    Text(context(account.lastEvent) ?? "已移除的账号")
                        .font(.subheadline.weight(.semibold))
                    if account.outcomes.isEmpty {
                        Text("未记录任务结果 · \(account.lastEvent.message)")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(account.outcomes) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: entry.level.symbol).foregroundStyle(entry.level.color)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.message).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let details = entry.details, !details.isEmpty {
                                    DetailDisclosure(details: details)
                                }
                            }
                        }
                        .font(.callout)
                    }
                }
            }
            if !notices.isEmpty {
                DisclosureGroup("提醒与错误 · \(notices.count) 条") {
                    eventList(notices).padding(.top, 10)
                }
                .font(.callout)
            }
            Divider()
            DisclosureGroup("完整过程 · \(session.entries.count) 条") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("只看警告与错误", isOn: $onlyAttention)
                        .toggleStyle(.checkbox).font(.caption)
                    if onlyAttention && attentionEntries.isEmpty {
                        Text("这次运行没有警告或错误").font(.callout).foregroundStyle(.secondary)
                    } else {
                        eventList(onlyAttention ? attentionEntries : session.entries)
                    }
                }
                .padding(.top, 10)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventList(_ entries: [LogEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ActivityEventRow(entry: entry, context: context(entry), drawsConnector: index < entries.count - 1)
            }
        }
    }
}
