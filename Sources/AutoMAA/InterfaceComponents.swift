import SwiftUI

enum PageLayout {
    static let inset: CGFloat = 28
    static let sectionSpacing: CGFloat = 20
    static let contentWidth: CGFloat = 1_060
    static let readingWidth: CGFloat = 900
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
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let symbol { Label(title, systemImage: symbol) }
                else { Text(title) }
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct EntityIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color.maaAccent)
            .frame(width: 54, height: 54)
            .background(Color.maaAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityHint(detail)
        }
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
            TextField("搜索记录…", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("搜索活动记录")
                .help("搜索历史运行中的方案、客户端、账号、任务、消息或详情")
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isFocused ? Color.maaAccent : Color.panelStroke, lineWidth: isFocused ? 2 : 1)
        }
    }
}

struct StopOperationButton: View {
    @EnvironmentObject private var model: AppModel
    var fillsWidth = false

    var body: some View {
        Button { model.cancelRun() } label: {
            Label(model.isCancellingRun ? "正在停止…" : model.activePlanID == nil ? "取消更新" : "安全停止",
                  systemImage: "stop.fill")
                .frame(minWidth: 76)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .tint(model.activePlanID == nil ? .maaAccent : .red)
        .disabled(model.isCancellingRun)
        .help(model.activePlanID == nil ? "取消更新并清理临时文件" : "停止任务，关闭客户端并释放连接")
    }
}
