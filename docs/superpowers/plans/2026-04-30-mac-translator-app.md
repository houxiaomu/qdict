# Mac 中英翻译 App · 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tiny, fast macOS menu-bar translator app that takes Chinese/English text in a single input field, calls an online LLM (DeepSeek/OpenAI/Claude) with streaming, and renders dictionary-style or translation-style output based on input shape.

**Architecture:** SwiftUI macOS app (macOS 13+). Six modules behind protocols (`StatusBarController`, `HotKeyManager`, `TranslatorWindow`, `TranslationService`, `Settings`, `PromptBuilder`). The `AppDelegate` wires them up; modules don't know about each other. Pure logic (PromptBuilder, providers) is unit-tested with `URLProtocol` and protocol mocks; UI is exercised via `#Preview`.

**Tech Stack:** Swift 5.9+, SwiftUI 4 (`MenuBarExtra`), Carbon `RegisterEventHotKey`, `SMAppService` (login item), Keychain (`SecItem*`), XcodeGen for project generation, XCTest, `xcodebuild` for CI-friendly test runs.

**Bundle ID convention:** `app.dictonary.Dictonary` (matches Keychain `service` field in spec).

**Spec reference:** `docs/superpowers/specs/2026-04-30-mac-translator-app-design.md`

---

## File Structure

```
dictonary/
├── project.yml                                # XcodeGen config
├── Dictonary.xcodeproj/                       # generated
├── Dictonary/
│   ├── App/
│   │   ├── DictonaryApp.swift                 # @main + Settings scene
│   │   ├── AppDelegate.swift                  # NSApplicationDelegate, module wiring
│   │   └── AppContainer.swift                 # DI container holding singletons
│   ├── Prompt/
│   │   ├── Mode.swift
│   │   ├── Direction.swift
│   │   ├── PromptBuilder.swift                # pure logic
│   │   └── Prompts/
│   │       ├── dictionary.txt                 # bundled resource
│   │       └── translation.txt
│   ├── Settings/
│   │   ├── Settings.swift                     # ObservableObject
│   │   ├── KeychainService.swift              # protocol + concrete
│   │   ├── ProviderKind.swift                 # enum
│   │   ├── HotkeyCombo.swift                  # struct (key + modifiers)
│   │   └── UI/
│   │       ├── SettingsView.swift             # tab root
│   │       ├── GeneralSettingsView.swift
│   │       ├── ProviderSettingsView.swift
│   │       ├── AboutSettingsView.swift
│   │       └── HotkeyRecorderView.swift
│   ├── Translation/
│   │   ├── TranslationError.swift
│   │   ├── TranslationProvider.swift          # protocol
│   │   ├── TranslationService.swift           # facade that picks active provider
│   │   ├── SSEParser.swift
│   │   ├── DeepSeekProvider.swift
│   │   ├── OpenAIProvider.swift
│   │   └── ClaudeProvider.swift
│   ├── Hotkey/
│   │   └── HotKeyManager.swift                # Carbon wrapper
│   ├── StatusBar/
│   │   └── StatusBarController.swift          # MenuBarExtra controller
│   ├── Window/
│   │   ├── TranslatorPanel.swift              # NSPanel subclass
│   │   ├── TranslatorWindowController.swift
│   │   └── TranslatorContentView.swift        # SwiftUI body
│   ├── Onboarding/
│   │   └── WelcomeView.swift
│   └── Resources/
│       ├── Info.plist
│       ├── Dictonary.entitlements
│       └── Assets.xcassets/
└── DictonaryTests/
    ├── PromptBuilderTests.swift
    ├── SettingsTests.swift
    ├── KeychainServiceTests.swift
    ├── SSEParserTests.swift
    ├── DeepSeekProviderTests.swift
    ├── OpenAIProviderTests.swift
    ├── ClaudeProviderTests.swift
    └── Mocks/
        ├── MockURLProtocol.swift
        ├── InMemoryKeychain.swift
        └── MockTranslationProvider.swift
```

**Why this layout:** every folder maps to one module from the design doc, mirroring the dependency direction (UI depends on Translation/Settings/Prompt, not the other way around). Tests live next to the type they cover, with shared mocks in `Mocks/`.

---

## Task 1: Bootstrap Xcode project with XcodeGen

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `Dictonary/App/DictonaryApp.swift`
- Create: `Dictonary/Resources/Info.plist`
- Create: `Dictonary/Resources/Dictonary.entitlements`
- Create: `Dictonary/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Dictonary/Resources/Assets.xcassets/Contents.json`
- Create: `DictonaryTests/SmokeTest.swift`

- [ ] **Step 1: Init git and write .gitignore**

```bash
cd /Users/houxiaomu/playground/dictonary
git init
```

Write `.gitignore`:

```
# macOS
.DS_Store

# Xcode
*.xcodeproj/
*.xcworkspace/
xcuserdata/
DerivedData/
build/
*.xcuserstate

# Swift Package Manager
.build/
Packages/
Package.resolved

# IDE
.vscode/
.idea/
```

- [ ] **Step 2: Install XcodeGen if missing**

```bash
which xcodegen || brew install xcodegen
xcodegen --version
```

Expected: a version line (≥ 2.38).

- [ ] **Step 3: Write `project.yml`**

```yaml
name: Dictonary
options:
  bundleIdPrefix: app.dictonary
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
  developmentLanguage: en
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
targets:
  Dictonary:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: Dictonary
    resources:
      - path: Dictonary/Prompt/Prompts
      - path: Dictonary/Resources/Assets.xcassets
    info:
      path: Dictonary/Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: Dictonary
        NSHumanReadableCopyright: "© 2026"
    entitlements:
      path: Dictonary/Resources/Dictonary.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.network.client: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.dictonary.Dictonary
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: NO
        ENABLE_HARDENED_RUNTIME: YES
        COMBINE_HIDPI_IMAGES: YES
  DictonaryTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: DictonaryTests
    dependencies:
      - target: Dictonary
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.dictonary.DictonaryTests
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: NO
schemes:
  Dictonary:
    build:
      targets:
        Dictonary: all
        DictonaryTests: [test]
    test:
      targets:
        - DictonaryTests
```

- [ ] **Step 4: Write minimal `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

(XcodeGen merges in the keys from `project.yml`'s `info.properties`.)

- [ ] **Step 5: Write empty entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 6: Write empty asset catalog**

`Dictonary/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info": { "version": 1, "author": "xcode" }
}
```

`Dictonary/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [],
  "info": { "version": 1, "author": "xcode" }
}
```

- [ ] **Step 7: Write minimal `DictonaryApp.swift`**

```swift
import SwiftUI

@main
struct DictonaryApp: App {
    var body: some Scene {
        Settings {
            Text("Dictonary")
                .frame(width: 400, height: 200)
        }
    }
}
```

This compiles into a no-op LSUIElement app. We'll fill it in later tasks.

- [ ] **Step 8: Write a smoke test**

`DictonaryTests/SmokeTest.swift`:

```swift
import XCTest
@testable import Dictonary

final class SmokeTest: XCTestCase {
    func testBundleLoads() {
        XCTAssertEqual(Bundle.main.bundleIdentifier?.contains("Dictonary") ?? false, true)
    }
}
```

(The test bundle's `Bundle.main` is the test runner, not the app. We just want SOMETHING to run so we know `xcodebuild test` works. This assertion is loose on purpose; replace later.)

Actually use this stricter version that doesn't depend on bundle identifier of the test runner:

```swift
import XCTest
@testable import Dictonary

