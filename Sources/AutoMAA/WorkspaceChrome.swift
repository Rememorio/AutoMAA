import AppKit
import AutoMAAKit
import SwiftUI

private struct WorkspaceActiveKey: FocusedValueKey { typealias Value = Bool }
private struct WorkspaceChromeFocusKey: FocusedValueKey { typealias Value = WorkspaceChromeController }

extension FocusedValues {
    var workspaceActive: Bool? {
        get { self[WorkspaceActiveKey.self] }
        set { self[WorkspaceActiveKey.self] = newValue }
    }
    var workspaceChromeController: WorkspaceChromeController? {
        get { self[WorkspaceChromeFocusKey.self] }
        set { self[WorkspaceChromeFocusKey.self] = newValue }
    }
}

extension Notification.Name {
    static let autoMAAOpenSettings = Notification.Name("AutoMAA.OpenSettings")
}

struct OperationStopControl: View {
    @EnvironmentObject private var model: AppModel
    var showsTitle = false

    private var title: String {
        if model.isCancellingRun { return "正在停止" }
        return model.activePlanID == nil && !model.isExternalRunActive ? "取消更新" : "安全停止"
    }

    var body: some View {
        Button { model.cancelCurrentOperation() } label: {
            if showsTitle {
                Label(title, systemImage: model.isCancellingRun ? "hourglass" : "stop.fill")
            } else {
                Label(title, systemImage: model.isCancellingRun ? "hourglass" : "stop.fill").labelStyle(.iconOnly)
            }
        }
        .disabled(!model.canCancelRun || model.isCancellingRun)
        .help(model.isCancellingRun ? "等待当前操作停止并清理连接" : title)
    }
}
