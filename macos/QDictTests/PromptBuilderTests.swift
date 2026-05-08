import XCTest
@testable import QDict

final class PromptBuilderTests: XCTestCase {

    // MARK: classify()

    func testClassifySingleEnglishWord() {
        XCTAssertEqual(PromptBuilder.classify("apple"), .dictionary)
    }

    func testClassifyTwoEnglishWords() {
        XCTAssertEqual(PromptBuilder.classify("hot dog"), .dictionary)
    }

    func testClassifyThreeEnglishWords() {
        XCTAssertEqual(PromptBuilder.classify("kick the bucket"), .dictionary)
    }

    func testClassifyFourEnglishWordsIsTranslation() {
        XCTAssertEqual(PromptBuilder.classify("a stitch in time"), .translation)
    }

    func testClassifyEnglishSentenceWithPeriod() {
        XCTAssertEqual(PromptBuilder.classify("Hello, world."), .translation)
    }

    func testClassifyEnglishQuestion() {
        XCTAssertEqual(PromptBuilder.classify("How are you?"), .translation)
    }

    func testClassifyChineseFourCharIdiom() {
        XCTAssertEqual(PromptBuilder.classify("一举两得"), .dictionary)
    }

    func testClassifySingleChineseWord() {
        XCTAssertEqual(PromptBuilder.classify("苹果"), .dictionary)
    }

    func testClassifyChineseSixChars() {
        XCTAssertEqual(PromptBuilder.classify("人工智能技术"), .dictionary)
    }

    func testClassifyChineseSevenCharsIsTranslation() {
        XCTAssertEqual(PromptBuilder.classify("人工智能技术发展"), .translation)
    }

    func testClassifyChineseWithPunctuation() {
        XCTAssertEqual(PromptBuilder.classify("好！"), .translation)
    }

    func testClassifyChineseSentence() {
        // 7 CJK chars without punctuation: above the dictionary threshold (≤6).
        XCTAssertEqual(PromptBuilder.classify("今天天气真不错"), .translation)
    }

    func testClassifyHyphenatedEnglishCountsAsOneWord() {
        XCTAssertEqual(PromptBuilder.classify("co-worker"), .dictionary)
    }

    func testClassifyEmptyStringIsTranslation() {
        XCTAssertEqual(PromptBuilder.classify(""), .translation)
    }

    func testClassifyTrimsWhitespace() {
        XCTAssertEqual(PromptBuilder.classify("   apple   "), .dictionary)
    }

    func testClassifyCollapsesInternalWhitespace() {
        XCTAssertEqual(PromptBuilder.classify("hot   dog"), .dictionary)
    }

    func testClassifyMixedShortIsDictionary() {
        // 3-or-fewer "words" once split
        XCTAssertEqual(PromptBuilder.classify("commit message"), .dictionary)
    }

    func testClassifyDigitsAreTranslation() {
        XCTAssertEqual(PromptBuilder.classify("12345"), .translation)
    }

    // MARK: detectDirection()

    func testDirectionPureEnglish() {
        XCTAssertEqual(PromptBuilder.detectDirection("apple"), .enToZh)
    }

    func testDirectionPureChinese() {
        XCTAssertEqual(PromptBuilder.detectDirection("苹果"), .zhToEn)
    }

    func testDirectionMostlyChineseGoesZhToEn() {
        XCTAssertEqual(PromptBuilder.detectDirection("把这个 commit 翻译一下"), .zhToEn)
    }

    func testDirectionMostlyEnglishWithStrayChineseGoesEnToZh() {
        XCTAssertEqual(PromptBuilder.detectDirection("Please send me the 报告"), .enToZh)
    }

    func testDirectionEmptyStringDefaultsToEnToZh() {
        XCTAssertEqual(PromptBuilder.detectDirection(""), .enToZh)
    }

    // MARK: build()

    func testBuildAssemblesDictionaryPromptForShortInput() {
        let result = PromptBuilder.build(
            text: "apple",
            dictionaryTemplate: "DICT {{direction}}",
            translationTemplate: "TRANS {{direction}}"
        )
        XCTAssertEqual(result.mode, .dictionary)
        XCTAssertEqual(result.direction, .enToZh)
        XCTAssertEqual(result.systemPrompt, "DICT en->zh")
    }

    func testBuildAssemblesTranslationPromptForLongChinese() {
        let result = PromptBuilder.build(
            text: "今天天气真好，我们出去玩吧",
            dictionaryTemplate: "DICT {{direction}}",
            translationTemplate: "TRANS {{direction}}"
        )
        XCTAssertEqual(result.mode, .translation)
        XCTAssertEqual(result.direction, .zhToEn)
        XCTAssertEqual(result.systemPrompt, "TRANS zh->en")
    }
}

extension PromptBuilderTests {
    func testTemplatesAreBundled() throws {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "dictionary", withExtension: "txt"),
            "dictionary.txt must be packaged in the app bundle"
        )
        XCTAssertNotNil(
            Bundle.main.url(forResource: "translation", withExtension: "txt"),
            "translation.txt must be packaged in the app bundle"
        )

        let dict = try PromptBuilder.loadTemplate(named: "dictionary")
        let trans = try PromptBuilder.loadTemplate(named: "translation")
        XCTAssertTrue(dict.contains("{{direction}}"))
        XCTAssertTrue(trans.contains("{{direction}}"))
    }
}
