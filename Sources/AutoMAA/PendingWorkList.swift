import AutoMAAKit
import SwiftUI

private extension WorkflowStep {
    var activityAccountID: ActivityAccountID { .init(client: clientID, account: accountID) }
}

struct PendingAccountWork: Identifiable {
    let step: WorkflowStep
    let tasks: [PendingWorkflowItem]
    let recovery: [FightRecoveryItem]
    var id: ActivityAccountID { step.activityAccountID }

    static func groups(items: [PendingWorkflowItem], recovery: [FightRecoveryItem]) -> [Self] {
        let recoveries = Dictionary(grouping: recovery) { $0.step.activityAccountID }
        let recoverySteps = Set(recovery.map(\.step))
        let tasks = Dictionary(grouping: items.filter { !recoverySteps.contains($0.step) }) { $0.step.activityAccountID }
        var seen: Set<ActivityAccountID> = []
        return (recovery.map(\.step) + items.map(\.step)).compactMap { step in
            let id = step.activityAccountID
            guard seen.insert(id).inserted else { return nil }
            return Self(step: step, tasks: tasks[id] ?? [], recovery: recoveries[id] ?? [])
        }
    }
}

struct PendingWorkList: View {
    @EnvironmentObject private var model: AppModel
    let items: [PendingWorkflowItem]
    let recovery: [FightRecoveryItem]

    var body: some View {
        let groups = PendingAccountWork.groups(items: items, recovery: recovery)
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                let context = model.pendingWorkContext(group.step)
                VStack(alignment: .leading, spacing: 7) {
                    Text(context).font(.callout.weight(.medium)).accessibilityAddTraits(.isHeader)
                    ForEach(group.recovery) { item in
                        FightRecoveryRow(item: item, context: context)
                    }
                    if !group.tasks.isEmpty {
                        Text(group.tasks.map(\.title).joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(group.tasks.filter { $0.reason != nil || $0.lastFailure != nil || $0.targets == [.weeklyAnnihilation] }) { item in
                        if let detail = item.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if group.id != groups.last?.id { Divider() }
            }
        }
    }
}
