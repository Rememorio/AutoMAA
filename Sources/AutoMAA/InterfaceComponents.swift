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
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("上移\(name)")
                .accessibilityLabel("上移\(name)")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .help("下移\(name)")
                .accessibilityLabel("下移\(name)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }
}

struct DetailDisclosure: View {
    let details: String
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
            Text(isExpanded ? "收起详情" : "查看详情")
        }
        .font(.caption)
    }
}

struct ActivitySearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索方案、账号或记录", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("搜索活动记录")
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
            Label(model.isCancellingRun ? "正在停止…" : model.runningPlanID == nil ? "取消更新" : "安全停止",
                  systemImage: "stop.fill")
                .frame(minWidth: 76)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .tint(model.runningPlanID == nil ? .maaAccent : .red)
        .disabled(model.isCancellingRun)
        .help(model.runningPlanID == nil ? "取消更新并清理临时文件" : "停止任务，关闭客户端并释放连接")
    }
}
