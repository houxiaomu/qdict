import XCTest
@testable import QDict

final class SuggestionItemTests: XCTestCase {
    func testEqualityAndIdentity() {
        let a = SuggestionItem(
            id: "epi", kind: .dictionary,
            word: "epi", pos: "n.", gloss: "abc", badge: .none
        )
        let b = SuggestionItem(
            id: "epi", kind: .dictionary,
            word: "epi", pos: "n.", gloss: "abc", badge: .none
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, "epi")
    }

    func testKindAndBadgeCases() {
        XCTAssertNotEqual(SuggestionItem.Kind.dictionary, SuggestionItem.Kind.history)
        XCTAssertNotEqual(SuggestionItem.Badge.none, SuggestionItem.Badge.recent)
    }
}
