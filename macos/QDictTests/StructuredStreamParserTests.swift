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

    // MARK: DEF in flat mode

    func testFlatDefinitionsAccumulate() {
        var p = StructuredStreamParser()
        var r = p.feed("DEF|||1|||一种水果。\n")
        r = p.feed("DEF|||2|||专有名词。\n")
        XCTAssertEqual(r.flatDefinitions, [
            Definition(n: 1, text: "一种水果。"),
            Definition(n: 2, text: "专有名词。"),
        ])
        XCTAssertTrue(r.senses.isEmpty)
    }

    func testDefWithNonIntegerNIsDropped() {
        var p = StructuredStreamParser()
        let r = p.feed("DEF|||abc|||text\n")
        XCTAssertTrue(r.flatDefinitions.isEmpty)
    }

    func testDefWithWrongFieldCountIsDropped() {
        var p = StructuredStreamParser()
        let r = p.feed("DEF|||only-one-field\n")
        XCTAssertTrue(r.flatDefinitions.isEmpty)
    }

    // MARK: SYN

    func testSynParsesAndTrims() {
        var p = StructuredStreamParser()
        let r = p.feed("SYN|||fruit, orchard ,iPhone, Mac\n")
        XCTAssertEqual(r.synonyms, ["fruit", "orchard", "iPhone", "Mac"])
    }

    func testSynEmptyEntriesFiltered() {
        var p = StructuredStreamParser()
        let r = p.feed("SYN|||fruit, , orchard\n")
        XCTAssertEqual(r.synonyms, ["fruit", "orchard"])
    }

    // MARK: EX

    func testExamplesAccumulate() {
        var p = StructuredStreamParser()
        var r = p.feed("EX|||She runs.|||她在跑。\n")
        r = p.feed("EX|||He runs a shop.|||他经营一家店。\n")
        XCTAssertEqual(r.examples, [
            Example(source: "She runs.", translation: "她在跑。"),
            Example(source: "He runs a shop.", translation: "他经营一家店。"),
        ])
    }

    func testExWithWrongFieldCountIsDropped() {
        var p = StructuredStreamParser()
        let r = p.feed("EX|||only-source\n")
        XCTAssertTrue(r.examples.isEmpty)
    }

    // MARK: SENSE blocks (multi-POS)

    func testSenseStartsBlockAndDefsGoUnderIt() {
        var p = StructuredStreamParser()
        var r = p.feed("SENSE|||动词|||跑\n")
        r = p.feed("DEF|||1|||用脚移动。\n")
        r = p.feed("DEF|||2|||运行。\n")
        XCTAssertEqual(r.senses.count, 1)
        XCTAssertEqual(r.senses[0].pos, "动词")
        XCTAssertEqual(r.senses[0].primary, "跑")
        XCTAssertEqual(r.senses[0].definitions, [
            Definition(n: 1, text: "用脚移动。"),
            Definition(n: 2, text: "运行。"),
        ])
        XCTAssertTrue(r.flatDefinitions.isEmpty)
    }

    func testSecondSenseRedirectsSubsequentDefs() {
        var p = StructuredStreamParser()
        var r = p.feed("SENSE|||动词|||跑\n")
        r = p.feed("DEF|||1|||A\n")
        r = p.feed("SENSE|||名词|||奔跑\n")
        r = p.feed("DEF|||1|||B\n")
        XCTAssertEqual(r.senses.count, 2)
        XCTAssertEqual(r.senses[0].definitions.map(\.text), ["A"])
        XCTAssertEqual(r.senses[1].definitions.map(\.text), ["B"])
    }

    // MARK: Streaming chunk handling

    func testInputSplitAcrossChunksProducesSameResult() {
        let full = "WORD|||apple\nTRANS|||苹果\nPOS|||名词\nDEF|||1|||一种水果。\n"
        var oneShot = StructuredStreamParser()
        let expected = oneShot.feed(full)

        var byteByByte = StructuredStreamParser()
        for ch in full {
            _ = byteByByte.feed(String(ch))
        }
        XCTAssertEqual(byteByByte.result, expected)
    }

    func testFlushHandlesTrailingLineWithoutNewline() {
        var p = StructuredStreamParser()
        _ = p.feed("WORD|||apple\nTRANS|||苹果")  // no trailing \n
        XCTAssertNil(p.result.primaryTranslation)  // not yet consumed
        let r = p.flush()
        XCTAssertEqual(r.primaryTranslation, "苹果")
    }

    func testFlushOnEmptyBufferIsNoop() {
        var p = StructuredStreamParser()
        _ = p.feed("WORD|||apple\n")
        let before = p.result
        let after = p.flush()
        XCTAssertEqual(after, before)
    }

    // MARK: Content with single | or || (must NOT be treated as separator)

    func testDefinitionContainingSinglePipePreserved() {
        var p = StructuredStreamParser()
        let r = p.feed("DEF|||1|||a | b is an OR\n")
        XCTAssertEqual(r.flatDefinitions, [Definition(n: 1, text: "a | b is an OR")])
    }

    func testExampleContainingDoublePipePreserved() {
        var p = StructuredStreamParser()
        let r = p.feed("EX|||x || y means alternative.|||x 或 y。\n")
        XCTAssertEqual(r.examples, [
            Example(source: "x || y means alternative.", translation: "x 或 y。")
        ])
    }

    // MARK: Robustness — unknown / malformed lines

    func testUnknownPrefixIsDropped() {
        var p = StructuredStreamParser()
        let r = p.feed("FOO|||bar\nWORD|||apple\n")
        XCTAssertEqual(r.word, "apple")
    }

    func testLineWithNoSeparatorIsDropped() {
        var p = StructuredStreamParser()
        let r = p.feed("Here is some prose without a separator.\nWORD|||apple\n")
        XCTAssertEqual(r.word, "apple")
    }

    func testBlankLinesIgnored() {
        var p = StructuredStreamParser()
        let r = p.feed("\n\nWORD|||apple\n\n\n")
        XCTAssertEqual(r.word, "apple")
    }

    func testCRLFLineEndings() {
        var p = StructuredStreamParser()
        let r = p.feed("WORD|||apple\r\nTRANS|||苹果\r\n")
        XCTAssertEqual(r.word, "apple")
        XCTAssertEqual(r.primaryTranslation, "苹果")
    }

    // MARK: End-to-end — full apple input

    func testFullAppleInput() {
        var p = StructuredStreamParser()
        let input = """
        WORD|||apple
        IPA|||/ˈæp.əl/
        TRANS|||苹果
        POS|||名词
        DEF|||1|||一种常见、圆形的水果，外皮通常红色、绿色或黄色，果肉白色。
        DEF|||2|||专有名词。指 Apple Inc.，美国跨国科技公司。
        EX|||She ate a crisp red apple for a snack.|||她吃了一个脆红苹果当点心。
        EX|||He works as a software engineer at Apple.|||他在苹果公司担任软件工程师。
        SYN|||fruit, orchard, iPhone, Mac

        """
        let r = p.feed(input)
        XCTAssertEqual(r.word, "apple")
        XCTAssertEqual(r.ipa, "/ˈæp.əl/")
        XCTAssertEqual(r.primaryTranslation, "苹果")
        XCTAssertEqual(r.primaryPOS, "名词")
        XCTAssertEqual(r.flatDefinitions.count, 2)
        XCTAssertEqual(r.examples.count, 2)
        XCTAssertEqual(r.synonyms, ["fruit", "orchard", "iPhone", "Mac"])
        XCTAssertTrue(r.senses.isEmpty)
    }
}
