import SwiftUI

/// Secondary actions whose purpose or destination needs an explicit name.
struct ActionTextButton: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    var help: String? = nil
    var reservedTitles: [String] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionTextLabel(title: title, symbol: symbol, reservedTitles: reservedTitles, tint: tint)
        }
        .buttonStyle(.borderless)
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(help ?? "")
    }
}

struct ActionTextMenu<Content: View>: View {
    let title: String
    let symbol: String
    var help: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            ActionTextLabel(title: title, symbol: symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(.secondary)
        .fixedSize()
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(help ?? "")
    }
}

/// Reserves the widest state label so feedback never moves adjacent content.
struct ActionTextLabel: View {
    let title: String
    let symbol: String
    var reservedTitles: [String] = []
    var tint: Color = .secondary
    var symbolTint: Color? = nil

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(reservedTitles, id: \.self) { title in
                label(title, symbol: symbol).hidden().accessibilityHidden(true)
            }
            label(title, symbol: symbol)
        }
        .font(.callout)
        .fixedSize()
        .frame(minHeight: 26)
        .contentShape(Rectangle())
    }

    private func label(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 14)
                .foregroundStyle(symbolTint ?? tint)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(tint)
        }
    }
}

/// Compact secondary actions retain native button semantics and a full spoken label.
struct ActionIconButton: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

struct ActionIconMenu<Content: View>: View {
    let title: String
    var symbol = "ellipsis"
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .tint(.secondary)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }
}
