import SwiftUI

/// Container that renders the suggestion dropdown when ``vm.isSuggestionsVisible``
/// is true. Click-to-pick goes straight to submit (skips the
/// ``hasUserMovedSelection`` flag — the click is itself an explicit pick).
struct TranslatorSuggestionsView: View {
    @ObservedObject var vm: TranslatorViewModel

    var body: some View {
        if vm.isSuggestionsVisible {
            VStack(spacing: 0) {
                ForEach(Array(vm.suggestions.enumerated()), id: \.element.id) { index, item in
                    SuggestionRow(
                        item: item,
                        isSelected: index == vm.selectionIndex,
                        prefix: vm.input
                    )
                    .onTapGesture {
                        vm.selectionIndex = index
                        vm.input = vm.suggestions[index].word
                        vm.submit()
                    }
                }
            }
        }
    }
}

/// One row in the suggestion dropdown. Pure render — no logic.
struct SuggestionRow: View {
    let item: SuggestionItem
    let isSelected: Bool
    /// The user's current input string; used to render the matched prefix in
    /// a lighter style and the remainder in primary color (Raycast-style).
    let prefix: String

    var body: some View {
        HStack(spacing: 8) {
            icon
            wordWithGloss
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: TranslatorTheme.suggestionRowHeight)
        .background(rowBackground)
        .overlay(alignment: .leading) { selectionBar }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(iconFill)
            Text(iconLetter)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }

    private var iconLetter: String {
        switch item.kind {
        case .dictionary: return "A"
        case .history:    return "🕘"      // M2 only; M1 never produces .history
        }
    }

    private var iconFill: Color {
        switch (item.kind, isSelected) {
        case (.dictionary, true):  return TranslatorTheme.accentColor
        case (.dictionary, false): return TranslatorTheme.iconNeutralFill
        case (.history, _):        return TranslatorTheme.iconNeutralFill
        }
    }

    @ViewBuilder
    private var wordWithGloss: some View {
        HStack(spacing: 6) {
            wordAttributed
            if let pos = item.pos {
                Text(pos)
                    .font(.system(size: 12).italic())
                    .foregroundStyle(.secondary)
            }
            Text(item.gloss)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var wordAttributed: Text {
        let lowerWord = item.word.lowercased()
        let lowerPrefix = prefix.lowercased()
        if !lowerPrefix.isEmpty && lowerWord.hasPrefix(lowerPrefix) {
            let head = String(item.word.prefix(lowerPrefix.count))
            let tail = String(item.word.dropFirst(lowerPrefix.count))
            return Text(head)
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .regular))
                + Text(tail)
                .foregroundColor(.primary)
                .font(.system(size: 14, weight: .semibold))
        }
        return Text(item.word)
            .foregroundColor(.primary)
            .font(.system(size: 14, weight: .semibold))
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if item.badge == .recent {
                Text("最近")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(TranslatorTheme.badgeFill)
                    )
            }
            if isSelected {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            TranslatorTheme.selectionRowFill
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isSelected {
            Rectangle()
                .fill(TranslatorTheme.accentColor)
                .frame(width: 2)
        }
    }
}
