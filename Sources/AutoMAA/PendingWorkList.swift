import AutoMAAKit
import SwiftUI

struct PendingWorkList: View {
    @EnvironmentObject private var model: AppModel
    let items: [PendingWorkflowItem]
    var showsStageSettings = false

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
                                if item.reason != nil || item.lastFailure != nil || item.targets == [.weeklyAnnihilation],
                                   let detail = item.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                                if showsStageSettings, model.canOpenFightStageSettings(for: item.step) {
                                    Button("前往关卡设置") { model.openFightStageSettings(for: item.step) }
                                        .buttonStyle(.link)
                                        .font(.caption)
                                        .help("在自定义参数中调整关卡策略和兜底关卡")
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
