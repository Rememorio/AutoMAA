import SwiftUI

struct ActivityOutcomeLabel: View {
    let outcome: ActivityOutcome
    var isSelected = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: outcome.symbol)
                .foregroundStyle(outcome.color)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(outcome.title)
                .foregroundStyle(isSelected || outcome == .completed ? Color.secondary : outcome.color)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}
