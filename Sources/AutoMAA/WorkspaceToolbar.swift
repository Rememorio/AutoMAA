import AppKit
import SwiftUI

struct WorkspaceToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.45)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                }
            }
    }
}

extension View {
    func workspaceToolbar<Actions: View, Detail: View>(title: String,
        @ViewBuilder actions: () -> Actions, @ViewBuilder detail: () -> Detail) -> some View {
        background(WorkspaceToolbarAttachment(title: title,
            actions: AnyView(actions()),
            detail: AnyView(HStack(spacing: 6) { detail() }))
            .frame(width: 0, height: 0))
    }

    func workspaceToolbar(title: String) -> some View {
        workspaceToolbar(title: title) { EmptyView() } detail: { EmptyView() }
    }
}

private struct WorkspaceToolbarAttachment: NSViewRepresentable {
    @EnvironmentObject private var model: AppModel
    @Environment(\.workspaceChrome) private var chrome
    let title: String
    let actions: AnyView
    let detail: AnyView

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        chrome?.setPage(title: title,
            actions: AnyView(actions.environmentObject(model).tint(.primary)),
            detail: AnyView(detail.environmentObject(model).tint(.maaAccent)))
    }
}

@MainActor
final class WorkspaceChromeController: NSObject, NSToolbarDelegate {
    static let sidebarID = NSToolbarItem.Identifier("AutoMAA.Sidebar")
    static let sidebarDividerID = NSToolbarItem.Identifier("AutoMAA.SidebarDivider")
    static let titleID = NSToolbarItem.Identifier("AutoMAA.PageTitle")
    static let detailDividerID = NSToolbarItem.Identifier("AutoMAA.DetailDivider")
    static let detailID = NSToolbarItem.Identifier("AutoMAA.DetailControls")
    static let runID = NSToolbarItem.Identifier("AutoMAA.RunControls")

    let toolbar = NSToolbar(identifier: "AutoMAA.Workspace.\(UUID().uuidString)")
    private weak var window: NSWindow?
    private weak var splitController: WorkspaceSplitController?
    private(set) weak var detailSplit: NSSplitView?
    private let titleField = NSTextField(labelWithString: "AutoMAA")
    private let pageHeader = NSStackView()
    private var titleWidth: NSLayoutConstraint?
    private let actionsHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let detailHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let runHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var showsRunControls = false
    private var pageActions = AnyView(EmptyView())

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        if #available(macOS 15, *) { toolbar.allowsDisplayModeCustomization = false }
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleWidth = titleField.widthAnchor.constraint(lessThanOrEqualToConstant: 140)
        titleWidth?.isActive = true
        titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        for host in [actionsHost, detailHost, runHost] {
            host.sizingOptions = [.intrinsicContentSize]
        }
        pageHeader.orientation = .horizontal
        pageHeader.alignment = .centerY
        pageHeader.distribution = .gravityAreas
        pageHeader.spacing = 8
        pageHeader.setViews([titleField, actionsHost], in: .leading)
        titleField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        actionsHost.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    func attach(to window: NSWindow, splitController: WorkspaceSplitController) {
        self.window = window
        self.splitController = splitController
        window.title = titleField.stringValue
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        if window.toolbar !== toolbar { window.toolbar = toolbar }
        reconcileItems()
    }

    func toggleSidebar(_ sender: Any?) { splitController?.toggleSidebar(sender) }

    var canToggleSidebar: Bool { splitController != nil }

    func sidebarVisibilityDidChange() {
        updatePageActions()
        reconcileItems()
    }

    private var isSidebarCollapsed: Bool { splitController?.splitViewItems.first?.isCollapsed == true }

    func setPage(title: String, actions: AnyView, detail: AnyView) {
        titleField.stringValue = title
        titleField.toolTip = title
        titleField.setAccessibilityLabel(title)
        window?.title = title
        pageActions = actions
        updatePageActions()
        detailHost.rootView = styled(detail)
    }

    func setRunControls(_ view: AnyView, visible: Bool) {
        runHost.rootView = styled(view)
        guard showsRunControls != visible else { return }
        showsRunControls = visible
        reconcileItems()
    }

    func setDetailSplit(_ split: NSSplitView) {
        guard detailSplit !== split else { return }
        detailSplit = split
        if let item = toolbar.items.first(where: { $0.itemIdentifier == Self.detailDividerID }) as? NSTrackingSeparatorToolbarItem {
            item.splitView = split
        }
        updatePageActions()
        reconcileItems()
    }

    func removeDetailSplit(_ split: NSSplitView) {
        guard detailSplit === split else { return }
        detailSplit = nil
        updatePageActions()
        reconcileItems()
    }

    var itemIdentifiers: [NSToolbarItem.Identifier] {
        var ids = [Self.sidebarID]
        if !isSidebarCollapsed { ids.append(Self.sidebarDividerID) }
        ids.append(Self.titleID)
        if detailSplit != nil { ids += [Self.detailDividerID, Self.detailID] }
        ids.append(.flexibleSpace)
        if showsRunControls { ids.append(Self.runID) }
        return ids
    }

    private func styled(_ view: AnyView) -> AnyView {
        AnyView(view.font(.callout).controlSize(.regular)
            .labelStyle(.iconOnly)
            .buttonStyle(WorkspaceToolbarButtonStyle()).menuStyle(.borderlessButton)
            .fixedSize().frame(maxWidth: .infinity, alignment: .leading))
    }

    private func updatePageActions() {
        titleWidth?.constant = detailSplit == nil ? 140 : (isSidebarCollapsed ? 52 : 90)
        if isSidebarCollapsed, detailSplit != nil {
            actionsHost.rootView = styled(AnyView(Menu {
                pageActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .help("页面操作").accessibilityLabel("页面操作")))
        } else {
            actionsHost.rootView = styled(AnyView(HStack(spacing: 6) { pageActions }))
        }
        actionsHost.layoutSubtreeIfNeeded()
        actionsHost.invalidateIntrinsicContentSize()
        pageHeader.setFrameSize(pageHeader.fittingSize)
        pageHeader.needsLayout = true
        pageHeader.layoutSubtreeIfNeeded()
    }

    private func reconcileItems() {
        guard window != nil else { return }
        let desired = itemIdentifiers
        for index in toolbar.items.indices.reversed() where !desired.contains(toolbar.items[index].itemIdentifier) {
            toolbar.removeItem(at: index)
        }
        for (index, id) in desired.enumerated() {
            if index < toolbar.items.count, toolbar.items[index].itemIdentifier == id { continue }
            if let old = toolbar.items.firstIndex(where: { $0.itemIdentifier == id }) { toolbar.removeItem(at: old) }
            toolbar.insertItem(withItemIdentifier: id, at: index)
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { itemIdentifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { itemIdentifiers }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.sidebarDividerID, let splitController {
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitController.splitView, dividerIndex: 0)
        }
        if id == Self.detailDividerID, let detailSplit {
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: detailSplit, dividerIndex: 0)
        }
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.sidebarID:
            item.label = "切换边栏"
            item.toolTip = "显示或隐藏边栏（⌃⌘S）"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "切换边栏")
            item.target = splitController
            item.action = #selector(NSSplitViewController.toggleSidebar(_:))
            item.isNavigational = true
            item.visibilityPriority = .high
        case Self.titleID:
            item.label = "当前页面"
            item.view = pageHeader
        case Self.detailID:
            item.label = "详情内容"
            item.view = detailHost
            item.visibilityPriority = .high
        case Self.runID:
            item.label = "运行控制"
            item.view = runHost
            item.visibilityPriority = .user
        default: return nil
        }
        return item
    }
}
