import AutoMAAKit
import SwiftUI

extension LogEntry {
    var isCarriedForwardFight: Bool {
        if let carriedForwardFight { return carriedForwardFight }
        guard task == .fight, phase == .runningTask, fightResult?.status == .unconfirmed else { return false }
        // These two messages identify carry-forward events recorded before the explicit flag.
        return message.hasSuffix("：保留待确认作战，继续其他任务；请在活动记录的当前待办中处理")
            || message.hasSuffix("：上次作战结果待核实，本次跳过作战并继续其他任务")
    }

    var recordedDropsSummary: String? {
        isCarriedForwardFight || fightResult?.status == .manuallyHandled ? nil : fightResult?.dropsSummary
    }
}

struct ActivityEntryDetails: View {
    let entry: LogEntry
    var showsRecordedDrops = true

    var body: some View {
        if showsRecordedDrops, let summary = entry.recordedDropsSummary {
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
