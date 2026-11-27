import AutoMAAKit
import SwiftUI

extension LogEntry {
    var recordedDropsSummary: String? {
        // Older carry-forward events embedded the previous run's entire fight result.
        if task == .fight, phase == .runningTask, fightResult?.status == .unconfirmed,
           message.hasSuffix("保留待确认作战，继续其他任务；请在活动记录的当前待办中处理") { return nil }
        return fightResult?.dropsSummary
    }
}

struct ActivityEntryDetails: View {
    let entry: LogEntry

    var body: some View {
        if let summary = entry.recordedDropsSummary {
            Text(summary)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        if let details = diagnosticDetails, !details.isEmpty {
            if details.count <= 180, details.split(separator: "\n").count <= 2 {
                Text(details).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else {
                DetailDisclosure(details: details)
            }
        }
    }

    private var diagnosticDetails: String? {
        guard let details = entry.details else { return nil }
        guard let prefix = entry.fightResult?.dropsSummary else { return details }
        guard details.hasPrefix(prefix) else { return details }
        return String(details.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
