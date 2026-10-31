import AppKit
import AutoMAAKit
import SwiftUI
import Testing
@testable import AutoMAA

@MainActor
@Suite("Workspace run controls")
struct WorkspaceRunControlsTests {
    @Test("starting, viewing another plan and completing a run do not reflow the toolbar host")
    func completionDoesNotMoveTheRunControl() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let (window, host) = makeHost(model)
        defer { window.contentView = nil }
        let windowFrame = window.frame
        let hostFrame = host.frame
        let initialSize = measure(host, model: model)
        #expect(initialSize.width > 28)
        #expect(initialSize.height == 28)

        var other = fixture.plan
        other.id = UUID()
        other.name = "当前正在查看的另一个名称很长的方案"
        model.configuration.plans.append(other)
        model.selection = .plan(other.id)
        model.runningPlanID = fixture.plan.id
        model.phase = .runningTask
        model.isRunning = true
        for progress in [0.0, 0.5, 1.0] {
            model.progress = progress
            #expect(measure(host, model: model) == initialSize)
            #expect(host.frame == hostFrame)
        }

        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(.init(status: .completed, stage: "1-7", times: 1), for: fixture.step.key)
        try ExecutionStateStore(directories: model.directories).save(state)
        model.isRunning = false
        model.runningPlanID = nil
        model.selection = .plan(fixture.plan.id)
        model.reloadActivityHistory()
        #expect(model.continuation(for: fixture.plan.id).pending == 0)
        #expect(measure(host, model: model) == initialSize)
        #expect(host.frame == hostFrame)
        #expect(window.frame == windowFrame)
    }

    @Test("attention, configuration errors and unrelated pages preserve the same run control slot")
    func attentionAndMissingContextDoNotReflowTheToolbar() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = fixture.model
        let (window, host) = makeHost(model)
        defer { window.contentView = nil }
        let initialSize = measure(host, model: model)
        let initialFrame = host.frame

        var state = ExecutionState(dateKey: ExecutionStateStore.todayKey)
        state.record(.init(status: .unconfirmed, reason: .interruptedBattle), for: fixture.step.key)
        try ExecutionStateStore(directories: model.directories).save(state)
        model.reloadActivityHistory()
        #expect(model.continuation(for: fixture.plan.id).unconfirmed == 1)
        #expect(measure(host, model: model) == initialSize)

        model.configuration.cliPath = fixture.root.appending(path: "missing-maa").path
        #expect(model.planRunState(planID: fixture.plan.id) == .configurationIncomplete)
        #expect(measure(host, model: model) == initialSize)

        model.activitySelection = .session("unrelated-record")
        for selection: SidebarSelection in [.overview, .clients, .activity] {
            model.selection = selection
            #expect(WorkspaceToolbarRunControls.isVisible(in: model))
            #expect(measure(host, model: model) == initialSize)
            #expect(host.frame == initialFrame)
        }
        #expect(!model.isWorkflowRunning)
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
            runnerExecutableURL: URL(filePath: "/usr/bin/true"))
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

    private func makeHost(_ model: AppModel) -> (NSWindow, NSHostingView<AnyView>) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AnyView(WorkspaceToolbarRunControls().environmentObject(model)))
        host.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 170, height: 28),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = host
        return (window, host)
    }

    private func measure(_ host: NSHostingView<AnyView>, model: AppModel) -> NSSize {
        host.rootView = AnyView(WorkspaceToolbarRunControls().environmentObject(model))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }
}
