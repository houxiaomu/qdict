import Foundation

/// A single row in the suggestion dropdown. M1 emits only ``.dictionary``
/// items with ``.none`` badge; M2 will introduce ``.history`` and ``.recent``.
struct SuggestionItem: Identifiable, Equatable {
    enum Kind: Equatable { case dictionary, history }
    enum Badge: Equatable { case none, recent }

    let id: String          // == word.lowercased(), used for de-dup in M2
    let kind: Kind
    let word: String        // display form
    let pos: String?
    let gloss: String
    let badge: Badge
}
