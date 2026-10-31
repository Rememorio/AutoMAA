import AppKit
import SwiftUI
import Testing
@testable import AutoMAA

@MainActor
@Suite("Workspace window chrome")
struct WorkspaceChromeTests {
    @Test("the first page and subsequent navigation keep an accessible window title")
    func pageTitlesSurviveAttachment() {
        let chrome = WorkspaceChromeController()
        chrome.setPage(title: "演示方案", actions: AnyView(EmptyView()), detail: AnyView(EmptyView()))
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }

        chrome.attach(to: window, splitController: root)
        let frame = window.frame
        #expect(window.title == "演示方案")
        #expect(window.titleVisibility == .hidden)
        #expect(window.toolbar === chrome.toolbar)

        chrome.setPage(title: "运行记录", actions: AnyView(EmptyView()), detail: AnyView(EmptyView()))
        #expect(window.title == "运行记录")
        #expect(window.toolbar === chrome.toolbar)
        #expect(window.frame == frame)
    }

    @Test("native separators follow the current columns and ignore cleanup from a previous page")
    func trackingSeparatorsFollowCurrentColumns() throws {
        let chrome = WorkspaceChromeController()
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        chrome.attach(to: window, splitController: root)
        let sidebar = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.sidebarDividerID }
            as? NSTrackingSeparatorToolbarItem)
        #expect(sidebar.splitView === root.splitView)
        #expect(sidebar.dividerIndex == 0)

        let previous = makeDetail(chrome: chrome)
        let current = makeDetail(chrome: chrome)
        chrome.setDetailSplit(previous.splitView)
        chrome.setDetailSplit(current.splitView)
        chrome.removeDetailSplit(previous.splitView)

        let tracked = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.detailDividerID }
            as? NSTrackingSeparatorToolbarItem)
        #expect(chrome.detailSplit === current.splitView)
        #expect(tracked.splitView === current.splitView)
        #expect(chrome.toolbar.items.filter { $0.itemIdentifier == WorkspaceChromeController.detailDividerID }.count == 1)

        chrome.removeDetailSplit(current.splitView)
        #expect(chrome.detailSplit == nil)
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.detailDividerID })
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.detailID })
        #expect(chrome.toolbar.items.contains { $0 === sidebar })
    }

    @Test("the native sidebar action preserves the window and hosted content through repeated toggles")
    func sidebarDoesNotReplaceContentOrResizeWindow() throws {
        let chrome = WorkspaceChromeController()
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        chrome.attach(to: window, splitController: root)
        let sidebar = try #require(root.splitViewItems.first)
        #expect(sidebar.minimumThickness == 200)
        #expect(sidebar.maximumThickness == 200)
        #expect(!sidebar.canCollapseFromWindowResize)
        let host = root.contentHost
        let frame = window.frame
        let item = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.sidebarID })
        let action = try #require(item.action)

        for _ in 0..<2 {
            #expect(NSApp.sendAction(action, to: item.target, from: item))
            #expect(sidebar.isCollapsed)
            #expect(root.contentHost === host)
            #expect(window.frame == frame)
            #expect(NSApp.sendAction(action, to: item.target, from: item))
            #expect(!sidebar.isCollapsed)
            #expect(root.contentHost === host)
            #expect(window.frame == frame)
        }
    }

    @Test("nested column focus still routes the sidebar action to the navigation sidebar")
    func innerColumnsForwardSidebarAction() throws {
        let chrome = WorkspaceChromeController()
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        chrome.attach(to: window, splitController: root)
        let detail = makeDetail(chrome: chrome)
        chrome.setDetailSplit(detail.splitView)
        let sidebar = try #require(root.splitViewItems.first)

        detail.toggleSidebar(nil)
        #expect(sidebar.isCollapsed)
        #expect(detail.splitViewItems.allSatisfy { !$0.isCollapsed })
        detail.toggleSidebar(nil)
        #expect(!sidebar.isCollapsed)
    }

    @Test("global run controls retain priority when the page changes between two and three columns")
    func runControlsRemainAvailableAcrossColumnChanges() throws {
        let chrome = WorkspaceChromeController()
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        chrome.attach(to: window, splitController: root)
        chrome.setRunControls(AnyView(Text("安全停止")), visible: true)
        let run = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.runID })
        #expect(run.visibilityPriority == .user)
        let detail = makeDetail(chrome: chrome)
        chrome.setDetailSplit(detail.splitView)
        chrome.removeDetailSplit(detail.splitView)
        #expect(chrome.toolbar.items.last === run)

        chrome.setRunControls(AnyView(EmptyView()), visible: false)
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.runID })
        #expect(window.toolbar === chrome.toolbar)
    }

    @Test("separate workspace lifetimes do not synchronize toolbar columns or controls")
    func workspaceToolbarsRemainIndependent() throws {
        let first = WorkspaceChromeController()
        let second = WorkspaceChromeController()
        let (firstWindow, firstRoot) = makeWindow(chrome: first)
        let (secondWindow, secondRoot) = makeWindow(chrome: second)
        defer {
            firstWindow.contentViewController = nil
            secondWindow.contentViewController = nil
        }
        first.attach(to: firstWindow, splitController: firstRoot)
        second.attach(to: secondWindow, splitController: secondRoot)
        let firstDetail = makeDetail(chrome: first)
        let secondDetail = makeDetail(chrome: second)
        first.setDetailSplit(firstDetail.splitView)
        first.setRunControls(AnyView(Text("安全停止")), visible: true)
        let firstItems = first.toolbar.items

        second.setDetailSplit(secondDetail.splitView)
        second.removeDetailSplit(secondDetail.splitView)
        #expect(first.toolbar.items.count == firstItems.count)
        #expect(zip(first.toolbar.items, firstItems).allSatisfy { $0 === $1 })
        let tracking = try #require(first.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.detailDividerID }
            as? NSTrackingSeparatorToolbarItem)
        #expect(tracking.splitView === firstDetail.splitView)
        #expect(firstWindow.toolbar === first.toolbar)
        #expect(secondWindow.toolbar === second.toolbar)
    }

    @Test("a replacement page action stays at the leading edge before and after its toolbar slot shrinks")
    func pageActionKeepsItsLeadingAnchorAcrossHostingResize() throws {
        let chrome = WorkspaceChromeController()
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        let geometry = ToolbarIconGeometry()
        chrome.setPage(title: "演示方案", actions: AnyView(HStack(spacing: 6) {
            measuredAction("安排", symbol: "calendar.badge.clock", geometry: geometry)
            measuredAction("更多", symbol: "ellipsis", geometry: geometry)
        }), detail: AnyView(EmptyView()))
        chrome.attach(to: window, splitController: root)
        let item = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.titleID })
        let header = try #require(item.view as? NSStackView)
        let productionHost = try #require(header.arrangedSubviews.compactMap { $0 as? NSHostingView<AnyView> }.first)
        // Hold the previous parent allocation while the replacement reports its new ideal size.
        let host = NSHostingView(rootView: productionHost.rootView)
        host.sizingOptions = [.intrinsicContentSize]
        let allocationWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                                        styleMask: [], backing: .buffered, defer: false)
        allocationWindow.isReleasedWhenClosed = false
        let allocation = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        allocation.addSubview(host)
        allocationWindow.contentView = allocation
        defer { allocationWindow.contentView = nil; allocationWindow.close() }
        let previousSize = host.fittingSize
        host.setFrameSize(previousSize)
        host.layoutSubtreeIfNeeded()

        chrome.setPage(title: "客户端与账号", actions: AnyView(
            measuredAction("添加客户端", symbol: "plus", geometry: geometry)
        ), detail: AnyView(EmptyView()))
        host.rootView = productionHost.rootView
        host.setFrameSize(previousSize)
        host.layoutSubtreeIfNeeded()
        let icon = try #require(geometry.views["添加客户端"]?.last { $0.isDescendant(of: host) })
        let beforeResize = icon.convert(icon.bounds, to: host)
        let replacementSize = host.fittingSize
        #expect(host.frame.size == previousSize)
        #expect(replacementSize.width < previousSize.width)
        #expect(replacementSize.width.isFinite)
        #expect(abs(replacementSize.width - beforeResize.width) < 0.5)
        #expect(abs(beforeResize.minX) < 0.5)

        host.setFrameSize(replacementSize)
        host.layoutSubtreeIfNeeded()
        let afterResize = icon.convert(icon.bounds, to: host)
        #expect(abs(afterResize.minX - beforeResize.minX) < 0.5)
        #expect(abs(afterResize.width - beforeResize.width) < 0.5)
    }

    @Test("a page header adopts its final title and action positions synchronously when growing or shrinking", arguments: [false, true])
    func pageHeaderSettlesBeforeParentLayout(growing: Bool) throws {
        _ = NSApplication.shared
        let chrome = WorkspaceChromeController()
        let geometry = ToolbarIconGeometry()
        let previousActions = growing ? AnyView(EmptyView()) : AnyView(HStack(spacing: 6) {
            measuredAction("安排", symbol: "calendar.badge.clock", geometry: geometry)
            measuredAction("更多", symbol: "ellipsis", geometry: geometry)
        })
        chrome.setPage(title: growing ? "概览" : "足够长以触发中列标题截断的日常方案名称",
                       actions: previousActions, detail: AnyView(EmptyView()))
        let detail = makeDetail(chrome: chrome)
        if !growing { chrome.setDetailSplit(detail.splitView) }
        let item = try #require(chrome.toolbar(chrome.toolbar,
            itemForItemIdentifier: WorkspaceChromeController.titleID, willBeInsertedIntoToolbar: false))
        let header = try #require(item.view as? NSStackView)
        let title = try #require(header.arrangedSubviews.compactMap { $0 as? NSTextField }.first)
        // Keep the owned header at a stable native origin without an unshown toolbar's installation layout.
        let allocationWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                                        styleMask: [], backing: .buffered, defer: false)
        allocationWindow.isReleasedWhenClosed = false
        let allocation = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        allocation.addSubview(header)
        allocationWindow.contentView = allocation
        defer { allocationWindow.contentView = nil; allocationWindow.close() }
        header.frame = NSRect(origin: NSPoint(x: 20, y: 20), size: header.fittingSize)
        header.layoutSubtreeIfNeeded()
        let previousSize = header.frame.size

        chrome.setPage(title: "客户端与账号", actions: AnyView(
            measuredAction("添加客户端", symbol: "plus", geometry: geometry)
        ), detail: AnyView(EmptyView()))
        let icon = try #require(geometry.views["添加客户端"]?.last { $0.isDescendant(of: header) })
        let immediateTitle = title.convert(title.bounds, to: nil)
        let immediateIcon = icon.convert(icon.bounds, to: nil)
        let replacementSize = header.fittingSize
        #expect(growing ? replacementSize.width > previousSize.width : replacementSize.width < previousSize.width)
        #expect(abs(header.frame.width - replacementSize.width) < 0.5)
        #expect(immediateIcon.width > 0)

        if !growing { chrome.removeDetailSplit(detail.splitView) }
        header.setFrameSize(replacementSize)
        layoutWindow(allocationWindow)
        let finalTitle = title.convert(title.bounds, to: nil)
        let finalIcon = icon.convert(icon.bounds, to: nil)
        #expect(abs(immediateTitle.minX - finalTitle.minX) < 0.5)
        #expect(abs(immediateTitle.width - finalTitle.width) < 0.5)
        #expect(abs(immediateIcon.minX - finalIcon.minX) < 0.5)
        #expect(abs(immediateIcon.width - finalIcon.width) < 0.5)
    }

    private func layoutWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.superview?.layoutSubtreeIfNeeded()
    }

    private func measuredAction(_ title: String, symbol: String, geometry: ToolbarIconGeometry) -> some View {
        Button {} label: { Label(title, systemImage: symbol) }
            .background(ToolbarIconGeometryMarker(title: title, geometry: geometry))
    }

    private func makeWindow(chrome: WorkspaceChromeController) -> (NSWindow, WorkspaceSplitController) {
        _ = NSApplication.shared
        let root = WorkspaceSplitController(chrome: chrome,
            sidebar: AnyView(Text("导航").frame(maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)),
            content: AnyView(Text("正文").frame(minWidth: 680, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.contentMinSize = NSSize(width: 1020, height: 680)
        window.contentViewController = root
        window.setContentSize(NSSize(width: 1180, height: 780))
        root.view.layoutSubtreeIfNeeded()
        return (window, root)
    }

    private func makeDetail(chrome: WorkspaceChromeController) -> WorkspaceDetailSplitController {
        WorkspaceDetailSplitController(chrome: chrome, content: AnyView(Text("列表")), detail: AnyView(Text("详情")))
    }
}

@MainActor
private final class ToolbarIconGeometry {
    var views: [String: [NSView]] = [:]
}

private struct ToolbarIconGeometryMarker: NSViewRepresentable {
    let title: String
    let geometry: ToolbarIconGeometry

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        if geometry.views[title]?.contains(where: { $0 === view }) != true {
            geometry.views[title, default: []].append(view)
        }
    }
}
