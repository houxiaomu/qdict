import Foundation

/// Structured representation of a dictionary lookup, populated incrementally
/// from the LLM's prefix-line output. All fields are optional or empty
/// collections so a partial result during streaming is meaningful.
struct DictionaryResult: Equatable {
    var word: String?
    var ipa: String?
    /// Set when the entry has a single POS (no SENSE blocks). Mutually
    /// exclusive with non-empty `senses` in well-formed input.
    var primaryTranslation: String?
    var primaryPOS: String?
    /// Per-POS blocks. Non-empty for multi-POS words (e.g. "run").
    var senses: [Sense] = []
    /// Definitions for the single-POS path (when `senses` is empty).
    var flatDefinitions: [Definition] = []
    var examples: [Example] = []
    var synonyms: [String] = []
    var usage: String?

    /// True when the parser hasn't extracted any meaningful field. Used by the
    /// view to decide between structured rendering and the legacy fallback.
    var isEmpty: Bool {
        word == nil
            && primaryTranslation == nil
            && senses.isEmpty
            && flatDefinitions.isEmpty
            && examples.isEmpty
            && synonyms.isEmpty
            && usage == nil
    }
}

struct Sense: Equatable {
    let pos: String
    var primary: String?
    var definitions: [Definition]
}

struct Definition: Equatable {
    let n: Int
    let text: String
}

struct Example: Equatable {
    let source: String
    let translation: String
}
