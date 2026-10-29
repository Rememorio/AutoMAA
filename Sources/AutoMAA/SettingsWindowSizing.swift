import AppKit
import QuartzCore
import SwiftUI

/// Keeps the toolbar in place while fitting each settings page within the current screen.
enum SettingsWindowLayout {
    static func contentHeight(page: CGFloat, feedback: CGFloat) -> CGFloat {
        max(220, ceil(page)) + ceil(max(0, feedback))
    }

    static func frame(current: NSRect, contentHeight: CGFloat, chromeHeight: CGFloat, visibleFrame: NSRect) -> NSRect {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        let height = min(max(220, ceil(contentHeight)) + chromeHeight, available.height)
        var result = current
        result.size.width = 560
        result.size.height = height
        result.origin.y = max(available.minY, min(current.maxY, available.maxY) - height)
        let centeredX = current.midX - result.width / 2
        result.origin.x = max(available.minX, min(centeredX, available.maxX - result.width))
        return result
    }
}

struct SettingsFeedbackHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsWindowSizing: NSViewRepresentable {
    let contentHeight: CGFloat
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SizingView { SizingView() }

    func updateNSView(_ view: SizingView, context: Context) {
        view.contentHeight = contentHeight
        view.reduceMotion = reduceMotion
        view.scheduleResize()
    }

    final class SizingView: NSView {
        var contentHeight: CGFloat = 360
        var reduceMotion = false
        private var appliedHeight: CGFloat?
        private var resizeTask: Task<Void, Never>?
        private weak var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if observedWindow !== window {
                NotificationCenter.default.removeObserver(self)
                observedWindow = window
                appliedHeight = nil
                if let window {
                    NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                        name: NSWindow.didChangeScreenNotification, object: window)
                }
            }
            scheduleResize()
        }

        @objc private func screenChanged() {
            appliedHeight = nil
            scheduleResize()
        }

        func scheduleResize() {
            resizeTask?.cancel()
            resizeTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                self?.resize()
            }
        }

        private func resize() {
            guard let window, let screen = window.screen, appliedHeight != contentHeight else { return }
            let shouldAnimate = appliedHeight != nil && window.isVisible && !reduceMotion
            appliedHeight = contentHeight
            let target = SettingsWindowLayout.frame(
                current: window.frame, contentHeight: contentHeight,
                chromeHeight: window.frame.height - window.contentLayoutRect.height,
                visibleFrame: screen.visibleFrame
            )
            guard abs(target.height - window.frame.height) > 1 || target.width != window.frame.width
                    || target.origin != window.frame.origin else { return }
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(target, display: true)
                }
            } else {
                window.setFrame(target, display: true)
            }
        }
    }
}
