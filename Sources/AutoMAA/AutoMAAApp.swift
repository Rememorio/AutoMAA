import AppKit
import AutoMAAKit
import SwiftUI

@main
struct AutoMAAApp: App {
    @StateObject private var model: AppModel

    init() {
        #if DEBUG
        if let root = Self.developmentDataDirectory() {
            _model = StateObject(wrappedValue: AppModel(
                directories: AppDirectories(root: root),
                launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
                managesSystemLaunchAgents: false,
                checksForUpdatesAutomatically: false
            ))
            return
        }
        #endif
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        Window("AutoMAA", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_020, minHeight: 680)
        }
        .defaultSize(width: 1_180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AutoMAACommands(model: model)
        }
    }

    #if DEBUG
    private static func developmentDataDirectory() -> URL? {
        if let value = ProcessInfo.processInfo.environment["AUTOMAA_DEVELOPMENT_DATA_DIRECTORY"],
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(filePath: value, directoryHint: .isDirectory).standardizedFileURL
        }
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--data-directory"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return URL(filePath: arguments[index + 1], directoryHint: .isDirectory).standardizedFileURL
    }
    #endif
}

private struct AutoMAACommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 AutoMAA") { show(.about) }
        }
        CommandGroup(after: .appInfo) {
            Button("检查更新…") {
                show(.settings)
                model.checkForApplicationUpdate()
            }
            .disabled(model.applicationUpdateState.isBusy)
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { show(.settings) }
                .keyboardShortcut(",", modifiers: [.command])
        }
        CommandGroup(after: .newItem) {
            Button("运行当前方案") { model.runSelectedPlan() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRun)
            Button("安全停止当前流程") { model.cancelRun() }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canCancelRun)
            Button("保存配置") { model.saveNow() }
                .keyboardShortcut("s", modifiers: [.command])
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

    private func show(_ selection: SidebarSelection) {
        model.selection = selection
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
