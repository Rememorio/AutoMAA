import AutoMAAKit
import SwiftUI

struct ActivityEntryDetails: View {
    let entry: LogEntry

    var body: some View {
        if let drops = entry.fightResult?.totalDrops, !drops.isEmpty {
            Text("总掉落：" + drops)
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
        guard let drops = entry.fightResult?.totalDrops else { return details }
        let prefix = "总掉落：" + drops
        guard details.hasPrefix(prefix) else { return details }
        return String(details.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
