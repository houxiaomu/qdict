import Foundation

/// Read-only English dictionary used by the suggestion dropdown.
///
/// Implementations must be safe to call from the main actor; queries should
/// be cheap (target: < 1 ms) since they fire on every keystroke.
protocol LocalDictionary {
    /// Return entries whose lowercased word starts with `prefix.lowercased()`,
    /// sorted by COCA rank ascending (most common first), capped at `limit`.
    /// Inputs longer than 32 bytes are truncated by the implementation.
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry]
}
