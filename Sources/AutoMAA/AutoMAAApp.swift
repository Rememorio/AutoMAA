import SwiftUI

@main
struct AutoMAAApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_020, minHeight: 680)
        }
        .defaultSize(width: 1_180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { model.checkForApplicationUpdate() }
                    .disabled(model.applicationUpdateState.isBusy)
            }
            CommandGroup(after: .newItem) {
                Button("运行全部任务") { model.runAll() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!model.canRun)
                Button("安全停止当前流程") { model.cancelRun() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!model.isRunning)
                Button("保存配置") { model.saveNow() }
                    .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }
}
