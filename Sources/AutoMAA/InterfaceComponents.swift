import AppKit
import SwiftUI

struct BrandLogo: View {
    private static let image: NSImage = {
        guard let url = Bundle.main.url(forResource: "AutoMAA-logo", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return NSApp.applicationIconImage }
        return image
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

enum PageLayout {
    static let inset: CGFloat = 24
    static let sectionSpacing: CGFloat = 16
    static let contentWidth: CGFloat = 1_060
    static let readingWidth: CGFloat = 900
    static let listWidth: CGFloat = 780
}

struct AppPage<Content: View>: View {
    var width: CGFloat = PageLayout.contentWidth
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.sectionSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PageLayout.inset)
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SectionHeading: View {
    let title: String
    var symbol: String? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let symbol { Label(title, systemImage: symbol) }
                else { Text(title) }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct EditorFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EntityIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityHint(detail)
    }
}

struct StatusBadge: View {
    let title: String
    var color: Color = .secondary

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
            .fixedSize()
    }
}

struct ReorderButtons: View {
    let name: String
    let index: Int
    let count: Int
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { move(-1) } label: { Image(systemName: "chevron.up").frame(width: 24, height: 24) }
                .disabled(index == 0)
                .help("上移\(name)")
                .accessibilityLabel("上移\(name)")
            Button { move(1) } label: { Image(systemName: "chevron.down").frame(width: 24, height: 24) }
                .disabled(index == count - 1)
                .help("下移\(name)")
                .accessibilityLabel("下移\(name)")
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .fixedSize()
    }
}

struct FullWidthDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureHeader(isExpanded: Binding(get: { configuration.isExpanded }, set: { configuration.isExpanded = $0 })) {
                configuration.label
            }
            if configuration.isExpanded {
                configuration.content
                    .disclosureGroupStyle(FullWidthDisclosureStyle())
                    .padding(.top, 8)
            }
        }
    }
}

private struct DisclosureHeader<Label: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var label: Label
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                label.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .onKeyPress(keys: [.space, .return]) { _ in
            isExpanded.toggle()
            return .handled
        }
        .onKeyPress(.rightArrow) { isExpanded = true; return .handled }
        .onKeyPress(.leftArrow) { isExpanded = false; return .handled }
        .background(Color.primary.opacity(isHovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isFocused ? Color.maaAccent : .clear, lineWidth: 2)
        }
        .onHover { isHovered = $0 }
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .accessibilityHint(isExpanded ? "收起内容" : "展开内容")
    }
}

struct DetailDisclosure: View {
    let details: String
    var title = "诊断详情"
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(details)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        } label: {
            Text(title)
        }
        .font(.callout)
    }
}

struct ActivitySearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索记录…", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("搜索运行记录")
                .help("搜索历史运行中的方案、客户端、账号、任务、消息或详情")
            Button {
                text = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill").frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("清除搜索")
            .accessibilityLabel("清除搜索")
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
            .accessibilityHidden(text.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.maaAccent : Color.panelStroke, lineWidth: isFocused ? 2 : 1)
        }
    }
}
