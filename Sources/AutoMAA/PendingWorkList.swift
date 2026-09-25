import AutoMAAKit
import SwiftUI

struct PendingWorkList: View {
    @EnvironmentObject private var model: AppModel
    let items: [PendingWorkflowItem]

    private var accounts: [WorkflowStep] {
        var seen: Set<String> = []
        return items.map(\.step).filter { seen.insert("\($0.clientID)/\($0.accountID)").inserted }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(accounts, id: \.key) { account in
                let remaining = items.filter { $0.step.clientID == account.clientID && $0.step.accountID == account.accountID }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.pendingWorkContext(account)).font(.callout.weight(.medium))
                        Spacer()
                        Text("剩余 \(remaining.count) 项").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(remaining) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.title, systemImage: item.step.task.symbol).font(.callout)
                                if let detail = item.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}
