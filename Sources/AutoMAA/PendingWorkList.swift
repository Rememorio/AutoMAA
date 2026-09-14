import AutoMAAKit
import SwiftUI

struct PendingWorkList: View {
    @EnvironmentObject private var model: AppModel
    let items: [PendingWorkflowItem]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.pendingWorkContext(item.step))
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)
                    Label(item.title, systemImage: item.step.task.symbol)
                        .font(.callout)
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                if item.id != items.last?.id { Divider() }
            }
        }
    }
}
