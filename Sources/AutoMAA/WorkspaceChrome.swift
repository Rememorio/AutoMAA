import AppKit
import AutoMAAKit
import SwiftUI

private struct WorkspaceActiveKey: FocusedValueKey { typealias Value = Bool }
private struct WorkspaceChromeFocusKey: FocusedValueKey { typealias Value = WorkspaceChromeController }
private struct OperationCommandScopeKey: FocusedValueKey { typealias Value = OperationCommandScope }

extension FocusedValues {
    var operationCommandScope: OperationCommandScope? {
        get { self[OperationCommandScopeKey.self] }
        set { self[OperationCommandScopeKey.self] = newValue }
    }
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
