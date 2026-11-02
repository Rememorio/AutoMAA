import AppKit
import AutoMAAKit
import SwiftUI
import Testing
@testable import AutoMAA

@MainActor
@Suite("Workspace window chrome")
struct WorkspaceChromeTests {
    @Test("the first page and subsequent navigation keep an accessible window title")
    func pageTitlesSurviveAttachment() {
        let chrome = WorkspaceChromeController()
        chrome.setPage(title: "演示方案", actions: [])
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }

        chrome.attach(to: window, splitController: root)
        let frame = window.frame
        #expect(window.title == "演示方案")
        #expect(window.titleVisibility == .hidden)
        #expect(window.toolbar === chrome.toolbar)

        chrome.setPage(title: "运行记录", actions: [])
        #expect(window.title == "运行记录")
        #expect(window.toolbar === chrome.toolbar)
        #expect(window.frame == frame)
    }

    @Test("workspace content stays below the native toolbar when a full-height window is reattached")
    func fullHeightContentDoesNotOverlapToolbar() throws {
        let chrome = WorkspaceChromeController()
        let fixture = makeModel()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        chrome.setPage(title: "客户端与账号", actions: [
            .init(id: "add-client", title: "添加客户端", symbol: "plus")
        ])
        chrome.setRunControls(model: fixture.model)
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        chrome.attach(to: window, splitController: root)
        layoutWindow(window)
        let frame = window.frame
        let title = window.title
        let items = chrome.toolbar.items
        let addFrame = try actionFrame("添加客户端", in: window)
        let stopFrame = try actionFrame("安全停止", in: window)
        let playFrame = try actionFrame("运行方案", in: window)

        window.styleMask.insert(.fullSizeContentView)
        layoutWindow(window)
        let content = try #require(window.contentView)
        let overlapping = content.convert(content.bounds, to: nil)
        #expect(overlapping.maxY > window.contentLayoutRect.maxY + 0.5)

        chrome.attach(to: window, splitController: root)
        layoutWindow(window)
        let bounded = content.convert(content.bounds, to: nil)
        #expect(bounded.maxY <= window.contentLayoutRect.maxY + 0.5)
        #expect(bounded.minY >= window.contentLayoutRect.minY - 0.5)
        #expect(bounded.height > 0)
        #expect(window.contentLayoutRect.maxY < window.frame.height)
        #expect(window.frame == frame)
        #expect(window.title == title)
        #expect(window.toolbar === chrome.toolbar)
        #expect(zip(chrome.toolbar.items, items).allSatisfy { $0 === $1 })
        #expect(chrome.toolbar.items.count == items.count)
        #expect(try actionFrame("添加客户端", in: window) == addFrame)
        #expect(try actionFrame("安全停止", in: window) == stopFrame)
        #expect(try actionFrame("运行方案", in: window) == playFrame)
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

    @Test("plan run controls preserve identity across navigation while unrelated idle pages omit them")
    func runControlsRemainAvailableAcrossColumnChanges() throws {
        let chrome = WorkspaceChromeController()
        chrome.setPage(title: "演示方案", actions: [.init(id: "arrange", title: "执行安排", symbol: "calendar.badge.clock")])
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        chrome.attach(to: window, splitController: root)
        let fixture = makeModel()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        chrome.setRunControls(model: fixture.model)
        let run = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.runID })
        #expect(run.visibilityPriority == .user)
        let detail = makeDetail(chrome: chrome)
        let planID = try #require(fixture.model.configuration.plans.first?.id)
        for _ in 0..<3 {
            fixture.model.selection = .plan(planID)
            chrome.setRunControls(model: fixture.model)
            chrome.setDetailSplit(detail.splitView)
            #expect(chrome.toolbar.items.filter { $0.itemIdentifier == .flexibleSpace }.count == 2)
            #expect(chrome.toolbar.items.map(\.itemIdentifier) == chrome.itemIdentifiers)
            fixture.model.selection = .overview
            chrome.setRunControls(model: fixture.model)
            chrome.removeDetailSplit(detail.splitView)
            #expect(chrome.toolbar.items.filter { $0.itemIdentifier == .flexibleSpace }.count == 1)
            #expect(chrome.toolbar.items.map(\.itemIdentifier) == chrome.itemIdentifiers)
        }
        #expect(!chrome.toolbar.items.contains { $0 === run })
        #expect(chrome.toolbar.items.last?.itemIdentifier == .flexibleSpace)

        fixture.model.selection = .clients
        chrome.setRunControls(model: fixture.model)
        #expect(!chrome.toolbar.items.contains { $0 === run })
        fixture.model.selection = .plan(planID)
        chrome.setRunControls(model: fixture.model)
        #expect(chrome.toolbar.items.contains { $0 === run })
        #expect(run.visibilityPriority == .user)
        #expect(window.toolbar === chrome.toolbar)
    }

    @Test("native actions hug their real column boundary while run and mode groups start the detail column",
           arguments: [false, true])
    func nativeActionsAlignWithNestedColumns(threeColumns: Bool) throws {
        let chrome = WorkspaceChromeController()
        let fixture = makeModel()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let (window, root, detail) = makeNestedWindow(chrome: chrome, threeColumns: threeColumns)
        defer { window.contentViewController = nil }
        if !threeColumns { fixture.model.selection = .overview }
        chrome.setRunControls(model: fixture.model)
        chrome.attach(to: window, splitController: root)
        if let detail { chrome.setDetailSplit(detail.splitView) }
        let modes = WorkspaceToolbarModes(options: [
            .init(title: "任务设置", symbol: "slider.horizontal.3", help: "调整参数"),
            .init(title: "运行概况", symbol: "checklist", help: "查看运行概况")
        ], selectedIndex: 0, select: { _ in })
        let actionSets: [[WorkspaceToolbarAction]] = threeColumns ? [
            [.init(id: "arrange", title: "执行安排", symbol: "calendar.badge.clock"),
             .init(id: "more", title: "方案操作", symbol: "ellipsis", menu: [.action("菜单操作", handler: {})])],
            [.init(id: "records", title: "记录操作", symbol: "ellipsis", menu: [.action("菜单操作", handler: {})])]
        ] : [[.init(id: "add-client", title: "添加客户端", symbol: "plus")]]
        let sidebar = try #require(root.splitViewItems.first)
        for width in [1020.0, 1180.0, 1400.0] {
            window.setContentSize(NSSize(width: width, height: 780))
            for collapsed in [false, true] {
                sidebar.isCollapsed = collapsed
                chrome.sidebarVisibilityDidChange()
                for middleWidth in (threeColumns ? [240.0, 280.0, 320.0] : [0.0]) {
                    layoutWindow(window)
                    detail?.splitView.setPosition(middleWidth, ofDividerAt: 0)
                    for actions in actionSets {
                        chrome.setPage(title: "日常方案", actions: actions, modes: threeColumns ? modes : nil)
                        layoutWindow(window)
                        let context = "width=\(width), collapsed=\(collapsed), middle=\(middleWidth), actions=\(actions.count)"
                        #expect(chrome.toolbar.items.map(\.itemIdentifier) == chrome.itemIdentifiers, Comment(rawValue: context))
                        let actionFrames = try actions.map { window.convertFromScreen(try actionFrame($0.title, in: window)) }
                        let lastAction = try #require(actionFrames.last)
                        if let detail {
                            let stop = window.convertFromScreen(try actionFrame("安全停止", in: window))
                            let play = window.convertFromScreen(try actionFrame("运行方案", in: window))
                            #expect(stop.maxX <= play.minX, Comment(rawValue: context))
                            #expect(play.maxX < width, Comment(rawValue: context))
                            let middle = try #require(detail.splitViewItems.first?.viewController.view)
                            let divider = detail.splitView.convert(NSPoint(x: middle.frame.maxX + detail.splitView.dividerThickness / 2, y: 0), to: nil).x
                            let leftGap = divider - lastAction.maxX
                            let rightGap = stop.minX - divider
                            #expect(leftGap >= -0.5 && leftGap <= 28, Comment(rawValue: "\(context), action gap=\(leftGap)"))
                            #expect(rightGap >= -0.5 && rightGap <= 28, Comment(rawValue: "\(context), run gap=\(rightGap)"))
                            let settings = window.convertFromScreen(try actionFrame("任务设置", in: window))
                            #expect(settings.minX >= play.maxX - 0.5 && settings.minX - play.maxX <= 28, Comment(rawValue: context))
                            #expect(chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.titleID } == !collapsed)
                        } else {
                            let title = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.titleID }?.view)
                            let titleFrame = title.convert(title.alignmentRect(forFrame: title.bounds), to: nil)
                            let firstAction = try #require(actionFrames.first)
                            #expect(firstAction.minX >= titleFrame.maxX - 0.5 && firstAction.minX - titleFrame.maxX <= 28,
                                    Comment(rawValue: "\(context), action=\(firstAction), title=\(titleFrame)"))
                            #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.runID })
                            #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.stopID })
                        }
                        #expect(window.title == "日常方案")
                    }
                }
            }
        }
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
        let fixture = makeModel()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        first.setRunControls(model: fixture.model)
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

    @Test("native page actions keep their positions and handlers while titles and enablement change")
    func nativePageActionsStayStable() throws {
        let chrome = WorkspaceChromeController()
        let (window, root, nested) = makeNestedWindow(chrome: chrome, threeColumns: true)
        defer { window.contentViewController = nil }
        var actionResult = 0
        chrome.setPage(title: "演示方案", actions: [
            .init(id: "arrange", title: "执行安排", symbol: "calendar.badge.clock", handler: { actionResult = 1 }),
            .init(id: "more", title: "方案操作", symbol: "ellipsis", menu: [
                .action("复制方案", handler: { actionResult = 2 })
            ])
        ])
        chrome.attach(to: window, splitController: root)
        let detail = try #require(nested)
        chrome.setDetailSplit(detail.splitView)
        layoutWindow(window)
        detail.splitView.setPosition(280, ofDividerAt: 0)
        layoutWindow(window)
        let arrange = try #require(chrome.toolbar.items.first { $0.label == "执行安排" })
        let more = try #require(chrome.toolbar.items.first { $0.label == "方案操作" } as? NSMenuToolbarItem)
        let initialArrange = try actionFrame("执行安排", in: window)
        let initialMore = try actionFrame("方案操作", in: window)
        #expect(initialArrange.maxX <= initialMore.minX)
        #expect(arrange.view == nil)
        #expect(arrange.isBordered)
        #expect(more.isBordered)
        #expect(arrange.image != nil)
        #expect(more.image != nil)

        chrome.setPage(title: "足够长以触发中列标题截断的日常方案名称", actions: [
            .init(id: "arrange", title: "执行安排", symbol: "calendar.badge.clock", isEnabled: false,
                  handler: { actionResult = 3 }),
            .init(id: "more", title: "方案操作", symbol: "ellipsis", menu: [
                .action("复制方案", isEnabled: false, handler: { actionResult = 4 })
            ])
        ])
        layoutWindow(window)
        #expect(chrome.toolbar.items.contains { $0 === arrange })
        #expect(chrome.toolbar.items.contains { $0 === more })
        #expect(!arrange.isEnabled)
        #expect(more.menu.items.first?.isEnabled == false)
        chrome.setPage(title: "演示方案", actions: [
            .init(id: "arrange", title: "执行安排", symbol: "calendar.badge.clock", handler: { actionResult = 5 }),
            .init(id: "more", title: "方案操作", symbol: "ellipsis", menu: [
                .action("复制方案", handler: { actionResult = 6 })
            ])
        ])
        layoutWindow(window)
        let finalArrange = try actionFrame("执行安排", in: window)
        #expect(finalArrange == initialArrange)
        let action = try #require(arrange.action)
        let sent = NSApp.sendAction(action, to: arrange.target, from: arrange)
        #expect(sent)
        #expect(actionResult == 5)
        chrome.setPage(title: "另一个页面", actions: [])
        #expect(!chrome.toolbar.items.contains { $0 === more })
    }

    @Test("replacing a column page never clears its tracking item and restores the user's actual column width")
    func replacementColumnsPreserveChromeAndWidth() throws {
        let chrome = WorkspaceChromeController()
        let fixture = makeModel()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let (window, root, nested) = makeNestedWindow(chrome: chrome, threeColumns: true)
        defer { window.contentViewController = nil }
        chrome.setRunControls(model: fixture.model)
        let actions = [WorkspaceToolbarAction(id: "arrange", title: "执行安排", symbol: "calendar.badge.clock")]
        let options = [WorkspaceToolbarMode(title: "任务设置", symbol: "slider.horizontal.3", help: "调整参数")]
        chrome.setPage(title: "第一个方案", actions: actions,
                       modes: .init(options: options, selectedIndex: 0, select: { _ in }))
        chrome.attach(to: window, splitController: root)
        let previous = try #require(nested)
        previous.viewDidLayout()
        chrome.setDetailSplit(previous.splitView)
        previous.splitView.setPosition(320, ofDividerAt: 0)
        layoutWindow(window)
        #expect(abs(chrome.middleColumnWidth - 320) < 0.5)
        let ids = chrome.toolbar.items.map(\.itemIdentifier)
        let tracking = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.detailDividerID }
            as? NSTrackingSeparatorToolbarItem)
        let arrange = try #require(chrome.toolbar.items.first { $0.label == "执行安排" })
        let image = try #require(arrange.image)
        let initialAction = try actionFrame("执行安排", in: window)
        let initialRun = try actionFrame("安全停止", in: window)
        let frame = window.frame

        var next = AutomationPlan(name: "另一个足够长的方案名称")
        next.id = UUID()
        fixture.model.configuration.plans.append(next)
        fixture.model.selection = .plan(next.id)
        chrome.setRunControls(model: fixture.model)
        chrome.removeDetailSplit(previous.splitView)
        #expect(chrome.detailSplit === previous.splitView)
        #expect(chrome.toolbar.items.map(\.itemIdentifier) == ids)
        chrome.setPage(title: next.name, actions: actions,
                       modes: .init(options: options, selectedIndex: 0, select: { _ in }))
        #expect(chrome.toolbar.items.map(\.itemIdentifier) == ids)
        #expect(arrange.image === image)
        #expect(try actionFrame("执行安排", in: window) == initialAction)
        #expect(try actionFrame("安全停止", in: window) == initialRun)

        root.removeSplitViewItem(root.splitViewItems[1])
        let replacement = makeDetail(chrome: chrome)
        let item = NSSplitViewItem(viewController: replacement)
        item.minimumThickness = 680
        root.addSplitViewItem(item)
        layoutWindow(window)
        replacement.viewDidLayout()
        layoutWindow(window)
        #expect(chrome.detailSplit === replacement.splitView)
        #expect(tracking.splitView === replacement.splitView)
        #expect(abs(replacement.splitView.subviews[0].frame.width - 320) < 0.5)
        #expect(chrome.toolbar.items.map(\.itemIdentifier) == ids)
        #expect(chrome.toolbar.items.contains { $0 === tracking })
        #expect(try actionFrame("执行安排", in: window) == initialAction)
        #expect(try actionFrame("安全停止", in: window) == initialRun)
        #expect(window.frame == frame)

        fixture.model.selection = .overview
        chrome.setRunControls(model: fixture.model)
        chrome.removeDetailSplit(replacement.splitView)
        #expect(chrome.detailSplit == nil)
        #expect(!chrome.toolbar.items.contains { $0 === tracking })
        chrome.setDetailSplit(replacement.splitView)
        #expect(chrome.detailSplit == nil)
        fixture.model.selection = .plan(UUID())
        chrome.setRunControls(model: fixture.model)
        chrome.setDetailSplit(replacement.splitView)
        #expect(chrome.detailSplit == nil)
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.runID })
    }

    @Test("native detail modes keep their icons and selection while sending the current navigation action")
    func nativeModesPreserveSelectionAndRouting() throws {
        let chrome = WorkspaceChromeController()
        let (window, root) = makeWindow(chrome: chrome)
        defer { window.contentViewController = nil }
        var selected = -1
        let options = [
            WorkspaceToolbarMode(title: "任务设置", symbol: "slider.horizontal.3", help: "调整所选任务的参数"),
            WorkspaceToolbarMode(title: "运行概况", symbol: "checklist", help: "查看本方案运行概况")
        ]
        chrome.setPage(title: "演示方案", actions: [],
                       modes: .init(options: options, selectedIndex: 0, select: { selected = $0 }))
        chrome.attach(to: window, splitController: root)
        let detail = makeDetail(chrome: chrome)
        chrome.setDetailSplit(detail.splitView)
        let group = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.detailID }
            as? NSToolbarItemGroup)
        #expect(group.isBordered)
        #expect(group.subitems.map(\.label) == ["任务设置", "运行概况"])
        let images = try group.subitems.map { try #require($0.image) }
        #expect(group.subitems.map(\.toolTip) == options.map { Optional($0.help) })
        #expect(group.selectedIndex == 0)
        group.selectedIndex = 1
        let action = try #require(group.action)
        let firstSent = NSApp.sendAction(action, to: group.target, from: group)
        #expect(firstSent)
        #expect(selected == 1)

        chrome.setPage(title: "另一个方案", actions: [],
                       modes: .init(options: options, selectedIndex: 1, select: { selected = $0 + 10 }))
        #expect(chrome.toolbar.items.contains { $0 === group })
        #expect(group.selectedIndex == 1)
        group.selectedIndex = 0
        let secondSent = NSApp.sendAction(action, to: group.target, from: group)
        #expect(secondSent)
        #expect(selected == 10)
        #expect(zip(group.subitems, images).allSatisfy { $0.image === $1 })
    }

    @Test("client detail actions keep their native positions when background stop appears and selection changes")
    func detailActionsRemainStableDuringBackgroundActivity() throws {
        let chrome = WorkspaceChromeController()
        let fixture = makeModel()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.model.selection = .clients
        let (window, root, nested) = makeNestedWindow(chrome: chrome, threeColumns: true)
        defer { window.contentViewController = nil }
        chrome.setRunControls(model: fixture.model)
        var edited = 0
        let add = WorkspaceToolbarAction(id: "add", title: "添加客户端", symbol: "plus")
        chrome.setPage(title: "客户端与账号", actions: [add], detailActions: [
            .init(id: "edit", title: "编辑客户端", symbol: "pencil", handler: { edited = 1 }),
            .init(id: "more", title: "更多操作", symbol: "ellipsis", menu: [.action("菜单操作", handler: {})])
        ])
        chrome.attach(to: window, splitController: root)
        let detail = try #require(nested)
        detail.viewDidLayout()
        chrome.setDetailSplit(detail.splitView)
        layoutWindow(window)
        let item = try #require(chrome.toolbar.items.first { $0.label == "编辑客户端" })
        let image = try #require(item.image)
        let editFrame = try actionFrame("编辑客户端", in: window)
        let moreFrame = try actionFrame("更多操作", in: window)
        let frame = window.frame
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.runID })
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.stopID })

        var lock: ProcessLock? = try ProcessLock(url: fixture.model.directories.lock)
        let identity = WorkflowRunIdentity(runID: UUID(), planID: try #require(fixture.model.configuration.plans.first?.id),
                                          lockID: try #require(lock).identity)
        let control = WorkflowRunControl(directories: fixture.model.directories)
        try control.activate(identity)
        defer { control.finish(identity); lock = nil }
        HistoryStore(directories: fixture.model.directories).append(.init(level: .info, message: "正在处理任务",
            runID: identity.runID, phase: .runningTask, planID: identity.planID))
        fixture.model.reloadActivityHistory()
        chrome.setRunControls(model: fixture.model)
        layoutWindow(window)
        #expect(chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.stopID })
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.runID })
        #expect(try actionFrame("编辑客户端", in: window) == editFrame)
        let activeMoreFrame = try actionFrame("更多操作", in: window)
        #expect(activeMoreFrame == moreFrame)

        control.finish(identity)
        lock = nil
        fixture.model.reloadActivityHistory()
        chrome.setRunControls(model: fixture.model)
        chrome.setPage(title: "客户端与账号", actions: [add], detailActions: [
            .init(id: "edit", title: "编辑账号", symbol: "pencil", handler: { edited = 2 }),
            .init(id: "more", title: "更多操作", symbol: "ellipsis", menu: [.action("账号菜单", handler: {})])
        ])
        layoutWindow(window)
        #expect(item.image === image)
        #expect(try actionFrame("编辑账号", in: window) == editFrame)
        #expect(try actionFrame("更多操作", in: window) == moreFrame)
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.stopID })
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(edited == 2)
        #expect(window.frame == frame)
    }

    private func layoutWindow(_ window: NSWindow) {
        window.contentView?.superview?.layoutSubtreeIfNeeded()
    }

    private func actionFrame(_ label: String, in element: any NSAccessibilityProtocol) throws -> NSRect {
        try #require(actionElement(label, in: element)).accessibilityFrame()
    }

    private func actionElement(_ label: String, in element: any NSAccessibilityProtocol) -> (any NSAccessibilityProtocol)? {
        if element.accessibilityLabel() == label {
            let frame = element.accessibilityFrame()
            if frame.width > 0, frame.height > 0 { return element }
        }
        for child in element.accessibilityChildren() ?? [] {
            if let child = child as? any NSAccessibilityProtocol,
               let match = actionElement(label, in: child) { return match }
        }
        return nil
    }

    private func makeModel() -> (root: URL, model: AppModel) {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-native-toolbar-\(UUID())")
        let model = AppModel(directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents"), managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false, allowsAutomaticMAAMaintenance: false,
            runnerExecutableURL: URL(filePath: "/usr/bin/true"))
        let plan = AutomationPlan(name: "演示方案")
        model.configuration.plans = [plan]
        model.selection = .plan(plan.id)
        return (root, model)
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

    private func makeNestedWindow(chrome: WorkspaceChromeController, threeColumns: Bool)
        -> (NSWindow, WorkspaceSplitController, WorkspaceDetailSplitController?) {
        let (window, root) = makeWindow(chrome: chrome)
        guard threeColumns else { return (window, root, nil) }
        let detail = makeDetail(chrome: chrome)
        root.removeSplitViewItem(root.splitViewItems[1])
        let content = NSSplitViewItem(viewController: detail)
        content.minimumThickness = 680
        root.addSplitViewItem(content)
        layoutWindow(window)
        return (window, root, detail)
    }

    private func makeDetail(chrome: WorkspaceChromeController) -> WorkspaceDetailSplitController {
        WorkspaceDetailSplitController(chrome: chrome, content: AnyView(Text("列表")), detail: AnyView(Text("详情")))
    }
}
