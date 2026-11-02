import AppKit
import SwiftUI

struct WorkspaceToolbarAction {
    let id: String
    let title: String
    let symbol: String
    var isEnabled = true
    var handler: () -> Void = {}
    var menu: [WorkspaceToolbarMenuItem]?
}

enum WorkspaceToolbarMenuItem {
    case action(String, isEnabled: Bool = true, handler: () -> Void)
    case separator
}

struct WorkspaceToolbarMode {
    let title: String
    let symbol: String
    let help: String
}

struct WorkspaceToolbarModes {
    let options: [WorkspaceToolbarMode]
    let selectedIndex: Int
    let select: (Int) -> Void
}

extension View {
    func workspaceToolbar(title: String, actions: [WorkspaceToolbarAction] = [],
                          detailActions: [WorkspaceToolbarAction] = [],
                          modes: WorkspaceToolbarModes? = nil) -> some View {
        background(WorkspaceToolbarAttachment(title: title, actions: actions, detailActions: detailActions, modes: modes)
            .frame(width: 0, height: 0))
    }
}

private struct WorkspaceToolbarAttachment: NSViewRepresentable {
    @Environment(\.workspaceChrome) private var chrome
    let title: String
    let actions: [WorkspaceToolbarAction]
    let detailActions: [WorkspaceToolbarAction]
    let modes: WorkspaceToolbarModes?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        chrome?.setPage(title: title, actions: actions, detailActions: detailActions, modes: modes)
    }
}

@MainActor
private final class WorkspaceToolbarTarget: NSObject {
    var handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invokeToolbarAction(_ sender: Any?) { handler() }
}

@MainActor
final class WorkspaceChromeController: NSObject, NSToolbarDelegate {
    static let sidebarID = NSToolbarItem.Identifier("AutoMAA.Sidebar")
    static let sidebarDividerID = NSToolbarItem.Identifier("AutoMAA.SidebarDivider")
    static let titleID = NSToolbarItem.Identifier("AutoMAA.PageTitle")
    static let detailDividerID = NSToolbarItem.Identifier("AutoMAA.DetailDivider")
    static let detailID = NSToolbarItem.Identifier("AutoMAA.DetailControls")
    static let runID = NSToolbarItem.Identifier("AutoMAA.RunControls")
    static let stopID = NSToolbarItem.Identifier("AutoMAA.StopControl")

