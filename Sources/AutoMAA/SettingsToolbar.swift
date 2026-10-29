import AppKit
import SwiftUI

/// The window owns its title; selecting a preferences item only changes the page.
struct SettingsToolbar: NSViewRepresentable {
    @Binding var selectedSection: SettingsSection

    func makeCoordinator() -> SettingsToolbarController {
        SettingsToolbarController(selectedSection: selectedSection) { selectedSection = $0 }
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.controller = context.coordinator
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        context.coordinator.onSelection = { selectedSection = $0 }
        context.coordinator.synchronizeSelection(selectedSection)
        view.attach()
    }

    final class AttachmentView: NSView {
        var controller: SettingsToolbarController?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            if let window { controller?.attach(to: window) }
        }
    }
}

@MainActor
final class SettingsToolbarController: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "AutoMAA.Settings")
    var onSelection: (SettingsSection) -> Void
    private var selectedSection: SettingsSection

    init(selectedSection: SettingsSection, onSelection: @escaping (SettingsSection) -> Void) {
        self.selectedSection = selectedSection
        self.onSelection = onSelection
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.centeredItemIdentifiers = Set(itemIdentifiers)
        if #available(macOS 15, *) { toolbar.allowsDisplayModeCustomization = false }
    }

    func attach(to window: NSWindow) {
        if window.toolbar !== toolbar {
            window.title = "设置"
            window.toolbarStyle = .preference
            window.toolbar = toolbar
        }
        synchronizeSelection(selectedSection)
    }

    func synchronizeSelection(_ section: SettingsSection) {
        selectedSection = section
        toolbar.selectedItemIdentifier = .init(section.rawValue)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { itemIdentifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { itemIdentifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { itemIdentifiers }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = SettingsSection(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = section.title
        item.paletteLabel = section.title
        item.toolTip = section.title
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
        item.target = self
        item.action = #selector(selectSection(_:))
        return item
    }

    private var itemIdentifiers: [NSToolbarItem.Identifier] {
        SettingsSection.allCases.map { .init($0.rawValue) }
    }

    @objc private func selectSection(_ item: NSToolbarItem) {
        guard let section = SettingsSection(rawValue: item.itemIdentifier.rawValue) else { return }
        synchronizeSelection(section)
        onSelection(section)
    }
}
