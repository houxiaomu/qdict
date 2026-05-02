import SwiftUI

struct TranslatorInputView: View {
    @ObservedObject var vm: TranslatorViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            textField
            if !vm.input.isEmpty {
                clearButton
            }
        }
        .padding(TranslatorTheme.inputPadding)
        .animation(.easeOut(duration: 0.12), value: vm.input.isEmpty)
    }

    @ViewBuilder
    private var textField: some View {
        let base = TextField("输入中文或英文", text: $vm.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(TranslatorTheme.inputFont)
            .lineLimit(1...8)
            .focused(isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)

        if #available(macOS 15.0, *) {
            base.writingToolsBehavior(.disabled)
        } else {
            base
        }
    }

    private var clearButton: some View {
        Button(action: { vm.input = "" }) {
            ZStack {
                Circle().fill(TranslatorTheme.clearButtonFill)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(
                width: TranslatorTheme.clearButtonSize,
                height: TranslatorTheme.clearButtonSize
            )
            .frame(
                width: TranslatorTheme.touchTargetSize,
                height: TranslatorTheme.touchTargetSize,
                alignment: .center
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清空输入")
    }
}
