import SwiftUI
import AppKit

struct TranslatorHeaderView: View {
    let onSettings: () -> Void
    @State private var settingsHovered = false

    var body: some View {
        HStack(spacing: 8) {
            brandMark
            Text("QDict")
                .font(TranslatorTheme.brandFont)
                .foregroundStyle(TranslatorTheme.primaryText)

            Spacer(minLength: 0)

            settingsButton
        }
        .padding(TranslatorTheme.headerPadding)
    }

    private var brandMark: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(
                width: TranslatorTheme.headerIconSize,
                height: TranslatorTheme.headerIconSize
            )
            .accessibilityHidden(true)
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16))
                .foregroundStyle(
                    settingsHovered
                        ? TranslatorTheme.primaryText
                        : TranslatorTheme.secondaryText
                )
                .frame(
                    width: TranslatorTheme.touchTargetSize,
                    height: TranslatorTheme.touchTargetSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { settingsHovered = $0 }
        .accessibilityLabel("偏好设置")
        .help("偏好设置（⌘,）")
    }
}
