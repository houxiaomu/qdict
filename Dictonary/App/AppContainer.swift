import AppKit
import Combine

@MainActor
final class AppContainer {
    let settings: Settings
    let translationService: TranslationService
    let hotKeyManager: HotKeyManager
    let statusBar: StatusBarController
    let translator: TranslatorWindowController
    let historyStore: HistoryStore
    let dictTemplate: String
    let translTemplate: String
    private var cancellables = Set<AnyCancellable>()

    init() {
        let s = Settings()
        self.settings = s
        self.translationService = TranslationService()
        self.hotKeyManager = HotKeyManager()
        self.statusBar = StatusBarController()

        do {
            self.dictTemplate = try PromptBuilder.loadTemplate(named: "dictionary")
            self.translTemplate = try PromptBuilder.loadTemplate(named: "translation")
        } catch {
            fatalError("Missing prompt templates: \(error)")
        }

        let url = (try? HistoryStore.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: url, limit: s.historyLimit)
        self.historyStore = store

        self.translator = TranslatorWindowController(
            service: translationService,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate,
            historyStore: store
        )

        s.$historyLimit
            .dropFirst() // skip the initial replay; we already used the value above.
            .sink { [weak store] newLimit in
                Task { @MainActor in store?.setLimit(newLimit) }
            }
            .store(in: &cancellables)
    }
}