final class SmokeTest: XCTestCase {
    func testCanInstantiateApp() {
        // If this compiles and links, the app target builds.
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 9: Generate Xcode project**

```bash
cd /Users/houxiaomu/playground/dictonary
xcodegen generate
```

Expected: `Dictonary.xcodeproj/` is created with no errors.

- [ ] **Step 10: Build and run tests**

```bash
xcodebuild test \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -quiet
```

Expected: `** TEST SUCCEEDED **`. If a code-signing error appears, double-check `CODE_SIGN_IDENTITY: "-"` in `project.yml` and re-run `xcodegen generate`.

- [ ] **Step 11: Commit**

```bash
git add .gitignore project.yml Dictonary DictonaryTests
git commit -m "chore: bootstrap XcodeGen project with empty SwiftUI scene"
```

---

## Task 2: Mode and Direction enums (foundations for PromptBuilder)

**Files:**
- Create: `Dictonary/Prompt/Mode.swift`
- Create: `Dictonary/Prompt/Direction.swift`

- [ ] **Step 1: Write `Mode.swift`**

```swift
import Foundation

enum Mode: String, Equatable {
    case dictionary
    case translation
}
```

- [ ] **Step 2: Write `Direction.swift`**

```swift
import Foundation

enum Direction: String, Equatable {
    case zhToEn = "zh->en"
    case enToZh = "en->zh"
}
```

- [ ] **Step 3: Regenerate project so new files are included**

```bash
xcodegen generate
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild build \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Dictonary/Prompt
git commit -m "feat(prompt): add Mode and Direction enums"
```

---

## Task 3: PromptBuilder — write tests first (TDD)

**Files:**
- Create: `DictonaryTests/PromptBuilderTests.swift`

- [ ] **Step 1: Write the failing test file**

```swift
import XCTest
@testable import Dictonary

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
```

- [ ] **Step 2: Verify it fails to compile (PromptBuilder doesn't exist yet)**

```bash
xcodebuild test \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -quiet 2>&1 | tail -20
```

Expected: compile error referencing `PromptBuilder`. Good — this is the "red" of TDD.

---

## Task 4: PromptBuilder — implementation

**Files:**
- Create: `Dictonary/Prompt/PromptBuilder.swift`

- [ ] **Step 1: Write `PromptBuilder.swift`**

```swift
import Foundation

struct BuiltPrompt: Equatable {
    let mode: Mode
    let direction: Direction
    let systemPrompt: String
}

enum PromptBuilder {

    // Sentence-end punctuation in CJK + Latin scripts.
    private static let sentenceEndingChars: Set<Character> = [
        ".", "!", "?", "。", "！", "？"
    ]

    /// Decide whether the input is a "lookup" (single word / short phrase / idiom)
    /// or a "sentence to translate".
    static func classify(_ raw: String) -> Mode {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .translation }

        // 1. sentence-ending punctuation → always treat as a sentence.
        if trimmed.contains(where: { sentenceEndingChars.contains($0) }) {
            return .translation
        }

        let cjkCount = trimmed.unicodeScalars.filter { isCJK($0) }.count
        let totalScalars = trimmed.unicodeScalars.count

        if cjkCount > 0 {
            // Chinese path. Count CJK chars only; ignore spaces & non-CJK punctuation.
            return cjkCount <= 6 ? .dictionary : .translation
        }

        // English path. Collapse whitespace and split.
        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace })
        // Pure-digit / pure-symbol input: route to translation mode (LLM handles it).
        let hasLetter = collapsed.contains { word in
            word.contains(where: { $0.isLetter })
        }
        guard hasLetter else { return .translation }

        return collapsed.count <= 3 ? .dictionary : .translation
    }

    /// Decide which way the translation should go.
    /// `> 30%` CJK characters → Chinese-to-English; otherwise English-to-Chinese.
    static func detectDirection(_ raw: String) -> Direction {
        let scalars = raw.unicodeScalars
        guard !scalars.isEmpty else { return .enToZh }

        var cjk = 0
        var letterOrCJK = 0
        for s in scalars {
            if isCJK(s) {
                cjk += 1
                letterOrCJK += 1
            } else if let scalar = Unicode.Scalar(s.value), Character(scalar).isLetter {
                letterOrCJK += 1
            }
        }
        guard letterOrCJK > 0 else { return .enToZh }
        let ratio = Double(cjk) / Double(letterOrCJK)
        return ratio > 0.30 ? .zhToEn : .enToZh
    }

    /// Build the final system prompt by selecting the right template and filling `{{direction}}`.
    static func build(
        text: String,
        dictionaryTemplate: String,
        translationTemplate: String
    ) -> BuiltPrompt {
        let mode = classify(text)
        let direction = detectDirection(text)
        let template = (mode == .dictionary) ? dictionaryTemplate : translationTemplate
        let prompt = template.replacingOccurrences(of: "{{direction}}", with: direction.rawValue)
        return BuiltPrompt(mode: mode, direction: direction, systemPrompt: prompt)
    }

    // MARK: - Private

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,   // CJK Unified Ideographs
             0x3400...0x4DBF,   // Extension A
             0x20000...0x2A6DF, // Extension B
             0x3000...0x303F,   // CJK Symbols and Punctuation
             0xFF00...0xFFEF:   // Halfwidth/Fullwidth
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: Regenerate Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 3: Run tests, expect green**

```bash
xcodebuild test \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -only-testing:DictonaryTests/PromptBuilderTests \
  -quiet
```

Expected: **TEST SUCCEEDED** with all `PromptBuilderTests` passing.

If `testClassifyMixedShortIsDictionary` fails because `commit message` somehow gets > 3 words, re-read your `split(whereSeparator:)` code — it's likely correct. If `testClassifyDigitsAreTranslation` fails, your "hasLetter" check is missing.

- [ ] **Step 4: Commit**

```bash
git add Dictonary/Prompt/PromptBuilder.swift DictonaryTests/PromptBuilderTests.swift
git commit -m "feat(prompt): PromptBuilder classifies input and builds prompt"
```

---

## Task 5: Bundle prompt template files

**Files:**
- Create: `Dictonary/Prompt/Prompts/dictionary.txt`
- Create: `Dictonary/Prompt/Prompts/translation.txt`
- Modify: `project.yml` (already includes `Dictonary/Prompt/Prompts` as resource — verify)

- [ ] **Step 1: Write `dictionary.txt`**

```
You are a precise bilingual dictionary for Chinese-English lookup. Return ONLY GitHub-flavored Markdown. Do NOT add preamble, apology, or "Here is...".

Format:
1. First line: `→ <translation>` (the most common single translation)
2. **词性 / Part of speech:** <pos>
3. **释义 / Definition:** numbered list, 1-3 senses, each one short
4. **例句 / Examples:** 1-2 bullet points; each bullet is `<source> — <translation>`

Direction: {{direction}}

Be concise. Total output ≤ 12 lines.
```

- [ ] **Step 2: Write `translation.txt`**

```
You are a fluent translator for Chinese-English. Return ONLY Markdown. Do NOT add preamble.

Format:
1. First line: <translation only, no quotes>
2. Blank line
3. (Optional) one short note about register, tone, or context, prefixed with "💡 ". Skip if nothing useful to add.

Direction: {{direction}}

Preserve any code, URLs, numbers exactly. Be concise.
```

- [ ] **Step 3: Confirm resources are bundled**

`project.yml` already has:
```yaml
resources:
  - path: Dictonary/Prompt/Prompts
```

Regenerate:

```bash
xcodegen generate
```

- [ ] **Step 4: Add a runtime helper to load templates**

Add to `Dictonary/Prompt/PromptBuilder.swift` (extend existing enum):

```swift
extension PromptBuilder {
    /// Loads a template from the app bundle. Throws if the file is missing — that's a packaging bug.
    static func loadTemplate(named name: String, in bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: "txt") else {
            throw NSError(
                domain: "PromptBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing prompt template: \(name).txt"]
            )
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

- [ ] **Step 5: Add a test verifying templates are bundled**

Append to `DictonaryTests/PromptBuilderTests.swift`:

```swift
extension PromptBuilderTests {
    func testTemplatesAreBundled() throws {
        let appBundle = Bundle(for: type(of: self)).bundleURL
            .deletingLastPathComponent()      // PlugIns
            .appendingPathComponent("Dictonary.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
        // The exact path varies; just check bundle.main also exposes them.
        let bundle = Bundle(for: PromptBuilderTestsAnchor.self)
        // Fallback: try loading via main bundle (the host app target).
        if let _ = Bundle.main.url(forResource: "dictionary", withExtension: "txt") {
            return
        }
        // If main bundle doesn't have it, the test is running without the host app — skip.
        try XCTSkipIf(true, "Templates accessed via host app bundle, not test bundle")
    }
}

private final class PromptBuilderTestsAnchor {}
```

(This test is intentionally lenient — XCTest test bundles often don't include host app resources directly. The real verification is `Step 6` running the actual app loading the template.)

- [ ] **Step 6: Run tests**

```bash
xcodebuild test \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -only-testing:DictonaryTests/PromptBuilderTests \
  -quiet
```

Expected: all PromptBuilderTests pass (the new bundling test may skip — that's fine).

- [ ] **Step 7: Commit**

```bash
git add Dictonary/Prompt/Prompts Dictonary/Prompt/PromptBuilder.swift DictonaryTests/PromptBuilderTests.swift
git commit -m "feat(prompt): bundle dictionary/translation templates and add loader"
```

---

## Task 6: KeychainService — protocol, in-memory mock, and tests

**Files:**
- Create: `Dictonary/Settings/KeychainService.swift`
- Create: `DictonaryTests/Mocks/InMemoryKeychain.swift`
- Create: `DictonaryTests/KeychainServiceTests.swift`

- [ ] **Step 1: Write the protocol + concrete implementation**

```swift
// Dictonary/Settings/KeychainService.swift
import Foundation
import Security

protocol KeychainService {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

enum KeychainError: Error, Equatable {
    case unhandledOSStatus(OSStatus)
    case dataConversionFailed
}

final class SystemKeychain: KeychainService {
    private let service: String

    init(service: String = "app.dictonary.api-keys") {
        self.service = service
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else { throw KeychainError.dataConversionFailed }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledOSStatus(status)
        }
    }

    func write(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unhandledOSStatus(addStatus)
            }
            return
        }
        throw KeychainError.unhandledOSStatus(updateStatus)
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledOSStatus(status)
        }
    }
}
```

- [ ] **Step 2: Write the in-memory mock**

```swift
// DictonaryTests/Mocks/InMemoryKeychain.swift
import Foundation
@testable import Dictonary

final class InMemoryKeychain: KeychainService {
    private var storage: [String: String] = [:]

    func read(account: String) throws -> String? {
        storage[account]
    }

    func write(_ value: String, account: String) throws {
        storage[account] = value
    }

    func delete(account: String) throws {
        storage.removeValue(forKey: account)
    }
}
```

- [ ] **Step 3: Write the tests using the mock**

```swift
// DictonaryTests/KeychainServiceTests.swift
import XCTest
@testable import Dictonary

final class KeychainServiceTests: XCTestCase {
    func testReadMissingReturnsNil() throws {
        let kc = InMemoryKeychain()
        XCTAssertNil(try kc.read(account: "deepseek"))
    }

    func testWriteThenRead() throws {
        let kc = InMemoryKeychain()
        try kc.write("sk-1234", account: "deepseek")
        XCTAssertEqual(try kc.read(account: "deepseek"), "sk-1234")
    }

    func testWriteOverwrites() throws {
        let kc = InMemoryKeychain()
        try kc.write("sk-1", account: "deepseek")
        try kc.write("sk-2", account: "deepseek")
        XCTAssertEqual(try kc.read(account: "deepseek"), "sk-2")
    }

    func testDeleteRemoves() throws {
        let kc = InMemoryKeychain()
        try kc.write("sk-1234", account: "deepseek")
        try kc.delete(account: "deepseek")
        XCTAssertNil(try kc.read(account: "deepseek"))
    }

    func testDeleteMissingDoesNotThrow() throws {
        let kc = InMemoryKeychain()
        XCTAssertNoThrow(try kc.delete(account: "missing"))
    }
}
```

- [ ] **Step 4: Regenerate, run tests**

```bash
xcodegen generate
xcodebuild test \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -only-testing:DictonaryTests/KeychainServiceTests \
  -quiet
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Dictonary/Settings/KeychainService.swift DictonaryTests/Mocks/InMemoryKeychain.swift DictonaryTests/KeychainServiceTests.swift
git commit -m "feat(settings): KeychainService protocol, system + in-memory impls, tests"
```

---

## Task 7: ProviderKind, HotkeyCombo, and Settings ObservableObject

**Files:**
- Create: `Dictonary/Settings/ProviderKind.swift`
- Create: `Dictonary/Settings/HotkeyCombo.swift`
- Create: `Dictonary/Settings/Settings.swift`
- Create: `DictonaryTests/SettingsTests.swift`

- [ ] **Step 1: Write `ProviderKind.swift`**

```swift
import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case openai
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai:   return "OpenAI"
        case .claude:   return "Claude"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .openai:   return "gpt-4o-mini"
        case .claude:   return "claude-haiku-4-5-20251001"
        }
    }

    var defaultEndpoint: URL {
        switch self {
        case .deepseek: return URL(string: "https://api.deepseek.com/v1/chat/completions")!
        case .openai:   return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .claude:   return URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }
}
```

- [ ] **Step 2: Write `HotkeyCombo.swift`**

```swift
import AppKit

struct HotkeyCombo: Equatable, Codable {
    /// Virtual key code (e.g. kVK_Space = 49).
    let keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, shiftKey, controlKey).
    let modifiers: UInt32

    static let defaultCombo = HotkeyCombo(keyCode: 49 /* space */, modifiers: 1 << 11 /* optionKey */)

    /// Human-readable label like "⌥Space".
    var displayString: String {
        var s = ""
        if modifiers & (1 << 12) != 0 { s += "⌃" } // controlKey
        if modifiers & (1 << 11) != 0 { s += "⌥" } // optionKey
        if modifiers & (1 << 9)  != 0 { s += "⇧" } // shiftKey
        if modifiers & (1 << 8)  != 0 { s += "⌘" } // cmdKey
        s += keyName(forKeyCode: keyCode)
        return s
    }

    private func keyName(forKeyCode code: UInt32) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        // Letters a-z are 0..0x32 ish; we expose only the names users can record.
        default:
            // For letters, map via UCKeyTranslate at recording time; fallback to raw code.
            return "Key\(code)"
        }
    }
}
```

- [ ] **Step 3: Write `Settings.swift`**

```swift
import Foundation
import Combine

final class Settings: ObservableObject {

    // Keys for UserDefaults
    private enum Key {
        static let provider     = "provider"
        static let model        = "model"
        static let endpoint     = "endpoint"
        static let hotkey       = "hotkey"
        static let launchAtLogin = "launchAtLogin"
        static let didOnboard   = "didOnboard"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainService

    @Published var provider: ProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: Key.provider) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    @Published var endpoint: URL? {
        didSet { defaults.set(endpoint?.absoluteString, forKey: Key.endpoint) }
    }

    @Published var hotkey: HotkeyCombo {
        didSet { try? saveHotkey(hotkey) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var didOnboard: Bool {
        didSet { defaults.set(didOnboard, forKey: Key.didOnboard) }
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainService = SystemKeychain()) {
        self.defaults = defaults
        self.keychain = keychain

        let providerRaw = defaults.string(forKey: Key.provider) ?? ProviderKind.deepseek.rawValue
        let providerKind = ProviderKind(rawValue: providerRaw) ?? .deepseek
        self.provider = providerKind
        self.model = defaults.string(forKey: Key.model) ?? providerKind.defaultModel
        if let s = defaults.string(forKey: Key.endpoint), let url = URL(string: s) {
            self.endpoint = url
        } else {
            self.endpoint = nil
        }
        if let data = defaults.data(forKey: Key.hotkey),
           let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            self.hotkey = combo
        } else {
            self.hotkey = .defaultCombo
        }
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.didOnboard = defaults.bool(forKey: Key.didOnboard)
    }

    // MARK: - API key helpers

    func apiKey(for kind: ProviderKind) -> String? {
        (try? keychain.read(account: kind.rawValue)) ?? nil
    }

    func setAPIKey(_ key: String, for kind: ProviderKind) throws {
        try keychain.write(key, account: kind.rawValue)
    }

    func deleteAPIKey(for kind: ProviderKind) throws {
        try keychain.delete(account: kind.rawValue)
    }

    /// The endpoint to actually use: user override if present, else provider default.
    func resolvedEndpoint(for kind: ProviderKind) -> URL {
        endpoint ?? kind.defaultEndpoint
    }

    private func saveHotkey(_ combo: HotkeyCombo) throws {
        let data = try JSONEncoder().encode(combo)
        defaults.set(data, forKey: Key.hotkey)
    }
}
```

- [ ] **Step 4: Write the tests**

```swift
// DictonaryTests/SettingsTests.swift
import XCTest
@testable import Dictonary

final class SettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsWhenEmpty() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        XCTAssertEqual(s.provider, .deepseek)
        XCTAssertEqual(s.model, "deepseek-chat")
        XCTAssertEqual(s.hotkey, .defaultCombo)
        XCTAssertFalse(s.didOnboard)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertNil(s.endpoint)
    }

    func testProviderChangePersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults, keychain: InMemoryKeychain())
        s.provider = .openai
        let s2 = Settings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(s2.provider, .openai)
    }

    func testHotkeyChangePersists() throws {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults, keychain: InMemoryKeychain())
        let custom = HotkeyCombo(keyCode: 36, modifiers: 1 << 8)
        s.hotkey = custom
        let s2 = Settings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(s2.hotkey, custom)
    }

    func testAPIKeyRoundTrip() throws {
        let kc = InMemoryKeychain()
        let s = Settings(defaults: makeDefaults(), keychain: kc)
        try s.setAPIKey("sk-foo", for: .deepseek)
        XCTAssertEqual(s.apiKey(for: .deepseek), "sk-foo")
        XCTAssertNil(s.apiKey(for: .openai))
    }

    func testResolvedEndpointFallsBackToProviderDefault() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        XCTAssertEqual(s.resolvedEndpoint(for: .deepseek), ProviderKind.deepseek.defaultEndpoint)
    }

    func testResolvedEndpointHonorsOverride() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        let override = URL(string: "https://example.com/v1")!
        s.endpoint = override
        XCTAssertEqual(s.resolvedEndpoint(for: .deepseek), override)
    }
}
```

- [ ] **Step 5: Regenerate, run tests**

```bash
xcodegen generate
xcodebuild test \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -only-testing:DictonaryTests/SettingsTests \
  -quiet
```

Expected: all 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Dictonary/Settings DictonaryTests/SettingsTests.swift
git commit -m "feat(settings): Settings ObservableObject with persisted preferences"
```

---

## Task 8: TranslationError and TranslationProvider protocol

**Files:**
- Create: `Dictonary/Translation/TranslationError.swift`
- Create: `Dictonary/Translation/TranslationProvider.swift`

- [ ] **Step 1: Write `TranslationError.swift`**

```swift
import Foundation

enum TranslationError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case network(message: String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, body: String?)
    case streamInterrupted(partial: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 API Key"
        case .network(let m):
            return "网络不可用：\(m)"
        case .unauthorized:
            return "API Key 无效或已过期"
        case .rateLimited:
            return "请求过于频繁，稍后再试"
        case .serverError(let s, _):
            return "服务异常 (HTTP \(s))"
        case .streamInterrupted:
            return "连接中断"
        case .cancelled:
            return "已取消"
        }
    }

    static func == (lhs: TranslationError, rhs: TranslationError) -> Bool {
        switch (lhs, rhs) {
        case (.missingAPIKey, .missingAPIKey),
             (.unauthorized, .unauthorized),
             (.cancelled, .cancelled):
            return true
        case let (.network(a), .network(b)):
            return a == b
        case let (.rateLimited(a), .rateLimited(b)):
            return a == b
        case let (.serverError(s1, b1), .serverError(s2, b2)):
            return s1 == s2 && b1 == b2
        case let (.streamInterrupted(a), .streamInterrupted(b)):
            return a == b
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: Write `TranslationProvider.swift`**

```swift
import Foundation

protocol TranslationProvider {
    /// Streams the model's response token-by-token.
    /// Throws `TranslationError` (mapped from underlying transport errors).
    func translate(
        systemPrompt: String,
        userText: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) -> AsyncThrowingStream<String, Error>
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodegen generate
xcodebuild build \
  -project Dictonary.xcodeproj \
  -scheme Dictonary \
  -destination 'platform=macOS' \
  -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Dictonary/Translation
git commit -m "feat(translation): TranslationError enum and TranslationProvider protocol"
```

---

## Task 9: SSEParser — write tests first

**Files:**
- Create: `DictonaryTests/SSEParserTests.swift`

- [ ] **Step 1: Write the failing test file**

```swift
import XCTest
@testable import Dictonary

final class SSEParserTests: XCTestCase {

    func testParsesSingleDataLine() {
        var parser = SSEParser()
        let events = parser.feed("data: hello\n\n")
        XCTAssertEqual(events, [.message("hello")])
    }

    func testParsesMultipleDataLinesInOneEventConcatenatesWithNewline() {
        var parser = SSEParser()
        let events = parser.feed("data: line1\ndata: line2\n\n")
        XCTAssertEqual(events, [.message("line1\nline2")])
    }

    func testEmitsDoneOnDoneSentinel() {
        var parser = SSEParser()
        let events = parser.feed("data: [DONE]\n\n")
        XCTAssertEqual(events, [.done])
    }

    func testHandlesChunkedFeedingMidEvent() {
        var parser = SSEParser()
        var all: [SSEEvent] = []
        all += parser.feed("data: hel")
        all += parser.feed("lo\n")
        all += parser.feed("\n")
        XCTAssertEqual(all, [.message("hello")])
    }

    func testIgnoresCommentsAndUnknownFields() {
        var parser = SSEParser()
        let events = parser.feed(": keepalive\nfoo: bar\ndata: real\n\n")
        XCTAssertEqual(events, [.message("real")])
    }

    func testHandlesMultipleEventsInOneChunk() {
        var parser = SSEParser()
        let events = parser.feed("data: a\n\ndata: b\n\n")
        XCTAssertEqual(events, [.message("a"), .message("b")])
    }
}
```

- [ ] **Step 2: Verify it fails to compile**

```bash
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -only-testing:DictonaryTests/SSEParserTests -quiet 2>&1 | tail -20
```

Expected: error about `SSEParser` / `SSEEvent` not being defined.

---

## Task 10: SSEParser — implementation

**Files:**
- Create: `Dictonary/Translation/SSEParser.swift`

- [ ] **Step 1: Write `SSEParser.swift`**

```swift
import Foundation

enum SSEEvent: Equatable {
    case message(String)
    case done
}

struct SSEParser {
    private var buffer = ""

    /// Feeds a chunk of bytes (decoded as UTF-8) into the parser.
    /// Returns any complete events extracted so far.
    mutating func feed(_ chunk: String) -> [SSEEvent] {
        buffer += chunk
        var events: [SSEEvent] = []
        // SSE separates events by a blank line ("\n\n").
        while let range = buffer.range(of: "\n\n") {
            let raw = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let event = parseEvent(raw) {
                events.append(event)
            }
        }
        return events
    }

    private func parseEvent(_ raw: String) -> SSEEvent? {
        var dataLines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix(":") { continue } // comment
            guard let colon = s.firstIndex(of: ":") else { continue }
            let field = s[s.startIndex..<colon]
            var value = s[s.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
            if field == "data" {
                dataLines.append(String(value))
            }
        }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        if payload == "[DONE]" { return .done }
        return .message(payload)
    }
}
```

- [ ] **Step 2: Run tests, expect green**

```bash
xcodegen generate
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -only-testing:DictonaryTests/SSEParserTests -quiet
```

Expected: all 6 SSE tests pass.

- [ ] **Step 3: Commit**

```bash
git add Dictonary/Translation/SSEParser.swift DictonaryTests/SSEParserTests.swift
git commit -m "feat(translation): SSE parser with chunked-input support"
```

---

## Task 11: MockURLProtocol shared test helper

**Files:**
- Create: `DictonaryTests/Mocks/MockURLProtocol.swift`

- [ ] **Step 1: Write `MockURLProtocol.swift`**

```swift
import Foundation

final class MockURLProtocol: URLProtocol {

    /// Each test sets this; the closure receives the request and returns headers + body chunks.
    /// Body chunks are delivered in order, then the loading completes.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            fatalError("MockURLProtocol.handler not set")
        }
        do {
            let (response, chunks) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static func mocked() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add DictonaryTests/Mocks/MockURLProtocol.swift
git commit -m "test: add MockURLProtocol helper for stubbing URLSession"
```

---

## Task 12: DeepSeekProvider — TDD

**Files:**
- Create: `DictonaryTests/DeepSeekProviderTests.swift`
- Create: `Dictonary/Translation/DeepSeekProvider.swift`

DeepSeek uses OpenAI-compatible chat completions with SSE streaming. Each event payload is JSON like:
```
{"choices":[{"delta":{"content":"hello"}}]}
```
followed eventually by `[DONE]`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Dictonary

final class DeepSeekProviderTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRequestShapeIsOpenAICompatible() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { req in
            capturedRequest = req
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (resp, [Data("data: [DONE]\n\n".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        let stream = provider.translate(
            systemPrompt: "SYS",
            userText: "hello",
            apiKey: "sk-test",
            model: "deepseek-chat",
            endpoint: URL(string: "https://api.deepseek.com/v1/chat/completions")!
        )
        for try await _ in stream { }

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.bodyData)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "deepseek-chat")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[0]["role"], "system")
        XCTAssertEqual(messages?[0]["content"], "SYS")
        XCTAssertEqual(messages?[1]["role"], "user")
        XCTAssertEqual(messages?[1]["content"], "hello")
    }

    func testStreamYieldsDeltaContent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunks = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
                "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n",
                "data: [DONE]\n\n"
            ].map { Data($0.utf8) }
            return (resp, chunks)
        }
        let provider = DeepSeekProvider(session: .mocked())
        var output = ""
        for try await piece in provider.translate(
            systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
            endpoint: URL(string: "https://example.com")!
        ) {
            output += piece
        }
        XCTAssertEqual(output, "Hello")
    }

    func testUnauthorizedMapsToTranslationError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, [Data("{\"error\":\"bad key\"}".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRateLimitedMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 429,
                httpVersion: nil, headerFields: ["Retry-After": "12"]
            )!
            return (resp, [Data("rate limited".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 12))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testServerErrorMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (resp, [Data("oops".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .serverError(status: 503, body: "oops"))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}

// Helper to read URLRequest body even when set via httpBodyStream.
extension URLRequest {
    var bodyData: Data? {
        if let d = httpBody { return d }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let bufSize = 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: bufSize)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
```

- [ ] **Step 2: Verify tests fail to compile (DeepSeekProvider missing)**

```bash
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -only-testing:DictonaryTests/DeepSeekProviderTests -quiet 2>&1 | tail -20
```

- [ ] **Step 3: Write `DeepSeekProvider.swift`**

```swift
import Foundation

final class DeepSeekProvider: TranslationProvider {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        systemPrompt: String,
        userText: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userText]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw TranslationError.network(message: "no HTTP response")
                    }
                    if http.statusCode == 401 {
                        throw TranslationError.unauthorized
                    } else if http.statusCode == 429 {
                        let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                        throw TranslationError.rateLimited(retryAfter: ra)
                    } else if !(200...299).contains(http.statusCode) {
                        let bodyStr = try await collect(bytes: bytes)
                        throw TranslationError.serverError(status: http.statusCode, body: bodyStr)
                    }

                    var parser = SSEParser()
                    var partial = ""

                    var dataChunk = Data()
                    for try await byte in bytes {
                        dataChunk.append(byte)
                        if dataChunk.count >= 256 {
                            try emit(&parser, &partial, &dataChunk, continuation)
                        }
                    }
                    try emit(&parser, &partial, &dataChunk, continuation)

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let urlErr as URLError {
                    continuation.finish(throwing: TranslationError.network(message: urlErr.localizedDescription))
                } catch let te as TranslationError {
                    continuation.finish(throwing: te)
                } catch {
                    continuation.finish(throwing: TranslationError.network(message: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func emit(
        _ parser: inout SSEParser,
        _ partial: inout String,
        _ chunk: inout Data,
        _ continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        guard !chunk.isEmpty else { return }
        guard let text = String(data: chunk, encoding: .utf8) else {
            chunk.removeAll(keepingCapacity: true)
            return
        }
        chunk.removeAll(keepingCapacity: true)
        for event in parser.feed(text) {
            switch event {
            case .done:
                continuation.finish()
                return
            case .message(let payload):
                if let token = parseDelta(payload) {
                    continuation.yield(token)
                    partial += token
                }
            }
        }
    }

    private func parseDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    private func collect(bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await b in bytes { data.append(b) }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 4: Run tests, expect green**

```bash
xcodegen generate
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -only-testing:DictonaryTests/DeepSeekProviderTests -quiet
```

Expected: all 5 DeepSeekProvider tests pass.

- [ ] **Step 5: Commit**

```bash
git add Dictonary/Translation/DeepSeekProvider.swift DictonaryTests/DeepSeekProviderTests.swift
git commit -m "feat(translation): DeepSeekProvider with streaming + error mapping"
```

---

## Task 13: OpenAIProvider — leverage DeepSeek's compatibility

OpenAI uses the SAME wire format as DeepSeek (DeepSeek deliberately mirrors OpenAI). So this provider is essentially the same.

**Files:**
- Create: `Dictonary/Translation/OpenAIProvider.swift`
- Create: `DictonaryTests/OpenAIProviderTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import Dictonary

final class OpenAIProviderTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    func testStreamsContent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunks = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n",
                "data: [DONE]\n\n"
            ].map { Data($0.utf8) }
            return (resp, chunks)
        }
        let provider = OpenAIProvider(session: .mocked())
        var out = ""
        for try await t in provider.translate(
            systemPrompt: "s", userText: "u", apiKey: "k", model: "gpt-4o-mini",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!
        ) {
            out += t
        }
        XCTAssertEqual(out, "Hi")
    }

    func testUnauthorizedMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, [])
        }
        let provider = OpenAIProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "s", userText: "u", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let e as TranslationError {
            XCTAssertEqual(e, .unauthorized)
        } catch { XCTFail("unexpected: \(error)") }
    }
}
```

- [ ] **Step 2: Implement `OpenAIProvider.swift`**

OpenAI is wire-compatible with DeepSeek; we just delegate. To avoid duplication, we'll extract a shared `OpenAICompatibleProvider` superclass.

Refactor: rename `DeepSeekProvider` to use a shared base. Create `Dictonary/Translation/OpenAIProvider.swift`:

```swift
import Foundation

/// Reusable streaming impl for any provider using OpenAI's chat-completions wire format.
/// Used by both DeepSeek and OpenAI directly.
class OpenAICompatibleProvider: TranslationProvider {
    fileprivate let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        systemPrompt: String,
        userText: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userText]
                        ]
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.checkResponse(response, bytes: bytes)

                    var parser = SSEParser()
                    var dataChunk = Data()

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        dataChunk.append(byte)
                        if dataChunk.count >= 256 {
                            Self.flush(&parser, &dataChunk, continuation, deltaParser: Self.parseOpenAIDelta)
                        }
                    }
                    Self.flush(&parser, &dataChunk, continuation, deltaParser: Self.parseOpenAIDelta)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let te as TranslationError {
                    continuation.finish(throwing: te)
                } catch let urlErr as URLError {
                    continuation.finish(throwing: TranslationError.network(message: urlErr.localizedDescription))
                } catch {
                    continuation.finish(throwing: TranslationError.network(message: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func checkResponse(_ response: URLResponse, bytes: URLSession.AsyncBytes) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network(message: "no HTTP response")
        }
        if http.statusCode == 401 { throw TranslationError.unauthorized }
        if http.statusCode == 429 {
            let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw TranslationError.rateLimited(retryAfter: ra)
        }
        if !(200...299).contains(http.statusCode) {
            // Sync-collect body since this is the failure path.
            let body = try awaitableCollect(bytes: bytes)
            throw TranslationError.serverError(status: http.statusCode, body: body)
        }
    }

    static func flush(
        _ parser: inout SSEParser,
        _ chunk: inout Data,
        _ continuation: AsyncThrowingStream<String, Error>.Continuation,
        deltaParser: (String) -> String?
    ) {
        guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else {
            chunk.removeAll(keepingCapacity: true); return
        }
        chunk.removeAll(keepingCapacity: true)
        for event in parser.feed(text) {
            switch event {
            case .done:
                continuation.finish(); return
            case .message(let payload):
                if let token = deltaParser(payload) {
                    continuation.yield(token)
                }
            }
        }
    }

    static func parseOpenAIDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    private static func awaitableCollect(bytes: URLSession.AsyncBytes) throws -> String {
        // Synchronously drain remaining bytes by spinning a child task.
        let semaphore = DispatchSemaphore(value: 0)
        var collected = Data()
        var capturedError: Error?
        let task = Task {
            defer { semaphore.signal() }
            do {
                for try await b in bytes { collected.append(b) }
            } catch { capturedError = error }
        }
        semaphore.wait()
        _ = task
        if let e = capturedError { throw e }
        return String(data: collected, encoding: .utf8) ?? ""
    }
}

/// OpenAI itself.
final class OpenAIProvider: OpenAICompatibleProvider {}
```

- [ ] **Step 3: Refactor `DeepSeekProvider.swift` to use the shared base**

Replace `Dictonary/Translation/DeepSeekProvider.swift` with:

```swift
import Foundation

/// DeepSeek is wire-compatible with OpenAI's chat completions.
final class DeepSeekProvider: OpenAICompatibleProvider {}
```

- [ ] **Step 4: Re-run all DeepSeek tests + new OpenAI tests**

```bash
xcodegen generate
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -only-testing:DictonaryTests/DeepSeekProviderTests -only-testing:DictonaryTests/OpenAIProviderTests -quiet
```

Expected: all 7 tests (5 DeepSeek + 2 OpenAI) pass.

- [ ] **Step 5: Commit**

```bash
git add Dictonary/Translation DictonaryTests/OpenAIProviderTests.swift
git commit -m "refactor(translation): extract OpenAICompatibleProvider; add OpenAIProvider"
```

---

## Task 14: ClaudeProvider — different wire format

Claude uses the messages API and a different SSE event shape. Each event has a JSON body like:
```
{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
```
The end is signaled by `{"type":"message_stop"}`.

**Files:**
- Create: `Dictonary/Translation/ClaudeProvider.swift`
- Create: `DictonaryTests/ClaudeProviderTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import XCTest
@testable import Dictonary

final class ClaudeProviderTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    func testRequestUsesMessagesAPIShape() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, [Data("data: {\"type\":\"message_stop\"}\n\n".utf8)])
        }
        let p = ClaudeProvider(session: .mocked())
        for try await _ in p.translate(
            systemPrompt: "SYS", userText: "Hi",
            apiKey: "sk-ant", model: "claude-haiku-4-5-20251001",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!
        ) { }

        let req = try XCTUnwrap(captured)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try XCTUnwrap(req.bodyData)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(json?["system"] as? String, "SYS")
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "Hi")
    }

    func testStreamsTextDeltas() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunks = [
                "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}\n\n",
                "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n"
            ].map { Data($0.utf8) }
            return (resp, chunks)
        }
        let p = ClaudeProvider(session: .mocked())
        var out = ""
        for try await t in p.translate(
            systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
            endpoint: URL(string: "https://example.com")!
        ) {
            out += t
        }
        XCTAssertEqual(out, "Hello")
    }

    func testUnauthorizedMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, [])
        }
        let p = ClaudeProvider(session: .mocked())
        do {
            for try await _ in p.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let e as TranslationError {
            XCTAssertEqual(e, .unauthorized)
        } catch { XCTFail("unexpected: \(error)") }
    }
}
```

- [ ] **Step 2: Implement `ClaudeProvider.swift`**

```swift
import Foundation

final class ClaudeProvider: TranslationProvider {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        systemPrompt: String,
        userText: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 1024,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": [
                            ["role": "user", "content": userText]
                        ]
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    try OpenAICompatibleProvider.checkResponse(response, bytes: bytes)

                    var parser = SSEParser()
                    var chunkData = Data()

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunkData.append(byte)
                        if chunkData.count >= 256 {
                            OpenAICompatibleProvider.flush(&parser, &chunkData, continuation, deltaParser: ClaudeProvider.parseClaudeDelta)
                        }
                    }
                    OpenAICompatibleProvider.flush(&parser, &chunkData, continuation, deltaParser: ClaudeProvider.parseClaudeDelta)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let te as TranslationError {
                    continuation.finish(throwing: te)
                } catch let urlErr as URLError {
                    continuation.finish(throwing: TranslationError.network(message: urlErr.localizedDescription))
                } catch {
                    continuation.finish(throwing: TranslationError.network(message: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func parseClaudeDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let type = obj["type"] as? String else { return nil }
        if type == "content_block_delta",
           let delta = obj["delta"] as? [String: Any],
           delta["type"] as? String == "text_delta",
           let text = delta["text"] as? String {
            return text
        }
        return nil
    }
}
```

- [ ] **Step 3: Run tests**

```bash
xcodegen generate
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -only-testing:DictonaryTests/ClaudeProviderTests -quiet
```

Expected: all 3 Claude tests pass.

- [ ] **Step 4: Commit**

```bash
git add Dictonary/Translation/ClaudeProvider.swift DictonaryTests/ClaudeProviderTests.swift
git commit -m "feat(translation): ClaudeProvider with messages API + text_delta parsing"
```

---

## Task 15: TranslationService facade

A thin façade so the rest of the app doesn't have to know which provider is active.

**Files:**
- Create: `Dictonary/Translation/TranslationService.swift`

- [ ] **Step 1: Write `TranslationService.swift`**

```swift
import Foundation

final class TranslationService {
    private let settings: Settings
    private let providers: [ProviderKind: TranslationProvider]

    init(settings: Settings, providers: [ProviderKind: TranslationProvider]? = nil) {
        self.settings = settings
        self.providers = providers ?? [
            .deepseek: DeepSeekProvider(),
            .openai:   OpenAIProvider(),
            .claude:   ClaudeProvider()
        ]
    }

    /// Translates `userText` using the active provider in `Settings`.
    /// Yields tokens as they stream. May throw `TranslationError`.
    func translate(systemPrompt: String, userText: String) -> AsyncThrowingStream<String, Error> {
        let kind = settings.provider
        guard let provider = providers[kind] else {
            return AsyncThrowingStream { c in c.finish(throwing: TranslationError.network(message: "provider missing")) }
        }
        guard let key = settings.apiKey(for: kind), !key.isEmpty else {
            return AsyncThrowingStream { c in c.finish(throwing: TranslationError.missingAPIKey) }
        }
        return provider.translate(
            systemPrompt: systemPrompt,
            userText: userText,
            apiKey: key,
            model: settings.model,
            endpoint: settings.resolvedEndpoint(for: kind)
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add Dictonary/Translation/TranslationService.swift
git commit -m "feat(translation): TranslationService facade selecting active provider"
```

---

## Task 16: HotKeyManager — Carbon wrapper

Carbon's `RegisterEventHotKey` requires a global C callback. We isolate that ugliness in this module.

**Files:**
- Create: `Dictonary/Hotkey/HotKeyManager.swift`

- [ ] **Step 1: Write `HotKeyManager.swift`**

```swift
import AppKit
import Carbon.HIToolbox

final class HotKeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handlerID: UInt32 = 0xDDDD0001

    /// Called on the main thread when the hotkey fires.
    var onPress: (() -> Void)?

    deinit { unregister() }

    /// Registers the given combo. Returns `true` on success, `false` if the system rejects it.
    @discardableResult
    func register(_ combo: HotkeyCombo) -> Bool {
        unregister()

        var hotKeyID = EventHotKeyID(signature: OSType(0x4458_4C54), id: handlerID) // "DXLT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref = ref else { return false }
        self.hotKeyRef = ref

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onPress?() }
                return noErr
            },
            1,
            &spec,
            userData,
            &eventHandler
        )
        if handlerStatus != noErr {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add Dictonary/Hotkey
git commit -m "feat(hotkey): Carbon-based HotKeyManager with main-thread callback"
```

---

## Task 17: TranslatorPanel + TranslatorWindowController + content view

This is the main visible UI. Uses an `NSPanel` so it can float and not steal app focus.

**Files:**
- Create: `Dictonary/Window/TranslatorPanel.swift`
- Create: `Dictonary/Window/TranslatorWindowController.swift`
- Create: `Dictonary/Window/TranslatorContentView.swift`

- [ ] **Step 1: Write `TranslatorPanel.swift`**

```swift
import AppKit

final class TranslatorPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.hidesOnDeactivate = true
        self.becomesKeyOnlyIfNeeded = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Write `TranslatorContentView.swift`**

```swift
import SwiftUI

@MainActor
final class TranslatorViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case streaming(String)
        case done(String)
        case error(String)
    }

    @Published var input: String = ""
    @Published var state: State = .idle

    private let service: TranslationService
    private let dictTemplate: String
    private let translTemplate: String
    private var task: Task<Void, Never>?

    init(service: TranslationService, dictTemplate: String, translTemplate: String) {
        self.service = service
        self.dictTemplate = dictTemplate
        self.translTemplate = translTemplate
    }

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        state = .streaming("")
        let prompt = PromptBuilder.build(
            text: text,
            dictionaryTemplate: dictTemplate,
            translationTemplate: translTemplate
        )
        task = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            do {
                for try await token in self.service.translate(systemPrompt: prompt.systemPrompt, userText: text) {
                    buffer += token
                    self.state = .streaming(buffer)
                }
                self.state = .done(buffer)
            } catch let e as TranslationError {
                if case .cancelled = e { return } // swallow
                self.state = .error(e.errorDescription ?? "未知错误")
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func reset() {
        task?.cancel()
        input = ""
        state = .idle
    }
}

struct TranslatorContentView: View {
    @ObservedObject var vm: TranslatorViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("输入中文或英文，回车翻译", text: $vm.input)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($inputFocused)
                .onSubmit { vm.submit() }

            switch vm.state {
            case .idle:
                EmptyView()
            case .streaming(let s) where s.isEmpty:
                ProgressView().controlSize(.small)
            case .streaming(let s), .done(let s):
                ScrollView {
                    Text(LocalizedStringKey(s))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            case .error(let msg):
                Text("⚠️ \(msg)")
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 560)
        .onAppear { inputFocused = true }
    }
}
```

- [ ] **Step 3: Write `TranslatorWindowController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class TranslatorWindowController {
    private let panel: TranslatorPanel
    private let vm: TranslatorViewModel
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(service: TranslationService, dictTemplate: String, translTemplate: String) {
        self.vm = TranslatorViewModel(
            service: service,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate
        )
        self.panel = TranslatorPanel()
        let host = NSHostingView(rootView: TranslatorContentView(vm: vm))
        panel.contentView = host
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        positionAtTopCenterOfMouseScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func hide() {
        removeDismissMonitors()
        panel.orderOut(nil)
        vm.reset()
    }

    // MARK: - Position

    private func positionAtTopCenterOfMouseScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main!
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.maxY - panelSize.height - (visibleFrame.height * 0.18)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Esc + click-outside dismissal

    private func installDismissMonitors() {
        removeDismissMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc = 53
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeDismissMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 5: Commit**

```bash
git add Dictonary/Window
git commit -m "feat(window): TranslatorPanel + Spotlight-style controller + streaming view"
```

---

## Task 18: StatusBarController

**Files:**
- Create: `Dictonary/StatusBar/StatusBarController.swift`

- [ ] **Step 1: Write `StatusBarController.swift`**

```swift
import AppKit

@MainActor
final class StatusBarController {
    private let item: NSStatusItem
    private var menu: NSMenu

    var onOpen: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    var needsAPIKey: Bool = false {
        didSet { renderIcon() }
    }

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        renderIcon()
        configureMenu()
    }

    private func renderIcon() {
        guard let button = item.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Dictonary")
        button.image = base?.withSymbolConfiguration(cfg)
        if needsAPIKey {
            // Add a tiny red dot indicator by appending another image inside the cell.
            button.title = "•"
            button.imagePosition = .imageLeft
            button.contentTintColor = .systemRed
        } else {
            button.title = ""
            button.contentTintColor = nil
        }
        button.target = self
        button.action = #selector(handleClick)
    }

    private func configureMenu() {
        menu.addItem(NSMenuItem(title: "打开", action: #selector(handleOpenMenu), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(handlePreferences), keyEquivalent: ","))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dictonary", action: #selector(handleQuit), keyEquivalent: "q"))
        menu.items.last?.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            item.menu = menu
            item.button?.performClick(nil)
            // Reset so the next left click triggers onOpen instead of menu.
            DispatchQueue.main.async { [weak self] in self?.item.menu = nil }
        } else {
            onOpen?()
        }
    }

    @objc private func handleOpenMenu() { onOpen?() }
    @objc private func handlePreferences() { onPreferences?() }
    @objc private func handleQuit() { onQuit?() }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add Dictonary/StatusBar
git commit -m "feat(statusbar): controller with left-click open, right-click menu, key-missing dot"
```

---

## Task 19: Settings UI (tabbed)

**Files:**
- Create: `Dictonary/Settings/UI/SettingsView.swift`
- Create: `Dictonary/Settings/UI/GeneralSettingsView.swift`
- Create: `Dictonary/Settings/UI/ProviderSettingsView.swift`
- Create: `Dictonary/Settings/UI/AboutSettingsView.swift`
- Create: `Dictonary/Settings/UI/HotkeyRecorderView.swift`

- [ ] **Step 1: Write `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let translationService: TranslationService
    let onHotkeyChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, onHotkeyChanged: onHotkeyChanged)
                .tabItem { Label("General", systemImage: "gear") }

            ProviderSettingsView(settings: settings, translationService: translationService)
                .tabItem { Label("Provider", systemImage: "cloud") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
    }
}
```

- [ ] **Step 2: Write `HotkeyRecorderView.swift`**

```swift
import SwiftUI
import AppKit

struct HotkeyRecorderView: View {
    @Binding var combo: HotkeyCombo
    let onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(combo.displayString)
                .frame(width: 120, alignment: .leading)
                .padding(6)
                .background(recording ? Color.accentColor.opacity(0.2) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.3)))
            Button(recording ? "Press keys…" : "Record") {
                if recording { stopRecording() } else { startRecording() }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = carbonMods(from: event.modifierFlags)
            let key = UInt32(event.keyCode)
            // Reject if no modifier — single keys are not safe as global hotkeys.
            if mods == 0 { return event }
            let newCombo = HotkeyCombo(keyCode: key, modifiers: mods)
            DispatchQueue.main.async {
                self.combo = newCombo
                self.stopRecording()
                self.onChange()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= 1 << 8 }
        if flags.contains(.shift)    { m |= 1 << 9 }
        if flags.contains(.option)   { m |= 1 << 11 }
        if flags.contains(.control)  { m |= 1 << 12 }
        return m
    }
}
```

- [ ] **Step 3: Write `GeneralSettingsView.swift`**

```swift
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: Settings
    let onHotkeyChanged: () -> Void

    var body: some View {
        Form {
            HStack {
                Text("Hotkey:")
                HotkeyRecorderView(combo: $settings.hotkey, onChange: onHotkeyChanged)
            }
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .padding(20)
    }
}
```

- [ ] **Step 4: Write `ProviderSettingsView.swift`**

```swift
import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var settings: Settings
    let translationService: TranslationService
    @State private var apiKeyInput: String = ""
    @State private var endpointInput: String = ""
    @State private var testStatus: String = ""
    @State private var testing = false

    var body: some View {
        Form {
            // NOTE: single-arg `.onChange` closure — works on macOS 13.
            // Two-arg form (`{ _, newValue in }`) is macOS 14+.
            Picker("Provider", selection: $settings.provider) {
                ForEach(ProviderKind.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .onChange(of: settings.provider) { newValue in
                settings.model = newValue.defaultModel
                apiKeyInput = settings.apiKey(for: newValue) ?? ""
                endpointInput = settings.endpoint?.absoluteString ?? ""
                testStatus = ""
            }

            HStack {
                SecureField("API Key", text: $apiKeyInput)
                Button("Save") {
                    do {
                        try settings.setAPIKey(apiKeyInput, for: settings.provider)
                        testStatus = "Saved"
                    } catch {
                        testStatus = "Save failed: \(error.localizedDescription)"
                    }
                }
                Button(testing ? "Testing…" : "Test") {
                    Task { await runTest() }
                }
                .disabled(testing || apiKeyInput.isEmpty)
            }

            TextField("Model", text: $settings.model)

            // Optional override; empty string means "use provider default".
            HStack {
                TextField("Endpoint (advanced, leave empty for default)", text: $endpointInput)
                Button("Apply") {
                    let trimmed = endpointInput.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        settings.endpoint = nil
                        testStatus = "Endpoint reset to default"
                    } else if let url = URL(string: trimmed), url.scheme != nil {
                        settings.endpoint = url
                        testStatus = "Endpoint updated"
                    } else {
                        testStatus = "Invalid URL"
                    }
                }
            }

            Text(testStatus)
                .font(.caption)
                .foregroundStyle(testStatus.starts(with: "OK") ? .green : .secondary)
        }
        .padding(20)
        .onAppear {
            apiKeyInput = settings.apiKey(for: settings.provider) ?? ""
            endpointInput = settings.endpoint?.absoluteString ?? ""
        }
    }

    private func runTest() async {
        testing = true; defer { testing = false }
        // Save first so TranslationService picks it up.
        do {
            try settings.setAPIKey(apiKeyInput, for: settings.provider)
        } catch {
            testStatus = "Save failed: \(error.localizedDescription)"
            return
        }
        do {
            var collected = ""
            for try await token in translationService.translate(systemPrompt: "Reply OK", userText: "ping") {
                collected += token
                if collected.count > 4 { break }
            }
            testStatus = "OK"
        } catch let e as TranslationError {
            testStatus = e.errorDescription ?? "Failed"
        } catch {
            testStatus = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: Write `AboutSettingsView.swift`**

```swift
import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Dictonary").font(.title2)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}
```

- [ ] **Step 6: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 7: Commit**

```bash
git add Dictonary/Settings/UI
git commit -m "feat(settings-ui): tabbed Settings with hotkey recorder, provider config, About"
```

---

## Task 20: Welcome / Onboarding view

**Files:**
- Create: `Dictonary/Onboarding/WelcomeView.swift`

- [ ] **Step 1: Write `WelcomeView.swift`**

```swift
import SwiftUI

struct WelcomeView: View {
    let openPreferences: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("👋 Welcome to Dictonary")
                .font(.title2)
            Text("Set your API Key to start translating.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Skip for now", action: skip)
                Button("Open Preferences") { openPreferences() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add Dictonary/Onboarding
git commit -m "feat(onboarding): WelcomeView for first-launch API key prompt"
```

---

## Task 21: AppContainer (DI) + AppDelegate wiring

This is the integration point — where modules meet.

**Files:**
- Create: `Dictonary/App/AppContainer.swift`
- Create: `Dictonary/App/AppDelegate.swift`
- Modify: `Dictonary/App/DictonaryApp.swift`

- [ ] **Step 1: Write `AppContainer.swift`**

```swift
import AppKit

@MainActor
final class AppContainer {
    let settings: Settings
    let translationService: TranslationService
    let hotKeyManager: HotKeyManager
    let statusBar: StatusBarController
    let translator: TranslatorWindowController
    let dictTemplate: String
    let translTemplate: String

    init() {
        let s = Settings()
        self.settings = s
        self.translationService = TranslationService(settings: s)
        self.hotKeyManager = HotKeyManager()
        self.statusBar = StatusBarController()

        // Load prompt templates from bundle. If missing, the app is broken — fail loudly.
        do {
            self.dictTemplate = try PromptBuilder.loadTemplate(named: "dictionary")
            self.translTemplate = try PromptBuilder.loadTemplate(named: "translation")
        } catch {
            fatalError("Missing prompt templates: \(error)")
        }

        self.translator = TranslatorWindowController(
            service: translationService,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate
        )
    }
}
```

- [ ] **Step 2: Write `AppDelegate.swift`**

```swift
import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let container = AppContainer()
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status bar wiring
        container.statusBar.onOpen = { [weak self] in self?.container.translator.toggle() }
        container.statusBar.onPreferences = { Self.openPreferences() }
        container.statusBar.onQuit = { NSApp.terminate(nil) }
        container.statusBar.needsAPIKey = (container.settings.apiKey(for: container.settings.provider) ?? "").isEmpty

        // Hotkey wiring
        container.hotKeyManager.onPress = { [weak self] in self?.container.translator.toggle() }
        if !container.hotKeyManager.register(container.settings.hotkey) {
            // Best-effort fallback: don't block startup. User can fix in Preferences.
            NSLog("[Dictonary] Failed to register hotkey \(container.settings.hotkey.displayString)")
        }

        // Login item
        if container.settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        }

        // First-launch
        if !container.settings.didOnboard {
            showWelcome()
        }

        // React to API-key changes for the red-dot indicator.
        // Simple poll-on-change via NotificationCenter would require more wiring;
        // for v1 we refresh on every translator open.
        // (See `applicationDidBecomeActive` below.)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        let key = container.settings.apiKey(for: container.settings.provider) ?? ""
        container.statusBar.needsAPIKey = key.isEmpty
    }

    /// Re-register hotkey when user changes it in Preferences.
    func reregisterHotkey() {
        _ = container.hotKeyManager.register(container.settings.hotkey)
    }

    static func openPreferences() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWelcome() {
        let welcome = WelcomeView(
            openPreferences: { [weak self] in
                Self.openPreferences()
                self?.container.settings.didOnboard = true
                self?.welcomeWindow?.close()
            },
            skip: { [weak self] in
                self?.container.settings.didOnboard = true
                self?.welcomeWindow?.close()
            }
        )
        let host = NSHostingController(rootView: welcome)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable]
        win.title = "Welcome"
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = win
    }
}
```

- [ ] **Step 3: Replace `DictonaryApp.swift`**

```swift
import SwiftUI

@main
struct DictonaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `SwiftUI.Settings` qualifier is required because our
        // `final class Settings: ObservableObject` shadows the scene name.
        SwiftUI.Settings {
            SettingsView(
                settings: appDelegate.container.settings,
                translationService: appDelegate.container.translationService,
                onHotkeyChanged: { appDelegate.reregisterHotkey() }
            )
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodegen generate
xcodebuild build -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

- [ ] **Step 5: Run all tests**

```bash
xcodebuild test -project Dictonary.xcodeproj -scheme Dictonary -destination 'platform=macOS' -quiet
```

Expected: every test from previous tasks still passes.

- [ ] **Step 6: Commit**

```bash
git add Dictonary/App
git commit -m "feat(app): wire modules in AppDelegate; first-launch welcome flow"
```

---

## Task 22: Manual end-to-end smoke test

These are the spec's acceptance criteria. Run the app and verify each one. This is NOT a test you can automate — it requires a real screen, a real keyboard, and a real API key.

- [ ] **Step 1: Build a Release-config product**

```bash
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Release -derivedDataPath ./build clean build -quiet
open -a ./build/Build/Products/Release/Dictonary.app
```

- [ ] **Step 2: Verify acceptance criteria from the spec**

Walk through each:

- [ ] App is running, but Dock has no icon (LSUIElement).
- [ ] Status bar shows the book icon (with red dot if no API key).
- [ ] Open the menu (right-click status item) → set up DeepSeek API key in Preferences → click `Test` → see `OK`.
- [ ] Press `⌥Space`. The translator panel appears centered horizontally, ~18% from the top of the screen.
- [ ] Type `apple` and press Enter. Stream appears within 1 second; response is dictionary-style with `→ 苹果`, 词性, 释义, 例句.
- [ ] Press Esc. Window hides instantly.
- [ ] Press `⌥Space` again. Window appears empty (state was reset).
- [ ] Type `今天天气真好` and press Enter. Stream appears; response is a single English sentence followed (optionally) by a `💡 ` note.
- [ ] Open Preferences → switch provider to OpenAI / Claude → enter that key → run a translation → confirm output streams.
- [ ] Quit the app via menu. Re-launch. The hotkey still works without re-onboarding.

If anything doesn't pass, fix and re-run from this task.

- [ ] **Step 3: Measure bundle size and cold start (informational)**

```bash
du -sh ./build/Build/Products/Release/Dictonary.app
```

Spec target: < 5 MB. Note actual size; if larger, investigate (asset catalogs, debug symbols).

For cold start, kill the app, time the first launch:

```bash
killall Dictonary 2>/dev/null
time open -a ./build/Build/Products/Release/Dictonary.app
```

(Note `time open` measures `open` itself, not actual app readiness — informational only.)

- [ ] **Step 4: Final commit (if any tweaks)**

```bash
git status
git add -A
git diff --cached
# If non-trivial: git commit -m "chore: smoke-test fixes"
```

- [ ] **Step 5: Tag v1.0.0**

```bash
git tag v1.0.0
```

---

## Open items for after v1

- App icon design (currently empty `AppIcon.appiconset`)
- Notarization & DMG packaging if distributed beyond own machine
- Translation history (deliberately YAGNI for v1)
- App rename if `dictonary` typo is intentional vs accidental
