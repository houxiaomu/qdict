import SwiftUI

/// Static keyboard-shortcut hint bar always shown at the bottom of the
/// idle shell. Decoupled from the actual key handling — the real
/// shortcuts are handled in `TranslatorWindowController`'s key monitor.
struct TranslatorHintsView: View {
    var body: some View {
        HStack(spacing: 18) {
            hint(keys: ["↵"],            label: "翻译")
            hint(keys: ["⇧", "+", "↵"],  label: "换行")
            hint(keys: ["⌘", "+", "Y"],  label: "历史记录")
            hint(keys: ["esc"],          label: "关闭")
            Spacer(minLength: 0)
        }
        .padding(TranslatorTheme.hintsPadding)
    }

    private func hint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                if key == "+" {
                    Text("+")
                        .font(TranslatorTheme.hintLabelFont)
                        .foregroundStyle(TranslatorTheme.secondaryText)
                } else {
                    keyCap(key)
                }
            }
            Text(label)
                .font(TranslatorTheme.hintLabelFont)
                .foregroundStyle(TranslatorTheme.secondaryText)
                .padding(.leading, 2)
        }
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(TranslatorTheme.hintKeyFont)
            .foregroundStyle(TranslatorTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(TranslatorTheme.hintKeyBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(TranslatorTheme.hintKeyStroke, lineWidth: 0.5)
            )
    }
}
