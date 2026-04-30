import SwiftUI

@MainActor
final class TranslatorViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case streaming(String)
        case done(String)
        case error(String)
    }

    @Published var input: String = ""
    @Published var state: State = .idle

    private let service: TranslationService
    private let dictTemplate: String
    private let translTemplate: String
    private var task: Task<Void, Never>?

    init(service: TranslationService, dictTemplate: String, translTemplate: String) {
        self.service = service
        self.dictTemplate = dictTemplate
        self.translTemplate = translTemplate
    }

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        state = .streaming("")
        let prompt = PromptBuilder.build(
            text: text,
            dictionaryTemplate: dictTemplate,
            translationTemplate: translTemplate
        )
        task = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            do {
                for try await token in self.service.translate(systemPrompt: prompt.systemPrompt, userText: text) {
                    buffer += token
                    self.state = .streaming(buffer)
                }
                self.state = .done(buffer)
            } catch let e as TranslationError {
                if case .cancelled = e { return } // swallow
                self.state = .error(e.errorDescription ?? "未知错误")
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func reset() {
        task?.cancel()
        input = ""
        state = .idle
    }
}

struct TranslatorContentView: View {
    @ObservedObject var vm: TranslatorViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputField
                .background(
                    // Hidden shortcut: plain Return submits. Shift+Return doesn't match
                    // this shortcut, so it falls through to the TextField and inserts a
                    // newline (the default behavior of axis: .vertical).
                    Button("", action: { vm.submit() })
                        .keyboardShortcut(.return, modifiers: [])
                        .opacity(0)
                        .frame(width: 0, height: 0)
                )

            switch vm.state {
            case .idle:
                EmptyView()
            case .streaming(let s) where s.isEmpty:
                ProgressView().controlSize(.small)
            case .streaming(let s), .done(let s):
                ScrollView {
                    Text(LocalizedStringKey(s))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            case .error(let msg):
                Text("⚠️ \(msg)")
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 560)
        .onAppear { inputFocused = true }
    }

    @ViewBuilder
    private var inputField: some View {
        let base = TextField(
            "输入中文或英文，回车翻译（Shift+回车换行）",
            text: $vm.input,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 17))
        .lineLimit(1...8)
        .focused($inputFocused)

        // Suppress the macOS 15+ Writing Tools / Apple Intelligence affordance
        // that pins itself to text inputs by default — irrelevant for this UI.
        if #available(macOS 15.0, *) {
            base.writingToolsBehavior(.disabled)
        } else {
            base
        }
    }
}
