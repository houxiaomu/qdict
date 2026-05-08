import SwiftUI

/// Borderless visual chrome for the translator panel. Wraps the entire
/// SwiftUI content tree, applies the warm background, rounded corners,
/// stroke, and a hand-drawn shadow. Reserves padding around itself so
/// the shadow has room to render without being clipped by the host
/// NSPanel's bounds.
struct TranslatorShell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(width: TranslatorTheme.panelWidth)
        .background(TranslatorTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: TranslatorTheme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TranslatorTheme.panelCornerRadius)
                .stroke(TranslatorTheme.panelStroke, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(
                colorScheme == .dark
                    ? TranslatorTheme.panelShadowOpacityDark
                    : TranslatorTheme.panelShadowOpacityLight
            ),
            radius: TranslatorTheme.panelShadowRadius,
            x: 0,
            y: TranslatorTheme.panelShadowYOffset
        )
        .padding(TranslatorTheme.panelShadowRadius)
    }
}
