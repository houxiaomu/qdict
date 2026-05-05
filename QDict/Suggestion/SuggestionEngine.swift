import Foundation

/// Single entry point through which the UI obtains dropdown suggestions.
/// The view layer never accesses ``LocalDictionary`` or ``HistoryStore``
/// directly — that decision lives here.
protocol SuggestionEngine {
    /// Best-effort, synchronous, < 1 ms. Caller is responsible for short-circuit
    /// rules (length, ASCII, idle-state, etc.); see TranslatorViewModel.
    func query(_ prefix: String, limit: Int) -> [SuggestionItem]
}
