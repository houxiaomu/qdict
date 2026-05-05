import XCTest
@testable import QDict

final class StructuredStreamParserTests: XCTestCase {

    // MARK: Single-field records

    func testWordRecord() {
        var p = StructuredStreamParser()
        let r = p.feed("WORD|||apple\n")
        XCTAssertEqual(r.word, "apple")
    }

    func testIPARecord() {
        var p = StructuredStreamParser()
        let r = p.feed("IPA|||/ˈæp.əl/\n")
        XCTAssertEqual(r.ipa, "/ˈæp.əl/")
    }

    func testTransAndPOS() {
        var p = StructuredStreamParser()
        var r = p.feed("TRANS|||苹果\n")
        XCTAssertEqual(r.primaryTranslation, "苹果")
        r = p.feed("POS|||名词\n")
        XCTAssertEqual(r.primaryPOS, "名词")
    }

    func testUsageRecord() {
        var p = StructuredStreamParser()
        let r = p.feed("USAGE|||常与 fresh 搭配\n")
        XCTAssertEqual(r.usage, "常与 fresh 搭配")
    }

    func testEmptyInputProducesEmptyResult() {
        var p = StructuredStreamParser()
        let r = p.feed("")
        XCTAssertTrue(r.isEmpty)
    }
}
