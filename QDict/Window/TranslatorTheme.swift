import SwiftUI

/// Centralized visual tokens for the translator panel chrome (idle shell).
/// Colors come from Asset Catalog and adapt to light/dark automatically.
enum TranslatorTheme {

    // MARK: - Colors

    static var panelBackground: Color { Color("PanelBackground") }
    static var panelStroke: Color { Color("PanelStroke") }
    static var dividerColor: Color { Color("DividerColor") }
    static var hintKeyBackground: Color { Color("HintKeyBackground") }
    static var hintKeyStroke: Color { Color("HintKeyStroke") }
    static var clearButtonFill: Color { Color("ClearButtonFill") }

    static var primaryText: Color { Color.primary }
    static var secondaryText: Color { Color.secondary }

    // MARK: - Fonts

    static let brandFont: Font = .system(size: 15, weight: .semibold)
    static let inputFont: Font = .system(size: 18)
    static let hintLabelFont: Font = .system(size: 12)
    static let hintKeyFont: Font = .system(size: 11, weight: .medium, design: .rounded)

    // MARK: - Geometry

    static let panelWidth: CGFloat = 560
    static let panelCornerRadius: CGFloat = 12
    static let panelShadowRadius: CGFloat = 24
    static let panelShadowYOffset: CGFloat = 8
    static let panelShadowOpacityLight: Double = 0.18
    static let panelShadowOpacityDark: Double = 0.45

    static let headerPadding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    static let inputPadding = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    static let hintsPadding = EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16)

    static let headerIconSize: CGFloat = 24
    static let clearButtonSize: CGFloat = 16
    static let touchTargetSize: CGFloat = 28
}
