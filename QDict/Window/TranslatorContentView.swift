import SwiftUI
import Combine

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

    // MARK: - Structured dictionary result (M3)
    @Published private(set) var dictionaryResult: DictionaryResult = DictionaryResult()
    @Published private(set) var lastRequestMode: Mode = .dictionary
    private var parser = StructuredStreamParser()

    // MARK: - Suggestion dropdown state (M1)
    @Published var suggestions: [SuggestionItem] = []
    @Published var selectionIndex: Int = 0
    @Published private(set) var hasUserMovedSelection: Bool = false

    var isSuggestionsVisible: Bool {
        !suggestions.isEmpty && !isDrawerOpen
    }

    private let service: TranslationService
    private let dictTemplate: String
    private let translTemplate: String
    private let historyStore: HistoryStore?
    private let historyMode: Mode
    private let suggestionEngine: SuggestionEngine
    private var task: Task<Void, Never>?
    private var inputObserver: AnyCancellable?

    init(
        service: TranslationService,
        dictTemplate: String,
        translTemplate: String,
        historyStore: HistoryStore? = nil,
        historyMode: Mode = .dictionary,
        suggestionEngine: SuggestionEngine = DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())
    ) {
        self.service = service
        self.dictTemplate = dictTemplate
        self.translTemplate = translTemplate
        self.historyStore = historyStore
        self.historyMode = historyMode
        self.suggestionEngine = suggestionEngine
        bindInput()
    }

    private func bindInput() {
        inputObserver = $input
            .removeDuplicates()
            .sink { [weak self] s in self?.refreshSuggestions(for: s) }
    }

    func refreshSuggestions(for raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isASCII = trimmed.allSatisfy { $0.isASCII }
        let endsWithSpace: Bool
        if let last = raw.last { endsWithSpace = (last == " " || last == "\t") } else { endsWithSpace = false }
        let isStreaming: Bool
        if case .streaming = state { isStreaming = true } else { isStreaming = false }

        if trimmed.count < 2 || !isASCII || endsWithSpace || isStreaming {
            suggestions = []
            selectionIndex = 0
            hasUserMovedSelection = false
            return
        }

        let items = suggestionEngine.query(trimmed.lowercased(), limit: 6)
        suggestions = items
        selectionIndex = 0
        hasUserMovedSelection = false
    }

    func moveSuggestionSelection(by delta: Int) {
        guard isSuggestionsVisible else { return }
        let next = max(0, min(suggestions.count - 1, selectionIndex + delta))
        selectionIndex = next
        hasUserMovedSelection = true
    }

    func acceptSuggestionForCompletion() {
        guard isSuggestionsVisible else { return }
        let item = suggestions[selectionIndex]
        input = item.word
        hasUserMovedSelection = false
    }

    func submitOrUseSelected() {
        if isSuggestionsVisible && hasUserMovedSelection {
            let item = suggestions[selectionIndex]
            input = item.word
        }
        submit()
    }

    @discardableResult
    func cancelSuggestionSelection() -> Bool {
        guard isSuggestionsVisible && hasUserMovedSelection else { return false }
        selectionIndex = 0
        hasUserMovedSelection = false
        return true
    }

    func submit() {
        suggestions = []
        selectionIndex = 0
        hasUserMovedSelection = false
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        state = .streaming("")
        let prompt = PromptBuilder.build(
            text: text,
            dictionaryTemplate: dictTemplate,
            translationTemplate: translTemplate
        )
        let requestMode = prompt.mode
        lastRequestMode = requestMode
        if requestMode == .dictionary {
            parser = StructuredStreamParser()
            dictionaryResult = DictionaryResult()
        }
        task = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            do {
                for try await token in self.service.translate(systemPrompt: prompt.systemPrompt, userText: text) {
                    buffer += token
                    if requestMode == .dictionary {
                        self.dictionaryResult = self.parser.feed(token)
                    }
                    self.state = .streaming(buffer)
                }
                if requestMode == .dictionary {
                    self.dictionaryResult = self.parser.flush()
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
        suggestions = []
        selectionIndex = 0
        hasUserMovedSelection = false
        task?.cancel()
        input = ""
        state = .idle
        parser = StructuredStreamParser()
        dictionaryResult = DictionaryResult()
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
        lastRequestMode = entry.mode
        if entry.mode == .dictionary {
            parser = StructuredStreamParser()
            _ = parser.feed(entry.result)
            dictionaryResult = parser.flush()
        } else {
            dictionaryResult = DictionaryResult()
        }
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
    let onShowPreferences: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        TranslatorShell {
            TranslatorHeaderView(onSettings: onShowPreferences)
            themedDivider
            TranslatorInputView(vm: vm, isFocused: $inputFocused)
            if vm.isSuggestionsVisible {
                themedDivider
                TranslatorSuggestionsView(vm: vm)
            }
            themedDivider
            TranslatorHintsView()
            resultSection
            drawerSection
        }
        .onAppear { inputFocused = true }
    }

    // MARK: - Result section (preserved from previous implementation)

    @ViewBuilder
    private var resultSection: some View {
        switch vm.state {
        case .idle:
            EmptyView()
        case .streaming(let s) where s.isEmpty:
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                ProgressView().controlSize(.small)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }
        case .streaming(let s), .done(let s):
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                ScrollView {
                    Text(LocalizedStringKey(s))
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .frame(maxHeight: 320)
            }
        case .error(let msg):
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                Text("⚠️ \(msg)")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - History drawer section (preserved)

    @ViewBuilder
    private var drawerSection: some View {
        if vm.isDrawerOpen {
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
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
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    private var themedDivider: some View {
        Rectangle()
            .fill(TranslatorTheme.dividerColor)
            .frame(height: 0.5)
    }
}
