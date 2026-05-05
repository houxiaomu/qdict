# Structured Dictionary Result Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dictionary-mode raw Markdown view with a structured, progressively-rendered card backed by a prefix-line LLM output format.

**Architecture:** A pure-value `StructuredStreamParser` consumes streamed tokens line-by-line, producing a `DictionaryResult` model that a new SwiftUI `DictionaryResultView` renders reactively. Translation mode keeps the existing free-form Markdown path. Dictionary prompt is rewritten to emit `PREFIX|||field|||field` records. Old Markdown history entries automatically fall back via an empty-result check.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 13+), XCTest, xcodegen, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-05-05-structured-dictionary-result-design.md`

---

## File Map

**New files:**
- `QDict/Translation/DictionaryResult.swift` — value-type model (DictionaryResult, Sense, Definition, Example)
- `QDict/Translation/StructuredStreamParser.swift` — incremental line scanner
- `QDict/Window/DictionaryResultView.swift` — SwiftUI view (B style)
- `QDictTests/StructuredStreamParserTests.swift` — XCTest unit tests

**Modified files:**
- `QDict/Prompt/Prompts/dictionary.txt` — rewrite for prefix-line output
- `QDict/Window/TranslatorContentView.swift` — add `dictionaryResult`, `lastRequestMode`, parser; fork `resultSection` rendering; update `submit`, `reset`, `loadFromHistory`

---

## Task 1: Add `DictionaryResult` model

**Files:**
- Create: `QDict/Translation/DictionaryResult.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Structured representation of a dictionary lookup, populated incrementally
/// from the LLM's prefix-line output. All fields are optional or empty
/// collections so a partial result during streaming is meaningful.
struct DictionaryResult: Equatable {
    var word: String?
    var ipa: String?
    /// Set when the entry has a single POS (no SENSE blocks). Mutually
    /// exclusive with non-empty `senses` in well-formed input.
    var primaryTranslation: String?
    var primaryPOS: String?
    /// Per-POS blocks. Non-empty for multi-POS words (e.g. "run").
    var senses: [Sense] = []
    /// Definitions for the single-POS path (when `senses` is empty).
    var flatDefinitions: [Definition] = []
    var examples: [Example] = []
    var synonyms: [String] = []
    var usage: String?

    /// True when the parser hasn't extracted any meaningful field. Used by the
    /// view to decide between structured rendering and the legacy fallback.
    var isEmpty: Bool {
        word == nil
            && primaryTranslation == nil
            && senses.isEmpty
            && flatDefinitions.isEmpty
            && examples.isEmpty
            && synonyms.isEmpty
            && usage == nil
    }
}

struct Sense: Equatable {
    let pos: String
    var primary: String?
    var definitions: [Definition]
}

struct Definition: Equatable {
    let n: Int
    let text: String
}

struct Example: Equatable {
    let source: String
    let translation: String
}
```

- [ ] **Step 2: Regenerate Xcode project so the new file is included**

Run: `xcodegen generate`
Expected: `Created project at QDict.xcodeproj`

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -destination 'platform=macOS' build -quiet`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add QDict/Translation/DictionaryResult.swift QDict.xcodeproj
git commit -m "feat(dict): add DictionaryResult value-type model"
```

---

## Task 2: Bootstrap `StructuredStreamParser` with single-field records (TDD)

**Files:**
- Create: `QDict/Translation/StructuredStreamParser.swift`
- Create: `QDictTests/StructuredStreamParserTests.swift`

- [ ] **Step 1: Write the failing test (single-field cases only)**

Create `QDictTests/StructuredStreamParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test -only-testing:QDictTests/StructuredStreamParserTests 2>&1 | tail -30`
Expected: compile error or test failures because `StructuredStreamParser` doesn't exist yet.

- [ ] **Step 3: Write the parser skeleton**

Create `QDict/Translation/StructuredStreamParser.swift`:

```swift
import Foundation

