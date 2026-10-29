import SwiftUI

struct SettingsPresentation<Content: View>: View {
    @Binding var selectedSection: SettingsSection
    let onPreferredHeight: (CGFloat, Bool) -> Void
    @ViewBuilder let content: (SettingsSection) -> Content

    var body: some View {
        SettingsPane(onPreferredHeight: onPreferredHeight) {
            content(selectedSection)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .id(selectedSection)
        .background(SettingsToolbar(selectedSection: $selectedSection).frame(width: 0, height: 0))
    }
}

private struct SettingsPane<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onPreferredHeight: (CGFloat, Bool) -> Void
    @ViewBuilder let content: () -> Content
    @State private var isVisible = false

    var body: some View {
        ScrollView {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { onPreferredHeight(geometry.size.height, true) }
                            .onChange(of: geometry.size.height) { _, height in
                                if isVisible { onPreferredHeight(height, false) }
                            }
                    }
                }
                .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isVisible = true }
        }
        .onDisappear { isVisible = false }
    }
}
