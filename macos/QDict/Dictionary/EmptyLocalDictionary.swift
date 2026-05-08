import Foundation

/// Used when the bundled SQLite cannot be opened; degrades QDict to its
/// pre-suggestion behavior (no dropdown, no error UI).
struct EmptyLocalDictionary: LocalDictionary {
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry] { [] }
}
