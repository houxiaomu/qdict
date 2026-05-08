import XCTest
@testable import QDict

private struct StubDictionary: LocalDictionary {
    let entries: [DictionaryEntry]
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry] {
        entries.filter { $0.word.lowercased().hasPrefix(s.lowercased()) }
            .prefix(limit).map { $0 }
    }
}

private func he(_ q: String, daysAgo: Double, now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> HistoryEntry {
    HistoryEntry(
        query: q,
        result: "irrelevant",
        timestamp: now.addingTimeInterval(-daysAgo * 86400),
        mode: .dictionary
    )
}

final class MergedSuggestionEngineMergingTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine(
        dict: [DictionaryEntry] = [],
        history: [HistoryEntry] = []
    ) -> MergedSuggestionEngine {
        MergedSuggestionEngine(
            dict: StubDictionary(entries: dict),
            historySnapshot: { history },
            now: { self.fixedNow }
        )
    }

    func testDictAndHistoryHitMergesIntoSingleDictionaryItemWithRecentBadge() {
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic", pos: "adj.", gloss: "宏大的", cocaRank: 100),
            ],
            history: [
                he("epic", daysAgo: 1, now: fixedNow),
            ]
        )
        let items = engine.query("epi", limit: 10)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "epic")
        XCTAssertEqual(items[0].kind, .dictionary)
        XCTAssertEqual(items[0].badge, .recent)
        XCTAssertEqual(items[0].word, "epic")
    }

    func testHistoryOnlyHitProducesHistoryKindWithRecentBadge() {
        let engine = makeEngine(
            dict: [],
            history: [he("epiphany", daysAgo: 1, now: fixedNow)]
        )
        let items = engine.query("epi", limit: 10)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "epiphany")
        XCTAssertEqual(items[0].kind, .history)
        XCTAssertEqual(items[0].badge, .recent)
    }

    func testDictOnlyHitProducesDictionaryKindWithNoBadge() {
        let engine = makeEngine(
            dict: [DictionaryEntry(word: "episode", pos: "n.", gloss: "插曲", cocaRank: 300)],
            history: []
        )
        let items = engine.query("epi", limit: 10)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "episode")
        XCTAssertEqual(items[0].kind, .dictionary)
        XCTAssertEqual(items[0].badge, .none)
    }

    func testHistoryMatchIsCaseInsensitive() {
        let engine = makeEngine(
            history: [he("Epitome", daysAgo: 1, now: fixedNow)]
        )
        let items = engine.query("epi", limit: 10)
        XCTAssertEqual(items.first?.id, "epitome")
        XCTAssertEqual(items.first?.word, "Epitome")
    }

    func testHistoryEntryWithoutMatchingPrefixIsIgnored() {
        let engine = makeEngine(
            dict: [DictionaryEntry(word: "epic", pos: nil, gloss: "g", cocaRank: 100)],
            history: [he("apple", daysAgo: 1, now: fixedNow)]
        )
        let items = engine.query("epi", limit: 10)
        XCTAssertEqual(items.map(\.word), ["epic"])
    }

    func testDuplicateHistoryEntriesForSameWordCollapseToOneItem() {
        let engine = makeEngine(
            history: [
                he("epic", daysAgo: 5, now: fixedNow),
                he("epic", daysAgo: 1, now: fixedNow),
                he("epic", daysAgo: 30, now: fixedNow),
            ]
        )
        let items = engine.query("epi", limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "epic")
    }

    func testEmptyHistoryDegradesToDictOnlyBehavior() {
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic", pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epitome", pos: nil, gloss: "g", cocaRank: 4000),
            ],
            history: []
        )
        let items = engine.query("epi", limit: 10).map(\.word).sorted()
        XCTAssertEqual(items, ["epic", "epitome"])
        let allBadges = engine.query("epi", limit: 10).map(\.badge)
        XCTAssertTrue(allBadges.allSatisfy { $0 == .none })
    }

    func testHistoryDisplayUsesHistoryQueryWhenDictMissesIt() {
        let engine = makeEngine(
            history: [he("Epiphany", daysAgo: 1, now: fixedNow)]
        )
        let items = engine.query("epi", limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "epiphany")
        XCTAssertEqual(items[0].word, "Epiphany")
    }
}

final class MergedSuggestionEngineScoringTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine(
        dict: [DictionaryEntry] = [],
        history: [HistoryEntry] = []
    ) -> MergedSuggestionEngine {
        MergedSuggestionEngine(
            dict: StubDictionary(entries: dict),
            historySnapshot: { history },
            now: { self.fixedNow }
        )
    }

    func testTodaysHistoryHitClimbsAheadOfMoreCommonDictWord() {
        // "epic" is more common (coca=100, dictScore≈9.99); "epitome" is rarer
        // (coca=4000, dictScore≈6.0). With a today bonus (+5.0), "epitome"
        // should outrank "epic".
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic",    pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epitome", pos: nil, gloss: "g", cocaRank: 4000),
            ],
            history: [he("epitome", daysAgo: 0, now: fixedNow)]
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order.first, "epitome")
        XCTAssertEqual(order.dropFirst().first, "epic")
    }

    func testTwoWeekOldHistoryAlmostStopsBoosting() {
        // 14 days ago: bonus ≈ 5 * exp(-2) ≈ 0.68. "epic" (dictScore≈9.99)
        // should still beat "epitome" (dictScore≈6.0 + 0.68 = 6.68).
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic",    pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epitome", pos: nil, gloss: "g", cocaRank: 4000),
            ],
            history: [he("epitome", daysAgo: 14, now: fixedNow)]
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order.first, "epic")
    }

    func testHistoryOnlyHitOutranksLowFrequencyDictWord() {
        // History-only word has dictScore = 0 (cocaRank treated as missing,
        // which scores at 0..1 range), but a today bonus pushes it ahead of
        // a long-tail dict word.
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epitomize", pos: nil, gloss: "g", cocaRank: 12000),
            ],
            history: [he("epiphany", daysAgo: 0, now: fixedNow)]
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order.first, "epiphany")
        XCTAssertEqual(order.dropFirst().first, "epitomize")
    }

    func testLimitIsAppliedToFinalSortedSet() {
        let dict = (0..<8).map { i in
            DictionaryEntry(word: "epi\(i)", pos: nil, gloss: "g", cocaRank: 100 + i * 10)
        }
        let engine = makeEngine(dict: dict, history: [])
        XCTAssertEqual(engine.query("epi", limit: 3).count, 3)
    }

    func testDictHitsAndHistoryOnlyHitsCompeteForTheSameLimit() {
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic",    pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epidemic", pos: nil, gloss: "g", cocaRank: 4000),
                DictionaryEntry(word: "epilogue", pos: nil, gloss: "g", cocaRank: 8000),
            ],
            history: [
                he("epiphany", daysAgo: 0, now: fixedNow),  // history-only, +5 bonus
                he("epitome", daysAgo: 30, now: fixedNow),  // history-only, ~0 bonus
            ]
        )
        // Limit 3: rankings (approx) — epic 9.99, epiphany 5.0, epidemic 6.0,
        // epilogue 2.0, epitome ≈ 0 + 0.07 ≈ 0.07.
        // So top 3 should be: epic, epidemic, epiphany (in that score order).
        let top3 = engine.query("epi", limit: 3).map(\.word)
        XCTAssertEqual(top3, ["epic", "epidemic", "epiphany"])
    }

    func testCocaRankAtMaxIntScoresAsUnranked() {
        // Sanity: a dict entry with cocaRank == .max (i.e. unranked, our
        // standard sentinel) must not produce a NaN/overflowing dictScore.
        let engine = makeEngine(
            dict: [DictionaryEntry(word: "epic", pos: nil, gloss: "g", cocaRank: .max)],
            history: []
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order, ["epic"])
    }
}
