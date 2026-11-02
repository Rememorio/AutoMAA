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
