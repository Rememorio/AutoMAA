import AppKit
import SwiftUI

private struct WorkspaceChromeKey: EnvironmentKey {
    static let defaultValue: WorkspaceChromeController? = nil
}

extension EnvironmentValues {
    var workspaceChrome: WorkspaceChromeController? {
        get { self[WorkspaceChromeKey.self] }
        set { self[WorkspaceChromeKey.self] = newValue }
    }
}

@MainActor
private func hostedWorkspace<V: View>(_ view: V, model: AppModel, chrome: WorkspaceChromeController?) -> AnyView {
    AnyView(view.environmentObject(model).environment(\.workspaceChrome, chrome)
        .disclosureGroupStyle(FullWidthDisclosureStyle()).tint(.maaAccent))
}

struct WorkspaceShell<Sidebar: View, Content: View>: NSViewControllerRepresentable {
    let chrome: WorkspaceChromeController
    let model: AppModel
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    func makeNSViewController(context: Context) -> WorkspaceSplitController {
        WorkspaceSplitController(chrome: chrome,
            sidebar: hostedWorkspace(sidebar(), model: model, chrome: chrome),
            content: hostedWorkspace(content(), model: model, chrome: chrome))
    }

    func updateNSViewController(_ controller: WorkspaceSplitController, context: Context) {
        controller.sidebarHost.rootView = hostedWorkspace(sidebar(), model: model, chrome: chrome)
        controller.contentHost.rootView = hostedWorkspace(content(), model: model, chrome: chrome)
        chrome.setRunControls(hostedWorkspace(WorkspaceToolbarRunControls(), model: model, chrome: chrome),
                              visible: WorkspaceToolbarRunControls.isVisible(in: model))
    }
}

final class WorkspaceSplitController: NSSplitViewController {
    let chrome: WorkspaceChromeController
    let sidebarHost: NSHostingController<AnyView>
    let contentHost: NSHostingController<AnyView>

    init(chrome: WorkspaceChromeController, sidebar: AnyView, content: AnyView) {
        self.chrome = chrome
        sidebarHost = NSHostingController(rootView: sidebar)
        contentHost = NSHostingController(rootView: content)
        sidebarHost.sizingOptions = []
        contentHost.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 200
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.allowsFullHeightLayout = false
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sidebarItem.holdingPriority = .init(751)
        addSplitViewItem(sidebarItem)
        let contentItem = NSSplitViewItem(viewController: contentHost)
        contentItem.minimumThickness = 680
        addSplitViewItem(contentItem)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window { chrome.attach(to: window, splitController: self) }
    }

    override func toggleSidebar(_ sender: Any?) {
        guard let sidebar = splitViewItems.first else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            sidebar.isCollapsed.toggle()
        } else {
            super.toggleSidebar(sender)
        }
        chrome.sidebarVisibilityDidChange()
    }
}

struct WorkspaceColumns<Content: View, Detail: View>: NSViewControllerRepresentable {
    @EnvironmentObject private var model: AppModel
    @Environment(\.workspaceChrome) private var chrome
    @ViewBuilder var content: () -> Content
    @ViewBuilder var detail: () -> Detail

    func makeNSViewController(context: Context) -> WorkspaceDetailSplitController {
        WorkspaceDetailSplitController(chrome: chrome,
            content: hostedWorkspace(content(), model: model, chrome: chrome),
            detail: hostedWorkspace(detail(), model: model, chrome: chrome))
    }

    func updateNSViewController(_ controller: WorkspaceDetailSplitController, context: Context) {
        controller.contentHost.rootView = hostedWorkspace(content(), model: model, chrome: chrome)
        controller.detailHost.rootView = hostedWorkspace(detail(), model: model, chrome: chrome)
    }

    static func dismantleNSViewController(_ controller: WorkspaceDetailSplitController, coordinator: ()) {
        controller.chrome?.removeDetailSplit(controller.splitView)
    }
}

final class WorkspaceDetailSplitController: NSSplitViewController {
    weak var chrome: WorkspaceChromeController?
    let contentHost: NSHostingController<AnyView>
    let detailHost: NSHostingController<AnyView>

    init(chrome: WorkspaceChromeController?, content: AnyView, detail: AnyView) {
        self.chrome = chrome
        contentHost = NSHostingController(rootView: content)
        detailHost = NSHostingController(rootView: detail)
        contentHost.sizingOptions = []
        detailHost.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        let contentItem = NSSplitViewItem(contentListWithViewController: contentHost)
        contentItem.minimumThickness = 240
        contentItem.maximumThickness = 320
        contentItem.holdingPriority = .init(251)
        addSplitViewItem(contentItem)
        let detailItem = NSSplitViewItem(viewController: detailHost)
        detailItem.minimumThickness = 440
        addSplitViewItem(detailItem)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear() {
        super.viewDidAppear()
        chrome?.setDetailSplit(splitView)
    }

    override func toggleSidebar(_ sender: Any?) { chrome?.toggleSidebar(sender) }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSSplitViewController.toggleSidebar(_:)) {
            return chrome?.canToggleSidebar == true
        }
        return super.validateUserInterfaceItem(item)
    }
}
