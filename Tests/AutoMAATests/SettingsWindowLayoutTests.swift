import AppKit
import Testing
@testable import AutoMAA

@Suite("Settings window layout")
struct SettingsWindowLayoutTests {
    @Test("feedback adds its own space without reducing the settings page viewport", arguments: [CGFloat(180), 300, 520])
    func feedbackPreservesContent(page: CGFloat) {
        let before = SettingsWindowLayout.contentHeight(page: page, feedback: 0)
        let after = SettingsWindowLayout.contentHeight(page: page, feedback: 48)
        #expect(after - before == 48)
        #expect(after - 48 >= page)
        #expect(SettingsWindowLayout.contentHeight(page: page, feedback: 0) == before)
    }

    @Test("switching pages preserves width and toolbar position")
    func stableToolbar() {
        let current = NSRect(x: 200, y: 300, width: 560, height: 440)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        for contentHeight: CGFloat in [240, 540] {
            let frame = SettingsWindowLayout.frame(current: current, contentHeight: contentHeight,
                                                   chromeHeight: 80, visibleFrame: screen)
            #expect(frame.width == current.width)
            #expect(frame.maxY == current.maxY)
            #expect(frame.height == contentHeight + 80)
        }
    }

    @Test("long pages and displaced windows stay within the current screen")
    func constrainedToScreen() {
        let screen = NSRect(x: -1440, y: 80, width: 1440, height: 700)
        let current = NSRect(x: -500, y: -100, width: 560, height: 440)
        let frame = SettingsWindowLayout.frame(current: current, contentHeight: 2000,
                                               chromeHeight: 80, visibleFrame: screen)
        #expect(screen.contains(frame))
        #expect(frame.height == 676)
        #expect(frame.width == 560)
    }

    @Test("restoring an oversized window returns to the common settings width")
    func oversizedRestoredWindow() {
        let current = NSRect(x: 200, y: 200, width: 900, height: 600)
        let frame = SettingsWindowLayout.frame(current: current, contentHeight: 240,
                                               chromeHeight: 80,
                                               visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(frame.width == 560)
        #expect(frame.midX == current.midX)
        #expect(frame.maxY == current.maxY)
    }
}
