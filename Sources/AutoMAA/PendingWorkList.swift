import AutoMAAKit
import SwiftUI

struct PendingWorkLinkButton: View {
    let action: () -> Void

    var body: some View {
        ActionTextButton(title: "查看待办", symbol: "chevron.right", tint: .primary,
                         help: "查看剩余任务和需要处理的事项", symbolAfterTitle: true, action: action)
    }
}

struct PendingWorkList: View {
    @EnvironmentObject private var model: AppModel
    let items: [PendingWorkflowItem]
    let recovery: [FightRecoveryItem]

    private var accounts: [WorkflowStep] {
        var seen: Set<UUID> = []
        return (items.map(\.step) + recovery.map(\.step)).filter { seen.insert($0.accountID).inserted }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(accounts, id: \.accountID) { account in
                let problems = recovery.filter { $0.step.accountID == account.accountID }
                let ordinary = items.filter { item in
                    item.step.accountID == account.accountID && !problems.contains(where: { $0.id == item.id })
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.pendingWorkContext(account))
                        .font(.callout.weight(.medium)).accessibilityAddTraits(.isHeader)
                    ForEach(problems) { item in
                        FightRecoveryRow(item: item, context: model.pendingWorkContext(account))
                    }
                    if !ordinary.isEmpty {
                        Text(ordinary.map(\.title).joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(ordinary.filter { $0.reason != nil || $0.lastFailure != nil || $0.targets == [.weeklyAnnihilation] }) { item in
                        if let detail = item.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if account.accountID != accounts.last?.accountID { Divider() }
            }
        }
    }
}
