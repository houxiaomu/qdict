import XCTest
@testable import QDict

private struct StubDictionary: LocalDictionary {
    let entries: [DictionaryEntry]
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry] {
        Array(entries.prefix(limit))
    }
}

final class DictionaryOnlySuggestionEngineTests: XCTestCase {
    func testProducesSuggestionItemsFromDictionary() {
        let dict = StubDictionary(entries: [
            DictionaryEntry(word: "Epic",     pos: "adj.", gloss: "宏大的",  cocaRank: 100),
            DictionaryEntry(word: "epitome",  pos: "n.",   gloss: "缩影",   cocaRank: 4000),
        ])
        let engine = DictionaryOnlySuggestionEngine(dict: dict)
        let items = engine.query("epi", limit: 6)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, "epic")            // lowercased(word)
        XCTAssertEqual(items[0].word, "Epic")          // display preserved
        XCTAssertEqual(items[0].kind, .dictionary)
        XCTAssertEqual(items[0].badge, .none)
        XCTAssertEqual(items[0].pos, "adj.")
        XCTAssertEqual(items[0].gloss, "宏大的")
    }

    func testHonorsLimit() {
        let dict = StubDictionary(entries: (0..<10).map {
            DictionaryEntry(word: "w\($0)", pos: nil, gloss: "g", cocaRank: $0)
        })
        let engine = DictionaryOnlySuggestionEngine(dict: dict)
        XCTAssertEqual(engine.query("w", limit: 3).count, 3)
    }

    func testEmptyDictionaryProducesEmpty() {
        let engine = DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())
        XCTAssertEqual(engine.query("anything", limit: 6), [])
    }
}
