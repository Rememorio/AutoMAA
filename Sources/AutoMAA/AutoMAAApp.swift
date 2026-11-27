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
                .frame(minWidth: WorkspaceLayout.minimumSize.width, minHeight: WorkspaceLayout.minimumSize.height)
                .onAppear { applicationDelegate.model = model }
        }
        .defaultSize(width: WorkspaceLayout.defaultSize.width, height: WorkspaceLayout.defaultSize.height)
        .windowToolbarStyle(.unified)
        .commands {
            AutoMAACommands(model: model)
        }
        Window("软件更新", id: ApplicationUpdateView.windowID) {
            ApplicationUpdateView()
                .environmentObject(model)
                .focusedSceneValue(\.operationCommandScope, .applicationUpdate)
                .onAppear { applicationDelegate.model = model }
        }
        .defaultSize(width: 560, height: 540)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        Settings {
            SettingsView(selectedSection: $model.settingsSection)
                .environmentObject(model)
                .tint(.maaAccent)
                .focusedSceneValue(\.workspaceActive, false)
                .focusedSceneValue(\.operationCommandScope, model.settingsSection == .environment ? .maaEnvironment : .unavailable)
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
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceActive) private var workspaceActive
    @FocusedValue(\.operationCommandScope) private var focusedOperation
    @FocusedValue(\.workspaceChromeController) private var workspaceChrome

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("切换边栏") { workspaceChrome?.toggleSidebar(nil) }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(workspaceActive != true || workspaceChrome == nil || hasWorkspaceSheet)
        }
        CommandGroup(replacing: .appInfo) {
            Button("关于 AutoMAA") { showSettings(.about) }
        }
        CommandGroup(after: .appInfo) {
            Button(model.applicationUpdateEntryTitle) {
                model.openApplicationUpdate()
                openWindow(id: ApplicationUpdateView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        CommandGroup(after: .newItem) {
            Button(runCommandTitle) { model.runSelectedPlan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(operationScope != .workspace || model.commandRunRequest == nil)
            Button(operationScope.cancelTitle) { operationScope.cancel(in: model) }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!operationScope.canCancel(in: model))
            Button("保存配置") { model.saveNow() }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(workspaceActive != true || hasWorkspaceSheet)
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

    private var hasWorkspaceSheet: Bool {
        model.entityEditor != nil || model.readinessRequest != nil || model.arrangementRequest != nil
            || model.updateDetailsRequest != nil || model.fightRecoveryDestination != nil
    }

    private var operationScope: OperationCommandScope {
        guard let window = NSApp.keyWindow else { return .unavailable }
        return OperationCommandScope.resolve(focusedScope: focusedOperation, workspaceActive: workspaceActive == true,
            hasSheet: window.attachedSheet != nil || window.sheetParent != nil || (workspaceActive == true && hasWorkspaceSheet))
    }

    private var runCommandTitle: String {
        guard let planID = model.commandPlanID, let request = model.commandRunRequest else {
            return "运行新一轮"
        }
        return model.runTitle(for: planID, request: request)
    }

    private func showSettings(_ section: SettingsSection) {
        model.showSettings(section)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}
