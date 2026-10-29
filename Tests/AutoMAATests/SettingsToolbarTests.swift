import AppKit
import Testing
@testable import AutoMAA

@MainActor
@Suite("Settings toolbar")
struct SettingsToolbarTests {
    @Test("selecting every settings page never assigns a page name to the window title")
    func stableWindowTitle() throws {
        _ = NSApplication.shared
        let window = TitleRecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                                          styleMask: [.titled, .closable], backing: .buffered, defer: true)
        var selections: [SettingsSection] = []
        let controller = SettingsToolbarController(selectedSection: .general) { selections.append($0) }
        controller.attach(to: window)
        window.recordedTitles.removeAll()

        for section in SettingsSection.allCases + SettingsSection.allCases.reversed() {
            let item = try #require(controller.toolbar.items.first { $0.itemIdentifier.rawValue == section.rawValue })
            let action = try #require(item.action)
            #expect(NSApp.sendAction(action, to: item.target, from: item))
            #expect(selections.last == section)
            #expect(controller.toolbar.selectedItemIdentifier?.rawValue == section.rawValue)
            #expect(window.title == "设置")
        }
        #expect(window.recordedTitles.allSatisfy { $0 == "设置" })
        #expect(window.toolbarStyle == .preference)
    }

    @Test("application menu selection synchronizes the existing toolbar without triggering another navigation")
    func externalSelection() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        var callbackCount = 0
        let controller = SettingsToolbarController(selectedSection: .about) { _ in callbackCount += 1 }
        controller.attach(to: window)
        let toolbar = window.toolbar
        #expect(toolbar?.selectedItemIdentifier?.rawValue == SettingsSection.about.rawValue)
        controller.synchronizeSelection(.updates)
        controller.attach(to: window)
        #expect(window.toolbar === toolbar)
        #expect(toolbar?.selectedItemIdentifier?.rawValue == SettingsSection.updates.rawValue)
        #expect(callbackCount == 0)
        #expect(window.title == "设置")
    }
}

@MainActor
private final class TitleRecordingWindow: NSWindow {
    var recordedTitles: [String] = []

    override var title: String {
        get { super.title }
        set {
            recordedTitles.append(newValue)
            super.title = newValue
        }
    }
}
