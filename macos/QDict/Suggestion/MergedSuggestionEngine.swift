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

        // Final score: dict-frequency component plus a recency bonus that
        // decays with a 7-day half-life (see spec §6.3). The α coefficient
        // is calibrated so a today-fresh history hit can lift a mid-frequency
        // word ahead of a top-tier dict word.
        struct Scored {
            let item: SuggestionItem
            let score: Double
        }

        let nowDate = now()

        func dictScore(forCocaRank coca: Int) -> Double {
            let clamped = min(coca, 10000)
            return Double(10000 - clamped) / 1000.0
        }
        func historyBonus(daysSince days: Double) -> Double {
            return 5.0 * exp(-days / 7.0)
        }

        var scored: [Scored] = []
        var seenLower = Set<String>()

        for e in dictHits {
            let lower = e.word.lowercased()
            seenLower.insert(lower)
            let recentEntry = historyByLower[lower]
            let bonus: Double
            if let entry = recentEntry {
                let days = nowDate.timeIntervalSince(entry.timestamp) / 86400.0
                bonus = historyBonus(daysSince: max(0, days))
            } else {
                bonus = 0
            }
            let item = SuggestionItem(
                id: lower,
                kind: .dictionary,
                word: e.word,
                pos: e.pos,
                gloss: e.gloss,
                badge: recentEntry == nil ? .none : .recent
            )
            scored.append(Scored(item: item, score: dictScore(forCocaRank: e.cocaRank) + bonus))
        }

        for (lower, entry) in historyByLower where !seenLower.contains(lower) {
            let days = nowDate.timeIntervalSince(entry.timestamp) / 86400.0
            let item = SuggestionItem(
                id: lower,
                kind: .history,
                word: entry.query,
                pos: nil,
                gloss: "",
                badge: .recent
            )
            scored.append(Scored(item: item, score: historyBonus(daysSince: max(0, days))))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.item)
    }
}