    let toolbar = NSToolbar(identifier: "AutoMAA.Workspace.\(UUID().uuidString)")
    private weak var window: NSWindow?
    private weak var splitController: WorkspaceSplitController?
    private weak var model: AppModel?
    private(set) weak var detailSplit: NSSplitView?
    private let titleField = NSTextField(labelWithString: "AutoMAA")
    private var titleWidth: NSLayoutConstraint?
    private var pageActions: [WorkspaceToolbarAction] = []
    private var detailActions: [WorkspaceToolbarAction] = []
    private var pageItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var pageSymbols: [NSToolbarItem.Identifier: String] = [:]
    private var actionTargets: [String: WorkspaceToolbarTarget] = [:]
    private var modes: WorkspaceToolbarModes?
    private var modesGroup: NSToolbarItemGroup?
    private var runPresentation = WorkspaceRunControlState.Presentation.hidden
    private var expectsColumns: Bool?
    private(set) var middleColumnWidth: CGFloat = 280
    private lazy var stopItem: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: Self.stopID)
        item.label = "安全停止"
        item.image = symbol("stop.fill", "安全停止")
        item.isBordered = true
        item.autovalidates = false
        item.target = self
        item.action = #selector(stopCurrentOperation(_:))
        item.visibilityPriority = .user
        return item
    }()
    private lazy var runGroup = NSToolbarItemGroup(itemIdentifier: Self.runID,
        images: [symbol("stop.fill", "安全停止"), symbol("play.fill", "运行方案")],
        selectionMode: .momentary, labels: ["安全停止", "运行方案"],
        target: self, action: #selector(performRunControl(_:)))

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        if #available(macOS 15, *) { toolbar.allowsDisplayModeCustomization = false }
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleWidth = titleField.widthAnchor.constraint(equalToConstant: 140)
        titleWidth?.isActive = true
        configure(runGroup)
        runGroup.label = "运行控制"
        runGroup.visibilityPriority = .user
    }

    func attach(to window: NSWindow, splitController: WorkspaceSplitController) {
        self.window = window
        self.splitController = splitController
        window.title = titleField.stringValue
        window.titleVisibility = .hidden
        // Keep column headers outside the toolbar's scroll-edge backdrop.
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unified
        if window.toolbar !== toolbar { window.toolbar = toolbar }
        reconcileItems()
    }

    func toggleSidebar(_ sender: Any?) { splitController?.toggleSidebar(sender) }
    var canToggleSidebar: Bool { splitController != nil }
    private var isSidebarCollapsed: Bool { splitController?.splitViewItems.first?.isCollapsed == true }

    func sidebarVisibilityDidChange() {
        updateTitleWidth()
        reconcileItems()
    }

    func setPage(title: String, actions: [WorkspaceToolbarAction], detailActions: [WorkspaceToolbarAction] = [],
                 modes: WorkspaceToolbarModes? = nil) {
        titleField.stringValue = title
        titleField.toolTip = title
        titleField.setAccessibilityLabel(title)
        window?.title = title
        pageActions = actions
        self.detailActions = detailActions
        for action in actions + detailActions { updatePageItem(action) }
        updateModes(modes)
        updateTitleWidth()
        reconcileItems()
    }

    func setRunControls(model: AppModel) {
        self.model = model
        switch model.selection {
        case .overview: expectsColumns = false
        case let .plan(id): expectsColumns = model.configuration.plans.contains { $0.id == id }
        case .clients, .client, .account, .activity: expectsColumns = true
        }
        let state = WorkspaceRunControlState(model: model)
        runPresentation = state.presentation
        updateSegment(runGroup, index: 0, enabled: state.canStop, help: state.stopHelp)
        updateSegment(runGroup, index: 1, enabled: state.canStart, help: state.startHelp)
        stopItem.isEnabled = state.canStop
        stopItem.toolTip = state.stopHelp
        if expectsColumns == false { detailSplit = nil }
        reconcileItems()
    }

    func setDetailSplit(_ split: NSSplitView) {
        guard expectsColumns != false else { return }
        guard detailSplit !== split else { return }
        detailSplit = split
        if let item = toolbar.items.first(where: { $0.itemIdentifier == Self.detailDividerID }) as? NSTrackingSeparatorToolbarItem {
            item.splitView = split
        }
        updateTitleWidth()
        reconcileItems()
    }

    func removeDetailSplit(_ split: NSSplitView) {
        guard detailSplit === split else { return }
        // A replacement column controller takes over the tracking item in the same layout pass.
        guard expectsColumns != true else { return }
        detailSplit = nil
        updateTitleWidth()
        reconcileItems()
    }

    func rememberMiddleColumnWidth(_ width: CGFloat, for split: NSSplitView) {
        guard detailSplit === split, width.isFinite, (240...320).contains(width) else { return }
        middleColumnWidth = width
    }

    var itemIdentifiers: [NSToolbarItem.Identifier] {
        var ids = [Self.sidebarID]
        if !isSidebarCollapsed { ids.append(Self.sidebarDividerID) }
        if detailSplit == nil || !isSidebarCollapsed { ids.append(Self.titleID) }
        if detailSplit != nil, !pageActions.isEmpty { ids.append(.flexibleSpace) }
        ids += pageActions.map { pageID($0.id) }
        if detailSplit != nil { ids.append(Self.detailDividerID) }
        if detailSplit != nil { ids += detailActions.map { pageID($0.id) } }
        if runPresentation == .plan { ids.append(Self.runID) }
        if detailSplit != nil, modesGroup != nil { ids.append(Self.detailID) }
        if runPresentation == .stop {
            ids += [.space, Self.stopID]
        }
        ids.append(.flexibleSpace)
        return ids
    }

    private func updateTitleWidth() {
        titleWidth?.constant = detailSplit == nil || pageActions.count < 2 ? 140 : 80
        titleField.invalidateIntrinsicContentSize()
    }

    private func pageID(_ id: String) -> NSToolbarItem.Identifier { .init("AutoMAA.PageAction.\(id)") }

    private func updatePageItem(_ action: WorkspaceToolbarAction) {
        let id = pageID(action.id)
        let item: NSToolbarItem
        if let existing = pageItems[id] {
            item = existing
        } else if action.menu != nil {
            let menu = NSMenuToolbarItem(itemIdentifier: id)
            menu.showsIndicator = action.symbol == "plus"
            item = menu
            pageItems[id] = item
        } else {
            item = NSToolbarItem(itemIdentifier: id)
            pageItems[id] = item
        }
        item.label = action.title
        item.toolTip = action.title
        if pageSymbols[id] != action.symbol {
            item.image = symbol(action.symbol, action.title)
            pageSymbols[id] = action.symbol
        }
        item.isBordered = true
        item.autovalidates = false
        item.isEnabled = action.isEnabled
        if let entries = action.menu, let menu = item as? NSMenuToolbarItem {
            menu.menu = makeMenu(entries)
        } else {
            let target = actionTargets[action.id] ?? WorkspaceToolbarTarget(action.handler)
            target.handler = action.handler
            actionTargets[action.id] = target
            item.target = target
            item.action = #selector(WorkspaceToolbarTarget.invokeToolbarAction(_:))
        }
    }

    private func makeMenu(_ entries: [WorkspaceToolbarMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator: menu.addItem(.separator())
            case let .action(title, enabled, handler):
                let target = WorkspaceToolbarTarget(handler)
                let item = NSMenuItem(title: title, action: #selector(WorkspaceToolbarTarget.invokeToolbarAction(_:)), keyEquivalent: "")
                item.target = target
                item.representedObject = target
                item.isEnabled = enabled
                menu.addItem(item)
            }
        }
        return menu
    }

    private func updateModes(_ modes: WorkspaceToolbarModes?) {
        let changed = self.modes?.options.map(\.symbol) != modes?.options.map(\.symbol)
        self.modes = modes
        guard let modes else { modesGroup = nil; return }
        if modesGroup == nil || changed {
            let group = NSToolbarItemGroup(itemIdentifier: Self.detailID,
                images: modes.options.map { symbol($0.symbol, $0.title) }, selectionMode: .selectOne,
                labels: modes.options.map(\.title), target: self, action: #selector(selectMode(_:)))
            configure(group)
            group.label = "详情内容"
            group.visibilityPriority = .high
            modesGroup = group
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.detailID }) {
                toolbar.removeItem(at: index)
            }
        }
        if let group = modesGroup {
            for (index, option) in modes.options.enumerated() {
                updateSegment(group, index: index, enabled: true, help: option.help)
            }
            group.selectedIndex = modes.selectedIndex
        }
    }

    private func configure(_ group: NSToolbarItemGroup) {
        group.controlRepresentation = .expanded
        group.isBordered = true
        group.autovalidates = false
        for item in group.subitems { item.autovalidates = false }
    }

    private func updateSegment(_ group: NSToolbarItemGroup, index: Int, enabled: Bool, help: String) {
        group.subitems[index].isEnabled = enabled
        group.subitems[index].toolTip = help
        if let control = group.view as? NSSegmentedControl {
            control.setEnabled(enabled, forSegment: index)
            control.setToolTip(help, forSegment: index)
        }
    }

    @objc private func performRunControl(_ sender: Any?) {
        guard let model else { return }
        let index = (sender as? NSToolbarItemGroup)?.selectedIndex
            ?? (sender as? NSSegmentedControl)?.selectedSegment ?? runGroup.selectedIndex
        if index == 0 {
            guard WorkspaceRunControlState(model: model).canStop else { return }
            model.cancelCurrentOperation()
        } else if index == 1 {
            WorkspaceRunControlState(model: model).start(in: model)
        }
    }

    @objc private func stopCurrentOperation(_ sender: Any?) {
        guard let model, WorkspaceRunControlState(model: model).canStop else { return }
        model.cancelCurrentOperation()
    }

    @objc private func selectMode(_ sender: Any?) {
        guard let modes else { return }
        let index = (sender as? NSToolbarItemGroup)?.selectedIndex
            ?? (sender as? NSSegmentedControl)?.selectedSegment ?? modesGroup?.selectedIndex ?? -1
        guard modes.options.indices.contains(index) else { return }
        modes.select(index)
    }

    private func symbol(_ name: String, _ title: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: title) ?? NSImage()
    }

    private func reconcileItems() {
        guard window != nil else { return }
        let desired = itemIdentifiers
        for index in toolbar.items.indices.reversed() where !desired.contains(toolbar.items[index].itemIdentifier) {
            toolbar.removeItem(at: index)
        }
        for (index, id) in desired.enumerated() {
            if index < toolbar.items.count, toolbar.items[index].itemIdentifier == id { continue }
            if let old = toolbar.items.indices.dropFirst(index).first(where: { toolbar.items[$0].itemIdentifier == id }) {
                toolbar.removeItem(at: old)
            }
            toolbar.insertItem(withItemIdentifier: id, at: index)
        }
        while toolbar.items.count > desired.count {
            toolbar.removeItem(at: toolbar.items.count - 1)
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
        if id == Self.runID { return runGroup }
        if id == Self.stopID { return stopItem }
        if id == Self.detailID { return modesGroup }
        if let item = pageItems[id] { return item }
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.sidebarID:
            item.label = "切换边栏"
            item.toolTip = "显示或隐藏边栏（⌃⌘S）"
            item.image = symbol("sidebar.left", "切换边栏")
            item.isBordered = true
            item.target = splitController
            item.action = #selector(NSSplitViewController.toggleSidebar(_:))
            item.isNavigational = true
            item.visibilityPriority = .high
        case Self.titleID:
            item.label = "当前页面"
            item.view = titleField
        default: return nil
        }
        return item
    }
}
