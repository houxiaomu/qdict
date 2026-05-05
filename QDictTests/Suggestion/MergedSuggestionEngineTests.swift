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
