import AppKit

@MainActor
final class AppContainer {
    let settings: Settings
    let translationService: TranslationService
    let hotKeyManager: HotKeyManager
    let statusBar: StatusBarController
    let translator: TranslatorWindowController
    let dictTemplate: String
    let translTemplate: String

    init() {
        let s = Settings()
        self.settings = s
        self.translationService = TranslationService(settings: s)
        self.hotKeyManager = HotKeyManager()
        self.statusBar = StatusBarController()

        // Load prompt templates from bundle. If missing, the app is broken — fail loudly.
        do {
            self.dictTemplate = try PromptBuilder.loadTemplate(named: "dictionary")
            self.translTemplate = try PromptBuilder.loadTemplate(named: "translation")
        } catch {
            fatalError("Missing prompt templates: \(error)")
        }

        self.translator = TranslatorWindowController(
            service: translationService,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate
        )
    }
}
