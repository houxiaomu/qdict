import XCTest
@testable import QDict

final class EmptyLocalDictionaryTests: XCTestCase {
    func testAlwaysReturnsEmpty() {
        let dict: LocalDictionary = EmptyLocalDictionary()
        XCTAssertEqual(dict.prefix("epi", limit: 6), [])
        XCTAssertEqual(dict.prefix("", limit: 6), [])
        XCTAssertEqual(dict.prefix("zzzzzzz", limit: 100), [])
    }
}
