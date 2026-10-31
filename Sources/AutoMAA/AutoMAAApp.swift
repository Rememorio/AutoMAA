import AppKit
import AutoMAAKit
import SwiftUI

@main
struct AutoMAAApp: App {
    @StateObject private var model: AppModel
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate

    init() {
        if let root = Self.developmentDataDirectory() {
            _model = StateObject(wrappedValue: AppModel(
                directories: AppDirectories(root: root),
                launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
                managesSystemLaunchAgents: false,
                checksForUpdatesAutomatically: false,
                allowsAutomaticMAAMaintenance: false
            ))
            return
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        Window("AutoMAA", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_020, minHeight: 680)
                .onAppear { applicationDelegate.model = model }
        }
        .defaultSize(width: 1_180, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            AutoMAACommands(model: model)
        }
        Settings {
            SettingsView(selectedSection: $model.settingsSection)
                .environmentObject(model)
                .tint(.maaAccent)
                .focusedSceneValue(\.workspaceActive, false)
                .onAppear { applicationDelegate.model = model }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    static func developmentDataDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> URL? {
        if let value = environment["AUTOMAA_DEVELOPMENT_DATA_DIRECTORY"],
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(filePath: value, directoryHint: .isDirectory).standardizedFileURL
        }
        guard let index = arguments.firstIndex(of: "--data-directory"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return URL(filePath: arguments[index + 1], directoryHint: .isDirectory).standardizedFileURL
    }
}

private struct AutoMAACommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @FocusedValue(\.workspaceActive) private var workspaceActive
    @FocusedValue(\.workspaceChromeController) private var workspaceChrome

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("切换边栏") { workspaceChrome?.toggleSidebar(nil) }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(workspaceActive != true || workspaceChrome == nil || model.entityEditor != nil
                          || model.readinessRequest != nil || model.updateDetailsRequest != nil)
        }
        CommandGroup(replacing: .appInfo) {
            Button("关于 AutoMAA") { showSettings(.about) }
        }
        CommandGroup(after: .appInfo) {
            Button(model.applicationUpdateMenuTitle) {
                model.openApplicationUpdate()
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        CommandGroup(after: .newItem) {
            Button(runCommandTitle) { model.runSelectedPlan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(workspaceActive != true || model.entityEditor != nil || model.readinessRequest != nil || model.updateDetailsRequest != nil || !model.canRun || model.currentPlanID.map { model.continuation(for: $0).pending == 0 } == true)
            Button(model.activePlanID == nil ? "取消更新" : "安全停止当前流程") { model.cancelCurrentOperation() }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canCancelRun && !model.applicationUpdateState.canCancel)
            Button("保存配置") { model.saveNow() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(workspaceActive != true || model.entityEditor != nil || model.readinessRequest != nil || model.updateDetailsRequest != nil)
        }
        CommandGroup(replacing: .help) {
            Button("AutoMAA 使用文档") {
                NSWorkspace.shared.open(model.documentationURL)
            }
            Button("报告问题…") {
                NSWorkspace.shared.open(model.issueReportURL)
            }
        }
    }

    private var runCommandTitle: String {
        guard let planID = model.currentPlanID, model.canRun(planID: planID) else {
            return "运行当前方案"
        }
        return model.runTitle(for: planID, readyTitle: "运行当前方案")
    }

    private func showSettings(_ section: SettingsSection) {
        model.showSettings(section)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}
