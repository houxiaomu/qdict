import XCTest
@testable import QDict

final class DictionaryEntryTests: XCTestCase {
    func testEqualityRequiresAllFieldsToMatch() {
        let a = DictionaryEntry(word: "epi", pos: "n.", gloss: "abc", cocaRank: 100)
        let b = DictionaryEntry(word: "epi", pos: "n.", gloss: "abc", cocaRank: 100)
        XCTAssertEqual(a, b)
    }

    func testEqualityDistinguishesByCocaRank() {
        let a = DictionaryEntry(word: "epi", pos: "n.", gloss: "abc", cocaRank: 100)
        let b = DictionaryEntry(word: "epi", pos: "n.", gloss: "abc", cocaRank: 200)
        XCTAssertNotEqual(a, b)
    }
}
