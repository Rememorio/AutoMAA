import AppKit
import AutoMAAKit
import SwiftUI
import Testing
@testable import AutoMAA

@MainActor
@Suite("Workspace run controls")
struct WorkspaceRunControlsTests {
    @Test("plan playback starts a round and pending playback resumes only the current round")
    func continuationHelpMatchesAcrossPages() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        model.configuration.plans[0].award.enabled = true
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        let round = state.startRound(for: fixture.plan.id, at: Date())
        state.record(.init(status: .unconfirmed, reason: .interruptedBattle), for: fixture.step.key)
        try ExecutionStateStore(directories: model.directories).save(state)
        model.reloadActivityHistory()
        model.selection = .plan(fixture.plan.id)
        let settings = WorkspaceRunControlState(model: model)
        model.selection = .activity
        model.activitySelection = .plan(fixture.plan.id)
        let today = WorkspaceRunControlState(model: model)
        #expect(settings.canStart)
        #expect(today.canStart)
        if case .run(fixture.plan.id) = settings.startAction {} else { Issue.record("Expected a new round") }
        if case .resume(fixture.plan.id, round.id) = today.startAction {} else { Issue.record("Expected the current round") }
        #expect(settings.startHelp.contains("开启新一轮"))
        #expect(today.startHelp.contains(fixture.plan.name))
        #expect(today.startHelp.contains("1 项待办"))
        #expect(today.startHelp.contains("1 项待核实"))
    }

    @Test("native stop and play retain their icons and actual positions through running, cancelling and completion")
    func completionDoesNotMoveTheRunControls() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let (window, chrome, group) = try makeHost(model)
        defer { window.contentViewController = nil }
        let initialFrames = try frames(window)
        let images = try group.subitems.map { try #require($0.image) }
        let windowFrame = window.frame
        let stop = try #require(group.subitems.first)
        let play = try #require(group.subitems.last)
        #expect(group.subitems.count == 2)
        #expect(!stop.isEnabled)
        #expect(play.isEnabled)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)

        var other = fixture.plan
        other.id = UUID()
        other.name = "当前正在查看的另一个名称很长的方案"
        model.configuration.plans.append(other)
        model.selection = .plan(other.id)
        var lock: ProcessLock? = try ProcessLock(url: model.directories.lock)
        let identity = WorkflowRunIdentity(runID: UUID(), planID: fixture.plan.id,
                                          lockID: try #require(lock).identity)
        let control = WorkflowRunControl(directories: model.directories)
        try control.activate(identity)
        defer { control.finish(identity); lock = nil }
        for progress in [0.0, 0.5, 1.0] {
            HistoryStore(directories: model.directories).append(.init(level: .info, message: "正在处理任务",
                runID: identity.runID, phase: .runningTask, progress: progress, planID: fixture.plan.id))
            model.reloadActivityHistory()
            refresh(chrome, model: model, window: window)
            #expect(stop.isEnabled)
            #expect(!play.isEnabled)
            #expect(stop.toolTip?.contains(fixture.plan.name) == true)
            try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
        }

        group.selectedIndex = 0
        let action = try #require(group.action)
        let sent = NSApp.sendAction(action, to: group.target, from: group)
        #expect(sent)
        #expect(control.isStopRequested(for: identity))
        #expect(model.isCancellingRun)
        refresh(chrome, model: model, window: window)
        #expect(!stop.isEnabled)
        #expect(!play.isEnabled)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)

        control.finish(identity)
        lock = nil
        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(.init(status: .completed, stage: "1-7", times: 1), for: fixture.step.key)
        try ExecutionStateStore(directories: model.directories).save(state)
        model.selection = .plan(fixture.plan.id)
        model.reloadActivityHistory()
        refresh(chrome, model: model, window: window)
        #expect(model.continuation(for: fixture.plan.id).pending == 0)
        #expect(!stop.isEnabled)
        #expect(play.isEnabled)
        #expect(play.toolTip?.contains("开启新一轮") == true)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
        #expect(window.frame == windowFrame)
    }

    @Test("attention and configuration errors keep native play while unrelated idle pages omit run controls")
    func attentionAndMissingContextDoNotReplaceButtons() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let (window, chrome, group) = try makeHost(model)
        defer { window.contentViewController = nil }
        let initialFrames = try frames(window)
        let images = try group.subitems.map { try #require($0.image) }
        let stop = try #require(group.subitems.first)
        let play = try #require(group.subitems.last)
        let action = try #require(group.action)

        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(.init(status: .unconfirmed, reason: .interruptedBattle), for: fixture.step.key)
        try ExecutionStateStore(directories: model.directories).save(state)
        model.reloadActivityHistory()
        refresh(chrome, model: model, window: window)
        #expect(model.continuation(for: fixture.plan.id).unconfirmed == 1)
        #expect(play.isEnabled)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
        group.selectedIndex = 1
        let firstSent = NSApp.sendAction(action, to: group.target, from: group)
        #expect(firstSent)
        #expect(model.activitySelection == .plan(fixture.plan.id))
        refresh(chrome, model: model, window: window)
        #expect(chrome.toolbar.items.contains { $0 === group })
        #expect(!play.isEnabled)
        #expect(play.toolTip?.contains("核实") == true)

        model.selection = .plan(fixture.plan.id)
        model.configuration.cliPath = fixture.root.appending(path: "missing-maa").path
        #expect(model.planRunState(planID: fixture.plan.id) == .configurationIncomplete)
        refresh(chrome, model: model, window: window)
        #expect(play.isEnabled)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
        group.selectedIndex = 1
        let secondSent = NSApp.sendAction(action, to: group.target, from: group)
        #expect(secondSent)
        #expect(model.readinessRequest?.id == fixture.plan.id)

        model.activitySelection = .session("historical-record")
        for selection: SidebarSelection in [.overview, .clients, .activity] {
            model.selection = selection
            refresh(chrome, model: model, window: window)
            #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.runID })
            #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.stopID })
        }
        model.selection = .plan(fixture.plan.id)
        refresh(chrome, model: model, window: window)
        #expect(chrome.toolbar.items.contains { $0 === group })
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
        #expect(!model.isWorkflowRunning)
    }

    @Test("unrelated pages show only a stop control during real activity without moving their own actions")
    func unrelatedPagesUseAnIndependentStopControl() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let (window, chrome, group) = try makeHost(model)
        defer { window.contentViewController = nil }
        model.selection = .clients
        chrome.setPage(title: "客户端与账号", actions: [.init(id: "add", title: "添加客户端", symbol: "plus")])
        refresh(chrome, model: model, window: window)
        let add = try #require(actionElement("添加客户端", in: window))
        let initial = add.accessibilityFrame()
        #expect(!chrome.toolbar.items.contains { $0 === group })
        #expect(!chrome.toolbar.items.contains { $0.itemIdentifier == WorkspaceChromeController.stopID })

        var lock: ProcessLock? = try ProcessLock(url: model.directories.lock)
        let identity = WorkflowRunIdentity(runID: UUID(), planID: fixture.plan.id,
                                          lockID: try #require(lock).identity)
        let control = WorkflowRunControl(directories: model.directories)
        try control.activate(identity)
        defer { control.finish(identity); lock = nil }
        HistoryStore(directories: model.directories).append(.init(level: .info, message: "正在处理任务",
            runID: identity.runID, phase: .runningTask, planID: fixture.plan.id))
        model.reloadActivityHistory()
        refresh(chrome, model: model, window: window)
        let stop = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.stopID })
        let image = try #require(stop.image)
        let stopFrame = try #require(actionElement("安全停止", in: window)).accessibilityFrame()
        #expect(stop.isEnabled)
        #expect(stop.toolTip?.contains(fixture.plan.name) == true)
        #expect(!chrome.toolbar.items.contains { $0 === group })
        model.selection = .activity
        model.activitySelection = .plan(fixture.plan.id)
        refresh(chrome, model: model, window: window)
        #expect(!chrome.toolbar.items.contains { $0 === stop })
        #expect(chrome.toolbar.items.contains { $0 === group })
        #expect(group.subitems.first?.isEnabled == true)
        #expect(group.subitems.last?.isEnabled == false)

        model.activitySelection = .session("historical-record")
        refresh(chrome, model: model, window: window)
        #expect(chrome.toolbar.items.contains { $0 === stop })
        #expect(!chrome.toolbar.items.contains { $0 === group })
        model.selection = .clients
        refresh(chrome, model: model, window: window)
        #expect(add.accessibilityFrame() == initial)
        #expect(!chrome.toolbar.items.contains { $0.label == "运行方案" })

        let action = try #require(stop.action)
        #expect(NSApp.sendAction(action, to: stop.target, from: stop))
        #expect(control.isStopRequested(for: identity))
        refresh(chrome, model: model, window: window)
        #expect(chrome.toolbar.items.contains { $0 === stop })
        #expect(stop.image === image)
        #expect(!stop.isEnabled)
        #expect(try #require(actionElement("安全停止", in: window)).accessibilityFrame() == stopFrame)
        #expect(add.accessibilityFrame() == initial)

        control.finish(identity)
        lock = nil
        model.reloadActivityHistory()
        refresh(chrome, model: model, window: window)
        #expect(!chrome.toolbar.items.contains { $0 === stop })
        #expect(add.accessibilityFrame() == initial)
    }

    @Test("history puts the active stop before the log switcher and omits play")
    func historyStopPrecedesLogModes() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let lock = try ProcessLock(url: model.directories.lock)
        defer { withExtendedLifetime(lock) {} }
        model.reloadActivityHistory()
        model.selection = .activity
        model.activitySelection = .session("historical-record")

        let chrome = WorkspaceChromeController()
        chrome.setRunControls(model: model)
        let detail = WorkspaceDetailSplitController(chrome: chrome, content: AnyView(Text("记录")), detail: AnyView(Text("日志")))
        chrome.setDetailSplit(detail.splitView)
        chrome.setPage(title: "运行记录", actions: [], modes: .init(options: [
            .init(title: "运行结果", symbol: "checklist", help: "查看结果"),
            .init(title: "完整日志", symbol: "list.bullet.rectangle", help: "查看日志")
        ], selectedIndex: 1, select: { _ in }))

        let ids = chrome.itemIdentifiers
        let stop = try #require(ids.firstIndex(of: WorkspaceChromeController.stopID))
        let modes = try #require(ids.firstIndex(of: WorkspaceChromeController.detailID))
        #expect(stop < modes)
        #expect(!ids.contains(WorkspaceChromeController.runID))
    }

    @Test("local maintenance and its cancellation preserve the same native stop and play pair")
    func maintenanceUsesTheSameButtons() async throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let (window, chrome, group) = try makeHost(model)
        defer { window.contentViewController = nil }
        let initialFrames = try frames(window)
        let images = try group.subitems.map { try #require($0.image) }
        let stop = try #require(group.subitems.first)
        let play = try #require(group.subitems.last)

        model.hotUpdate()
        #expect(model.isWorkflowRunning)
        #expect(model.activePlanID == nil)
        refresh(chrome, model: model, window: window)
        #expect(stop.isEnabled)
        #expect(!play.isEnabled)
        #expect(stop.toolTip?.contains("取消更新") == true)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
        group.selectedIndex = 0
        let action = try #require(group.action)
        let sent = NSApp.sendAction(action, to: group.target, from: group)
        #expect(sent)
        #expect(model.isCancellingRun)
        refresh(chrome, model: model, window: window)
        #expect(!stop.isEnabled)
        #expect(!play.isEnabled)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)

        // Cancel before yielding so maintenance cannot invoke an executable or resource probe.
        for _ in 0..<500 where model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!model.isWorkflowRunning)
        refresh(chrome, model: model, window: window)
        try expectFixedControls(group, stop: stop, play: play, window: window, frames: initialFrames, images: images)
    }

    private struct Fixture {
        let root: URL
        let model: AppModel
        let plan: AutomationPlan
        let step: WorkflowStep
    }

    private func makeFixture() -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-toolbar-run-\(UUID())")
        let model = AppModel(directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents"), managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false, allowsAutomaticMAAMaintenance: false,
            runnerExecutableURL: URL(filePath: "/usr/bin/true"), resourceProbeExecutable: URL(filePath: "/usr/bin/true"))
        let account = AccountConfiguration(name: "演示账号")
        let client = ClientConfiguration(name: "演示客户端", kind: .yoStarJP,
            appPath: root.appending(path: "Fixture.app").path, address: "127.0.0.1:61394",
            profileName: "toolbar-fixture", bundleIdentifier: "dev.automaa.tests.toolbar", accounts: [account])
        var plan = AutomationPlan.lightRoutine
        plan.name = "演示日常"
        plan.fight.enabled = true
        plan.recruit.enabled = false
        plan.infrast.enabled = false
        plan.mall.enabled = false
        plan.award.enabled = false
        model.configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        model.selection = .plan(plan.id)
        return Fixture(root: root, model: model, plan: plan,
            step: WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight))
    }

    private func makeHost(_ model: AppModel) throws -> (NSWindow, WorkspaceChromeController, NSToolbarItemGroup) {
        _ = NSApplication.shared
        let chrome = WorkspaceChromeController()
        let root = WorkspaceSplitController(chrome: chrome,
            sidebar: AnyView(Text("导航").frame(maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)),
            content: AnyView(Text("正文").frame(minWidth: 680, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)))
        chrome.setPage(title: "演示日常", actions: [])
        chrome.setRunControls(model: model)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.contentViewController = root
        chrome.attach(to: window, splitController: root)
        refresh(chrome, model: model, window: window)
        let group = try #require(chrome.toolbar.items.first { $0.itemIdentifier == WorkspaceChromeController.runID }
            as? NSToolbarItemGroup)
        return (window, chrome, group)
    }

    private func refresh(_ chrome: WorkspaceChromeController, model: AppModel, window: NSWindow) {
        chrome.setRunControls(model: model)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
    }

    private func expectFixedControls(_ group: NSToolbarItemGroup, stop: NSToolbarItem, play: NSToolbarItem,
                                     window: NSWindow, frames initial: [NSRect], images: [NSImage]) throws {
        #expect(group.subitems.count == 2)
        #expect(group.subitems[0] === stop)
        #expect(group.subitems[1] === play)
        #expect(stop.image === images[0])
        #expect(play.image === images[1])
        #expect(stop.label == "安全停止")
        #expect(play.label == "运行方案")
        #expect(try frames(window) == initial)
    }

    private func frames(_ window: NSWindow) throws -> [NSRect] {
        let result = try ["安全停止", "运行方案"].map { label in
            try #require(actionElement(label, in: window)).accessibilityFrame()
        }
        #expect(result.allSatisfy { $0.width > 0 && $0.height > 0 })
        #expect(result[0].maxX <= result[1].minX)
        return result
    }

    private func actionElement(_ label: String, in element: any NSAccessibilityProtocol) -> (any NSAccessibilityProtocol)? {
        if element.accessibilityLabel() == label { return element }
        for child in element.accessibilityChildren() ?? [] {
            if let child = child as? any NSAccessibilityProtocol,
               let match = actionElement(label, in: child) { return match }
        }
        return nil
    }
}
