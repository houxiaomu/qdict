import Foundation

/// Milestone 2 engine: merges local-dictionary prefix hits with the user's
/// recent query history, marking same-word matches with a "recent" badge
/// and surfacing history-only hits (words not in the dict) as their own
/// kind. Final ranking and ``limit`` enforcement are layered on top in a
/// follow-up step.
///
/// Not ``@MainActor`` — the engine is a value type called synchronously
/// from ``TranslatorViewModel`` (which *is* main-actor isolated). Accessing
/// the main-actor ``HistoryStore.entries`` is funnelled through the
/// ``historySnapshot`` closure provided at wiring time; that closure is
/// expected to be invoked on the main thread, where ``MainActor.assumeIsolated``
/// can read the published array safely.
struct MergedSuggestionEngine: SuggestionEngine {
    let dict: LocalDictionary
    let historySnapshot: () -> [HistoryEntry]
    let now: () -> Date

    init(
        dict: LocalDictionary,
        historySnapshot: @escaping () -> [HistoryEntry],
        now: @escaping () -> Date = Date.init
    ) {
        self.dict = dict
        self.historySnapshot = historySnapshot
        self.now = now
    }

    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        let lowerPrefix = prefix.lowercased()
        guard !lowerPrefix.isEmpty else { return [] }

        let dictHits = dict.prefix(prefix, limit: limit + 4)

        var historyByLower: [String: HistoryEntry] = [:]
        for entry in historySnapshot() {
            let lower = entry.query.lowercased()
            guard lower.hasPrefix(lowerPrefix) else { continue }
            if let existing = historyByLower[lower], existing.timestamp >= entry.timestamp {
                continue
            }
            historyByLower[lower] = entry
        }

        var items: [SuggestionItem] = []
        var seenLower = Set<String>()

        for e in dictHits {
            let lower = e.word.lowercased()
            seenLower.insert(lower)
            let isRecent = historyByLower[lower] != nil
            items.append(SuggestionItem(
                id: lower,
                kind: .dictionary,
                word: e.word,
                pos: e.pos,
                gloss: e.gloss,
                badge: isRecent ? .recent : .none
            ))
        }

        for (lower, entry) in historyByLower where !seenLower.contains(lower) {
            items.append(SuggestionItem(
                id: lower,
                kind: .history,
                word: entry.query,
                pos: nil,
                gloss: "",
                badge: .recent
            ))
        }

        return items
    }
}