/// Incremental line-scanner for the dictionary prompt's prefix-line output.
///
/// Feed token chunks via `feed(_:)`; the parser splits on `\n`, identifies each
/// complete line by its prefix, and updates the cumulative `result`. Call
/// `flush()` once the stream ends to consume any trailing line without `\n`.
///
/// Pure value type. No locking, no main-actor assumption — callers serialize
/// access however they need.
struct StructuredStreamParser {
    static let separator = "|||"

    private(set) var result = DictionaryResult()
    private var buffer = ""
    private var currentSenseIndex: Int? = nil

    @discardableResult
    mutating func feed(_ chunk: String) -> DictionaryResult {
        buffer += chunk
        while let nlRange = buffer.range(of: "\n") {
            let line = String(buffer[..<nlRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<nlRange.upperBound)
            consume(line: line)
        }
        return result
    }

    @discardableResult
    mutating func flush() -> DictionaryResult {
        if !buffer.isEmpty {
            consume(line: buffer)
            buffer = ""
        }
        return result
    }

    private mutating func consume(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed.components(separatedBy: Self.separator)
        guard parts.count >= 2 else { return }
        let prefix = parts[0]
        switch prefix {
        case "WORD" where parts.count == 2:
            result.word = parts[1]
        case "IPA" where parts.count == 2:
            result.ipa = parts[1]
        case "TRANS" where parts.count == 2:
            result.primaryTranslation = parts[1]
        case "POS" where parts.count == 2:
            result.primaryPOS = parts[1]
        case "USAGE" where parts.count == 2:
            result.usage = parts[1]
        default:
            return
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run tests**

Run: `xcodegen generate && xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test -only-testing:QDictTests/StructuredStreamParserTests 2>&1 | tail -20`
Expected: `Test Suite 'StructuredStreamParserTests' passed` with 5 tests.

- [ ] **Step 5: Commit**

```bash
git add QDict/Translation/StructuredStreamParser.swift QDictTests/StructuredStreamParserTests.swift QDict.xcodeproj
git commit -m "feat(dict): bootstrap StructuredStreamParser with single-field records"
```

---

## Task 3: Add `DEF` and `SYN` parsing (flat / single-POS path)

**Files:**
- Modify: `QDict/Translation/StructuredStreamParser.swift`
- Modify: `QDictTests/StructuredStreamParserTests.swift`

- [ ] **Step 1: Append failing tests**

Add to `StructuredStreamParserTests.swift` inside the class body, before the closing brace:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test -only-testing:QDictTests/StructuredStreamParserTests 2>&1 | tail -20`
Expected: failures (`testFlatDefinitionsAccumulate`, `testSynParsesAndTrims`, etc.).

- [ ] **Step 3: Extend `consume(line:)` switch in StructuredStreamParser.swift**

Replace the `switch prefix { … default: return }` block with:

```swift
        switch prefix {
        case "WORD" where parts.count == 2:
            result.word = parts[1]
        case "IPA" where parts.count == 2:
            result.ipa = parts[1]
        case "TRANS" where parts.count == 2:
            result.primaryTranslation = parts[1]
        case "POS" where parts.count == 2:
            result.primaryPOS = parts[1]
        case "USAGE" where parts.count == 2:
            result.usage = parts[1]
        case "DEF" where parts.count == 3:
            guard let n = Int(parts[1]) else { return }
            let def = Definition(n: n, text: parts[2])
            if let idx = currentSenseIndex {
                result.senses[idx].definitions.append(def)
            } else {
                result.flatDefinitions.append(def)
            }
        case "SYN" where parts.count == 2:
            result.synonyms = parts[1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        default:
            return
        }
```

- [ ] **Step 4: Run tests; expect pass**

Run: same as Step 2.
Expected: `Test Suite 'StructuredStreamParserTests' passed` with 10 tests.

- [ ] **Step 5: Commit**

```bash
git add QDict/Translation/StructuredStreamParser.swift QDictTests/StructuredStreamParserTests.swift
git commit -m "feat(dict): parse DEF (flat) and SYN records"
```

---

## Task 4: Add `EX` and `SENSE` parsing

**Files:**
- Modify: `QDict/Translation/StructuredStreamParser.swift`
- Modify: `QDictTests/StructuredStreamParserTests.swift`

- [ ] **Step 1: Append failing tests**

Add to `StructuredStreamParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests; expect failure**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test -only-testing:QDictTests/StructuredStreamParserTests 2>&1 | tail -20`
Expected: 4 new test failures.

- [ ] **Step 3: Extend `consume(line:)` with EX and SENSE cases**

In the `switch prefix { … }` block, before the `default:` line, insert:

```swift
        case "SENSE" where parts.count == 3:
            result.senses.append(Sense(pos: parts[1], primary: parts[2], definitions: []))
            currentSenseIndex = result.senses.count - 1
        case "EX" where parts.count == 3:
            result.examples.append(Example(source: parts[1], translation: parts[2]))
```

- [ ] **Step 4: Run tests; expect pass**

Run: same as Step 2.
Expected: 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add QDict/Translation/StructuredStreamParser.swift QDictTests/StructuredStreamParserTests.swift
git commit -m "feat(dict): parse EX and SENSE block records"
```

---

## Task 5: Streaming chunk boundaries, `flush()`, and content-with-pipe edge cases

**Files:**
- Modify: `QDictTests/StructuredStreamParserTests.swift`

- [ ] **Step 1: Append failing tests for chunk boundaries and edge cases**

Add to `StructuredStreamParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test -only-testing:QDictTests/StructuredStreamParserTests 2>&1 | tail -25`

Most should pass already. The CRLF case (`testCRLFLineEndings`) may fail if `feed` doesn't strip `\r`. The `trimmingCharacters(in: .whitespacesAndNewlines)` inside `consume` handles it — verify pass.

If any of the 9 new tests fail, fix the parser. (The implementation in Tasks 2–4 should already cover all of these, but we explicitly assert behavior.)

- [ ] **Step 3: Commit**

```bash
git add QDictTests/StructuredStreamParserTests.swift
git commit -m "test(dict): cover streaming chunks, flush, and content edge cases"
```

---

## Task 6: Rewrite `dictionary.txt` prompt

**Files:**
- Modify: `QDict/Prompt/Prompts/dictionary.txt`

- [ ] **Step 1: Replace the file contents**

Overwrite `QDict/Prompt/Prompts/dictionary.txt` with:

```
You output ONLY prefix-line records describing a dictionary entry. No prose, no Markdown, no preamble, no apology, no code fences, no extra blank lines beyond what's shown in the examples.

Direction: {{direction}}

# Format

Each line is one record. Field separator is exactly three pipes: |||

  PREFIX|||field
  PREFIX|||field|||field

# Records

WORD|||<the source word as queried, echoed verbatim>
IPA|||<phonetic, e.g. /ˈæp.əl/>           (omit for Chinese queries)
TRANS|||<single most common translation>  (omit when SENSE blocks are used)
POS|||<part of speech in the target language>  (omit when SENSE blocks are used)
SENSE|||<part of speech>|||<primary translation for this sense>
DEF|||<n>|||<definition text>             (n is 1-based; appears under TRANS or under each SENSE)
EX|||<source sentence>|||<translation>    (2-3 examples total)
SYN|||<comma-separated related words>     (optional, 0-4 entries)
USAGE|||<one short sentence about register or collocation>  (optional)

# Rules

- Single-POS words: emit TRANS, POS, then 1-3 DEF lines.
- Multi-POS words (e.g. "run" as both verb and noun): emit one SENSE per POS with DEF lines under it. Do NOT emit top-level TRANS or POS.
- Always include WORD.
- Always include 2-3 EX lines covering distinct contexts (everyday, work, written/news).
- Skip optional lines (SYN, USAGE, IPA) if you have nothing meaningful to say. Do NOT emit empty values.
- NEVER output any line that does not start with one of: WORD, IPA, TRANS, POS, SENSE, DEF, EX, SYN, USAGE.
- NEVER use single | or double || inside content as a separator — that is fine; only ||| separates fields.

# Examples

## Example 1: simple English noun (apple)

WORD|||apple
IPA|||/ˈæp.əl/
TRANS|||苹果
POS|||名词
DEF|||1|||一种常见、圆形的水果，外皮通常红色、绿色或黄色，果肉白色。
DEF|||2|||专有名词。指 Apple Inc.，美国跨国科技公司，以 iPhone、Mac 等产品闻名。
EX|||She ate a crisp red apple for a snack.|||她吃了一个脆红苹果当点心。
EX|||He works as a software engineer at Apple.|||他在苹果公司担任软件工程师。
SYN|||fruit, orchard, iPhone, Mac

## Example 2: multi-POS English word (run)

WORD|||run
IPA|||/rʌn/
SENSE|||动词|||跑；运行；经营
DEF|||1|||用脚快速移动。
DEF|||2|||使（机器、程序）工作。
DEF|||3|||管理或经营（业务、组织）。
SENSE|||名词|||奔跑；一段时期
DEF|||1|||快速移动的过程。
EX|||She runs every morning.|||她每天早上跑步。
EX|||He runs a small bakery.|||他经营一家小面包店。
USAGE|||"run a business" 是高频搭配。

## Example 3: Chinese-to-English (苹果)

WORD|||苹果
TRANS|||apple
POS|||noun
DEF|||1|||a fruit with red, green, or yellow skin and white flesh.
DEF|||2|||refers to Apple Inc., the US technology company.
EX|||她每天早上吃一个苹果。|||She eats an apple every morning.
EX|||他在苹果公司工作。|||He works at Apple.
SYN|||fruit

## Example 4: English phrase (give up)

WORD|||give up
TRANS|||放弃
POS|||动词短语
DEF|||1|||停止尝试或不再坚持做某事。
DEF|||2|||戒除（习惯，如吸烟、饮酒）。
EX|||Don't give up on your dreams.|||不要放弃你的梦想。
EX|||She gave up smoking last year.|||她去年戒了烟。
USAGE|||常与 "on someone/something" 或 doing 形式搭配。

## Example 5: rare word, no SYN or USAGE (serendipity)

WORD|||serendipity
IPA|||/ˌserənˈdɪpəti/
TRANS|||意外发现的惊喜
POS|||名词
DEF|||1|||偶然之中发现美好或有价值事物的运气与能力，常带积极含义。
EX|||Meeting her was pure serendipity.|||遇见她纯属意外的惊喜。
EX|||The discovery was a moment of serendipity.|||这个发现是个偶然的惊喜时刻。

## Example 6: Chinese idiom (一举两得)

WORD|||一举两得
TRANS|||kill two birds with one stone
POS|||成语
DEF|||1|||一次行动达到两个目的。
EX|||这个方案能一举两得。|||This plan kills two birds with one stone.
USAGE|||书面与口语都常用。

# Final reminder

Output ONLY the lines. Do not wrap in code fences, do not add commentary, do not echo the rules.
```

- [ ] **Step 2: Verify file is still bundled (no project regen needed; resources path unchanged)**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -destination 'platform=macOS' build -quiet`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add QDict/Prompt/Prompts/dictionary.txt
git commit -m "feat(dict): rewrite dictionary prompt to emit prefix-line records"
```

---

## Task 7: Build `DictionaryResultView` (B-style structured card)

**Files:**
- Create: `QDict/Window/DictionaryResultView.swift`

- [ ] **Step 1: Write the view**

Create `QDict/Window/DictionaryResultView.swift`:

```swift
import SwiftUI

struct DictionaryResultView: View {
    let result: DictionaryResult

    private static let labelColor = Color.secondary.opacity(0.7)
    private static let accentColor = Color(red: 0.77, green: 0.47, blue: 0.23)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if result.senses.isEmpty {
                    primaryRow
                    flatDefinitionsBlock
                } else {
                    sensesBlock
                }
                examplesBlock
                synonymsBlock
                usageBlock
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 360)
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerRow: some View {
        if result.word != nil || result.ipa != nil {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let word = result.word {
                    Text(word)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.3)
                }
                if let ipa = result.ipa {
                    Text(ipa)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryRow: some View {
        if let trans = result.primaryTranslation {
            HStack(alignment: .center, spacing: 8) {
                Text(trans)
                    .font(.system(size: 18, weight: .medium))
                if let pos = result.primaryPOS {
                    posPill(pos)
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var flatDefinitionsBlock: some View {
        if !result.flatDefinitions.isEmpty {
            sectionLabel("释义")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(result.flatDefinitions, id: \.n) { def in
                    definitionRow(def)
                }
            }
        }
    }

    @ViewBuilder
    private var sensesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.senses.indices, id: \.self) { i in
                let s = result.senses[i]
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.pos)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Self.accentColor)
                    if let primary = s.primary {
                        Text(primary)
                            .font(.system(size: 16, weight: .medium))
                    }
                    if !s.definitions.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(s.definitions, id: \.n) { def in
                                definitionRow(def)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var examplesBlock: some View {
        if !result.examples.isEmpty {
            sectionLabel("例句")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(result.examples.indices, id: \.self) { i in
                    let e = result.examples[i]
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.source).font(.system(size: 13))
                        Text(e.translation).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var synonymsBlock: some View {
        if !result.synonyms.isEmpty {
            sectionLabel("近义")
            HStack(spacing: 10) {
                ForEach(result.synonyms, id: \.self) { syn in
                    Text(syn).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var usageBlock: some View {
        if let usage = result.usage {
            sectionLabel("用法")
            Text(usage).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func definitionRow(_ def: Definition) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(def.n)")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
            Text(def.text)
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Self.labelColor)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func posPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

#Preview("apple") {
    DictionaryResultView(result: DictionaryResult(
        word: "apple",
        ipa: "/ˈæp.əl/",
        primaryTranslation: "苹果",
        primaryPOS: "名词",
        flatDefinitions: [
            Definition(n: 1, text: "一种常见、圆形的水果，外皮通常红色、绿色或黄色，果肉白色。"),
            Definition(n: 2, text: "专有名词。指 Apple Inc.，美国跨国科技公司。"),
        ],
        examples: [
            Example(source: "She ate a crisp red apple for a snack.", translation: "她吃了一个脆红苹果当点心。"),
            Example(source: "He works as a software engineer at Apple.", translation: "他在苹果公司担任软件工程师。"),
        ],
        synonyms: ["fruit", "orchard", "iPhone", "Mac"]
    ))
    .frame(width: 480)
}

#Preview("run (multi-POS)") {
    DictionaryResultView(result: DictionaryResult(
        word: "run",
        ipa: "/rʌn/",
        senses: [
            Sense(pos: "动词", primary: "跑；运行；经营", definitions: [
                Definition(n: 1, text: "用脚快速移动。"),
                Definition(n: 2, text: "使（机器、程序）工作。"),
                Definition(n: 3, text: "管理或经营。"),
            ]),
            Sense(pos: "名词", primary: "奔跑；一段时期", definitions: [
                Definition(n: 1, text: "快速移动的过程。"),
            ]),
        ],
        examples: [
            Example(source: "She runs every morning.", translation: "她每天早上跑步。"),
            Example(source: "He runs a small bakery.", translation: "他经营一家小面包店。"),
        ],
        usage: "\"run a business\" 是高频搭配。"
    ))
    .frame(width: 480)
}
```

- [ ] **Step 2: Regenerate project and verify build**

Run: `xcodegen generate && xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -destination 'platform=macOS' build -quiet`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add QDict/Window/DictionaryResultView.swift QDict.xcodeproj
git commit -m "feat(dict): add DictionaryResultView with B-style structured layout"
```

---

## Task 8: Wire `TranslatorViewModel` to feed the parser during streaming

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`

- [ ] **Step 1: Add new published state and parser instance**

In `TranslatorContentView.swift`, locate the `@Published` declarations near the top of `TranslatorViewModel` (around line 17–19):

```swift
    @Published var input: String = ""
    @Published var state: State = .idle

    // MARK: - Suggestion dropdown state (M1)
    @Published var suggestions: [SuggestionItem] = []
```

Insert after the `state` line (before the suggestion section):

```swift
    // MARK: - Structured dictionary result (M3)
    @Published private(set) var dictionaryResult: DictionaryResult = DictionaryResult()
    @Published private(set) var lastRequestMode: Mode = .dictionary
    private var parser = StructuredStreamParser()

```

- [ ] **Step 2: Update `submit()` to feed the parser when in dictionary mode**

Replace the existing `submit()` function (currently at roughly lines 108–138) entirely with:

```swift
    func submit() {
        suggestions = []
        selectionIndex = 0
        hasUserMovedSelection = false
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        state = .streaming("")
        let prompt = PromptBuilder.build(
            text: text,
            dictionaryTemplate: dictTemplate,
            translationTemplate: translTemplate
        )
        let requestMode = prompt.mode
        lastRequestMode = requestMode
        if requestMode == .dictionary {
            parser = StructuredStreamParser()
            dictionaryResult = DictionaryResult()
        }
        task = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            do {
                for try await token in self.service.translate(systemPrompt: prompt.systemPrompt, userText: text) {
                    buffer += token
                    if requestMode == .dictionary {
                        self.dictionaryResult = self.parser.feed(token)
                    }
                    self.state = .streaming(buffer)
                }
                if requestMode == .dictionary {
                    self.dictionaryResult = self.parser.flush()
                }
                self.state = .done(buffer)
                self.historyStore?.append(query: text, result: buffer, mode: self.historyMode)
            } catch let e as TranslationError {
                if case .cancelled = e { return } // swallow
                self.state = .error(e.errorDescription ?? "未知错误")
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }
```

- [ ] **Step 3: Update `reset()` to clear dictionary result and parser**

Replace the existing `reset()` function with:

```swift
    func reset() {
        suggestions = []
        selectionIndex = 0
        hasUserMovedSelection = false
        task?.cancel()
        input = ""
        state = .idle
        parser = StructuredStreamParser()
        dictionaryResult = DictionaryResult()
    }
```

- [ ] **Step 4: Update `loadFromHistory(_:)` to populate `dictionaryResult` from raw text**

Replace the existing `loadFromHistory(_:)` function with:

```swift
    /// Replay a history entry without re-calling the API.
    func loadFromHistory(_ entry: HistoryEntry) {
        task?.cancel()
        input = entry.query
        state = .done(entry.result)
        lastRequestMode = entry.mode
        if entry.mode == .dictionary {
            parser = StructuredStreamParser()
            _ = parser.feed(entry.result)
            dictionaryResult = parser.flush()
        } else {
            dictionaryResult = DictionaryResult()
        }
    }
```

- [ ] **Step 5: Build to verify compile**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -destination 'platform=macOS' build -quiet`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift
git commit -m "feat(dict): wire StructuredStreamParser into TranslatorViewModel"
```

---

## Task 9: Fork `resultSection` rendering in `TranslatorContentView`

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`

- [ ] **Step 1: Replace `resultSection` with the forking implementation**

Locate the `@ViewBuilder private var resultSection: some View { … }` block (currently around lines 250–286). Replace the entire block with:

```swift
    @ViewBuilder
    private var resultSection: some View {
        switch vm.state {
        case .idle:
            EmptyView()
        case .streaming(let s) where s.isEmpty:
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                ProgressView().controlSize(.small)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }
        case .streaming(let s), .done(let s):
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                if vm.lastRequestMode == .dictionary && !vm.dictionaryResult.isEmpty {
                    DictionaryResultView(result: vm.dictionaryResult)
                } else if vm.lastRequestMode == .dictionary, case .streaming = vm.state {
                    // Dictionary request still streaming but parser hasn't yielded
                    // any field yet — show spinner instead of raw prefix-line text.
                    ProgressView().controlSize(.small)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                } else {
                    legacyMarkdownView(s)
                }
            }
        case .error(let msg):
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                Text("⚠️ \(msg)")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    private func legacyMarkdownView(_ s: String) -> some View {
        ScrollView {
            Text(LocalizedStringKey(s))
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(maxHeight: 320)
    }
```

- [ ] **Step 2: Build to verify compile**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -destination 'platform=macOS' build -quiet`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run all tests**

Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: all test suites pass (existing + new parser tests).

- [ ] **Step 4: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift
git commit -m "feat(dict): fork resultSection to render structured cards"
```

---

## Task 10: Manual smoke test

**Files:** none modified.

- [ ] **Step 1: Launch the app**

Run:
```
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath build/debug build -quiet \
  && open build/debug/Build/Products/Debug/QDict.app
```

Expected: app launches, status bar icon appears.

- [ ] **Step 2: Walk through the verification matrix**

For each query below, open the app via the global hotkey (or status-bar click), type the input, hit Return, and verify the listed expectation. Failures here mean a bug in the parser, prompt, or view — fix and re-test.

| # | Input | Expected |
|---|---|---|
| 1 | `apple` | Header "apple" + IPA. Below: 苹果 + 名词 pill. 释义 1–2 条. 例句 2 条 (English source, Chinese gloss). 近义 row. Sections appear progressively as tokens stream. |
| 2 | `run` | Header "run" + IPA. Two SENSE blocks (动词 / 名词) each with primary translation + numbered defs. Examples below. No top-level translation row. |
| 3 | `serendipity` | Header + IPA + 苹果-style structure but no 近义 / 用法 sections (just header → primary → 释义 → 例句, then card ends). |
| 4 | `苹果` | Header "苹果" (no IPA). Primary translation is English. Defs/examples may be in mixed languages (Chinese source, English gloss). |
| 5 | `give up` | Header "give up" (no IPA). 动词短语 pill. Defs + examples. |
| 6 | A long English sentence (e.g. `The quick brown fox jumps over the lazy dog.`) | Falls back to legacy Markdown view (translation mode). No structured card. |
| 7 | Open History drawer (⌘↑) and click an old entry created before this change | If it was a dictionary entry in old Markdown format, it should fall back to legacy Markdown view. New-format entries render as structured. |

- [ ] **Step 3: Note any visual issues**

If the layout looks off (overflow, awkward spacing, font weights wrong), record the case and fix in `DictionaryResultView.swift`. Re-run.

- [ ] **Step 4: Commit any fixes**

```bash
git add QDict/Window/DictionaryResultView.swift
git commit -m "fix(dict): polish structured card layout from manual QA"
```

(Skip this commit if no issues were found.)

---

## Final verification

- [ ] **All tests pass:**
  Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -destination 'platform=macOS' test 2>&1 | tail -10`
  Expected: `** TEST SUCCEEDED **`

- [ ] **Build clean:**
  Run: `xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -destination 'platform=macOS' build -quiet`
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Manual matrix complete:** all 7 cases in Task 10 verified.

- [ ] **No new TODO/FIXME left in modified files:**
  Run: `git diff main -- QDict/ QDictTests/ | grep -iE "TODO|FIXME"`
  Expected: empty.
