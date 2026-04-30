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
    private let historyStore: HistoryStore?
    private let historyMode: Mode
    private var task: Task<Void, Never>?

    init(
        service: TranslationService,
        dictTemplate: String,
        translTemplate: String,
        historyStore: HistoryStore? = nil,
        historyMode: Mode = .dictionary
    ) {
        self.service = service
        self.dictTemplate = dictTemplate
        self.translTemplate = translTemplate
        self.historyStore = historyStore
        self.historyMode = historyMode
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
                self.historyStore?.append(query: text, result: buffer, mode: self.historyMode)
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

    // MARK: - Session snapshot (soft-hide / restore)

    func snapshot(now: Date = Date()) -> SessionSnapshot? {
        SessionSnapshot.makeIfWorthCapturing(input: input, state: state, now: now)
    }

    func restore(_ snapshot: SessionSnapshot) {
        task?.cancel()
        input = snapshot.input
        state = snapshot.state
    }

    // MARK: - History recall

    /// Replay a history entry without re-calling the API.
    func loadFromHistory(_ entry: HistoryEntry) {
        task?.cancel()
        input = entry.query
        state = .done(entry.result)
    }

    // MARK: - History drawer state

    @Published var isDrawerOpen: Bool = false
    @Published var selectedHistoryID: UUID?

    func toggleDrawer(history: HistoryStore) {
        if isDrawerOpen {
            closeDrawer()
        } else {
            isDrawerOpen = true
            selectedHistoryID = history.entries.first?.id
        }
    }

    func moveSelection(in history: HistoryStore, by delta: Int) {
        if !isDrawerOpen {
            isDrawerOpen = true
            selectedHistoryID = (delta < 0)
                ? history.entries.first?.id
                : history.entries.last?.id
            return
        }
        guard !history.entries.isEmpty else { return }
        let ids = history.entries.map(\.id)
        let currentIdx = ids.firstIndex(where: { $0 == selectedHistoryID }) ?? 0
        let newIdx = max(0, min(ids.count - 1, currentIdx + delta))
        selectedHistoryID = ids[newIdx]
    }

    func closeDrawer() {
        isDrawerOpen = false
        selectedHistoryID = nil
    }

    func confirmSelection(history: HistoryStore) {
        guard let id = selectedHistoryID,
              let entry = history.entries.first(where: { $0.id == id }) else { return }
        loadFromHistory(entry)
        closeDrawer()
    }

    func deleteSelection(history: HistoryStore) {
        guard let id = selectedHistoryID else { return }
        let ids = history.entries.map(\.id)
        let currentIdx = ids.firstIndex(of: id) ?? 0
        history.remove(id: id)
        if history.entries.isEmpty {
            closeDrawer()
        } else {
            let newIdx = min(currentIdx, history.entries.count - 1)
            selectedHistoryID = history.entries[newIdx].id
        }
    }
}

struct TranslatorContentView: View {
    @ObservedObject var vm: TranslatorViewModel
    @ObservedObject var historyStore: HistoryStore
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputField

            switch vm.state {
            case .idle:
                EmptyView()
            case .streaming(let s) where s.isEmpty:
                Divider()
                ProgressView().controlSize(.small)
                    .padding(.vertical, 4)
            case .streaming(let s), .done(let s):
                Divider()
                ScrollView {
                    Text(LocalizedStringKey(s))
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            case .error(let msg):
                Divider()
                Text("⚠️ \(msg)")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            if vm.isDrawerOpen {
                Divider()
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                HistoryDrawerView(
                    store: historyStore,
                    selectedID: Binding(
                        get: { vm.selectedHistoryID },
                        set: { vm.selectedHistoryID = $0 }
                    ),
                    onPick: { entry in
                        vm.loadFromHistory(entry)
                        vm.closeDrawer()
                    },
                    onDelete: { entry in
                        historyStore.remove(id: entry.id)
                    }
                )
            }
        }
        .padding(14)
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
        .font(.system(size: 15))
        .lineLimit(1...8)
        .focused($inputFocused)

        if #available(macOS 15.0, *) {
            base.writingToolsBehavior(.disabled)
        } else {
            base
        }
    }
}
