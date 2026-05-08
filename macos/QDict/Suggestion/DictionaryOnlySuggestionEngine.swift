import Foundation

/// Milestone 1 implementation: forwards prefix queries to the local
/// dictionary and wraps results as ``SuggestionItem``. Milestone 2 will
/// add history merging in a different concrete engine.
struct DictionaryOnlySuggestionEngine: SuggestionEngine {
    let dict: LocalDictionary

    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        dict.prefix(prefix, limit: limit).map { e in
            SuggestionItem(
                id: e.word.lowercased(),
                kind: .dictionary,
                word: e.word,
                pos: e.pos,
                gloss: e.gloss,
                badge: .none
            )
        }
    }
}
