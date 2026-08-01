import AutoMAAKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var filteredLogs: [LogEntry] {
        guard !search.isEmpty else { return model.logs }
        return model.logs.filter { $0.message.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("筛选日志", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Button {
                    NSWorkspace.shared.open(model.directories.logs)
                } label: {
                    Label("打开日志目录", systemImage: "folder")
                }
                Button("清空", role: .destructive) { model.clearLogs() }
                    .disabled(model.logs.isEmpty || model.isRunning)
            }
            .padding(20)

            Divider()

            if filteredLogs.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "还没有运行日志" : "没有匹配的日志",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                List(filteredLogs.reversed()) { log in
                    HStack(alignment: .top, spacing: 12) {
                        StatusDot(color: log.level.color)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.message)
                                .font(.callout)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                Text(log.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                if let task = log.task { Text(task.title) }
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("运行日志")
    }
}
