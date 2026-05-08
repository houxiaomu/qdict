import Foundation

struct DictionaryEntry: Equatable {
    let word: String       // display form (original case)
    let pos: String?       // shortened part-of-speech, e.g. "n." / "adj."; nil if missing
    let gloss: String      // single-line CN definition, already truncated
    let cocaRank: Int      // smaller = more common; missing entries use .max
}
