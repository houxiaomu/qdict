# Input Suggestion 下拉建议 — Milestone 2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把历史查询融合进下拉候选——同词命中两边时打"最近"角标、仅历史命中保留为单独项、按"COCA 词频得分 + 最近 7 天衰减加成"排序。

**Architecture:** 新增 `MergedSuggestionEngine`（实现 `SuggestionEngine`），内部组合 M1 的 `LocalDictionary` 与一个 `[HistoryEntry]` 快照闭包，按 spec §6.3 算法 merge + score + sort。AppContainer 把 wiring 从 `DictionaryOnlySuggestionEngine` 切换到这个新引擎；UI 层零改动（M1 时 `SuggestionRow` 已预留 `.history` / `.recent` 分支）。`TranslatorViewModel` 不变。

**Tech Stack:** SwiftUI / Combine / XCTest（项目已有）；`MainActor.assumeIsolated`（Swift 5.9，用于在非隔离引擎里安全读 `@MainActor HistoryStore.entries`）。

**Spec 引用：** `docs/superpowers/specs/2026-05-05-input-suggestion-design.md` §6.3、§10、§11。

---

## 文件结构总览

```
QDict/
  Suggestion/
    MergedSuggestionEngine.swift          ← 新增（M2 核心）
  App/
    AppContainer.swift                     ← 改：注入 MergedSuggestionEngine

QDictTests/
  Suggestion/
    MergedSuggestionEngineTests.swift      ← 新增

（无新视图、无 ViewModel 改动）
```

---

## 通用约定

- 每个 Task 末尾 `git commit`，conventional commits 风格（`feat(suggest): …` / `chore(app): …`）。
- 新文件 + 重新跑 `xcodegen` 后必须跑 `xcodebuild test`，全套测试通过才提交。
- `QDict.xcodeproj` 在 `.gitignore`，**不要 git add**。
- 先写失败的测试，再写实现；同一文件的连续小步也保留 commit 节奏（merge 逻辑 + 排序逻辑分两个 commit 落地）。

---

## Task 1：MergedSuggestionEngine — 合并层（kind / badge / 去重）

第一层只关心"哪些项进列表，每项 kind/badge 是什么"；不做排序、不做打分、不做 limit 截断（先把 merge 语义跑通）。

**Files:**
- Create: `QDict/Suggestion/MergedSuggestionEngine.swift`
- Create: `QDictTests/Suggestion/MergedSuggestionEngineTests.swift`

- [ ] **Step 1: 写测试（合并层）**

```swift
// QDictTests/Suggestion/MergedSuggestionEngineTests.swift
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
            dict: [],   // word not in dict
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
            history: [he("apple", daysAgo: 1, now: fixedNow)]   // does not match "epi"
        )
        let items = engine.query("epi", limit: 10)
        XCTAssertEqual(items.map(\.word), ["epic"])
    }

    func testDuplicateHistoryEntriesForSameWordCollapseToOneItem() {
        let engine = makeEngine(
            history: [
                he("epic", daysAgo: 5, now: fixedNow),
                he("epic", daysAgo: 1, now: fixedNow),    // newer duplicate
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
        // None should carry recent badge.
        let allBadges = engine.query("epi", limit: 10).map(\.badge)
        XCTAssertTrue(allBadges.allSatisfy { $0 == .none })
    }

    func testHistoryDisplayUsesHistoryQueryWhenDictMissesIt() {
        // Confirms id is lowercased; word (display) preserves history's original casing.
        let engine = makeEngine(
            history: [he("Epiphany", daysAgo: 1, now: fixedNow)]
        )
        let items = engine.query("epi", limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "epiphany")
        XCTAssertEqual(items[0].word, "Epiphany")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 编译失败，`cannot find 'MergedSuggestionEngine' in scope`。

- [ ] **Step 3: 实现合并层（先不做排序/打分/截断）**

```swift
// QDict/Suggestion/MergedSuggestionEngine.swift
import Foundation

/// Milestone 2 engine: merges local-dictionary prefix hits with the user's
/// recent query history, marking same-word matches with a "recent" badge
/// and surfacing history-only hits (words not in the dict) as their own
/// kind. Final ranking and ``limit`` enforcement are layered on top in a
/// follow-up step.
///
/// Not ``@MainActor`` — the engine is a value type called synchronously
/// from ``TranslatorViewModel`` (which *is* main-actor isolated). Accessing
/// the main-actor ``HistoryStore.entries`` is funnelled through the
/// ``historySnapshot`` closure provided at wiring time; that closure is
/// expected to be invoked on the main thread, where ``MainActor.assumeIsolated``
/// can read the published array safely.
struct MergedSuggestionEngine: SuggestionEngine {
    let dict: LocalDictionary
    let historySnapshot: () -> [HistoryEntry]
    let now: () -> Date

    init(
        dict: LocalDictionary,
        historySnapshot: @escaping () -> [HistoryEntry],
        now: @escaping () -> Date = Date.init
    ) {
        self.dict = dict
        self.historySnapshot = historySnapshot
        self.now = now
    }

    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        let lowerPrefix = prefix.lowercased()
        guard !lowerPrefix.isEmpty else { return [] }

        // Take a few extra dict hits — they're cheap and we may filter
        // duplicates after merge.
        let dictHits = dict.prefix(prefix, limit: limit + 4)

        // Filter history to entries whose lowercased query starts with the
        // requested prefix; collapse same-word duplicates (most-recent wins).
        var historyByLower: [String: HistoryEntry] = [:]
        for entry in historySnapshot() {
            let lower = entry.query.lowercased()
            guard lower.hasPrefix(lowerPrefix) else { continue }
            if let existing = historyByLower[lower], existing.timestamp >= entry.timestamp {
                continue
            }
            historyByLower[lower] = entry
        }

        // Merge: dict-hit drives display when present; history augments it
        // with the .recent badge. History-only entries become .history items.
        var items: [SuggestionItem] = []
        var seenLower = Set<String>()

        for e in dictHits {
            let lower = e.word.lowercased()
            seenLower.insert(lower)
            let isRecent = historyByLower[lower] != nil
            items.append(SuggestionItem(
                id: lower,
                kind: .dictionary,
                word: e.word,
                pos: e.pos,
                gloss: e.gloss,
                badge: isRecent ? .recent : .none
            ))
        }

        for (lower, entry) in historyByLower where !seenLower.contains(lower) {
            items.append(SuggestionItem(
                id: lower,
                kind: .history,
                word: entry.query,
                pos: nil,
                gloss: "",          // gloss filled later if/when we cache results
                badge: .recent
            ))
        }

        return items
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Suggestion/MergedSuggestionEngine.swift QDictTests/Suggestion/MergedSuggestionEngineTests.swift
git commit -m "feat(suggest): add MergedSuggestionEngine merging layer (M2)"
```

---

## Task 2：MergedSuggestionEngine — 排序、打分、limit 截断

把 spec §6.3 的打分公式装到合并层之上：`final = dictScore + α · histBonus`，其中 `dictScore = (10000 - min(coca, 10000)) / 1000`，`histBonus = 5.0 * exp(-daysSince / 7.0)`。最后按 final 降序、应用 `limit`。

**Files:**
- Modify: `QDict/Suggestion/MergedSuggestionEngine.swift`
- Modify: `QDictTests/Suggestion/MergedSuggestionEngineTests.swift`

- [ ] **Step 1: 加测试（排序 + 打分 + limit）**

在 `MergedSuggestionEngineTests.swift` 末尾追加：

```swift
final class MergedSuggestionEngineScoringTests: XCTestCase {
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

    func testTodaysHistoryHitClimbsAheadOfMoreCommonDictWord() {
        // "epic" is more common (coca=100, dictScore≈9.99); "epitome" is rarer
        // (coca=4000, dictScore≈6.0). With a today bonus (+5.0), "epitome"
        // should outrank "epic".
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic",    pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epitome", pos: nil, gloss: "g", cocaRank: 4000),
            ],
            history: [he("epitome", daysAgo: 0, now: fixedNow)]
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order.first, "epitome")
        XCTAssertEqual(order.dropFirst().first, "epic")
    }

    func testTwoWeekOldHistoryAlmostStopsBoosting() {
        // 14 days ago: bonus ≈ 5 * exp(-2) ≈ 0.68. "epic" (dictScore≈9.99)
        // should still beat "epitome" (dictScore≈6.0 + 0.68 = 6.68).
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic",    pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epitome", pos: nil, gloss: "g", cocaRank: 4000),
            ],
            history: [he("epitome", daysAgo: 14, now: fixedNow)]
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order.first, "epic")
    }

    func testHistoryOnlyHitOutranksLowFrequencyDictWord() {
        // History-only word has dictScore = 0 (cocaRank treated as missing,
        // which scores at 0..1 range), but a today bonus pushes it ahead of
        // a long-tail dict word.
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epitomize", pos: nil, gloss: "g", cocaRank: 12000),
            ],
            history: [he("epiphany", daysAgo: 0, now: fixedNow)]
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order.first, "epiphany")
        XCTAssertEqual(order.dropFirst().first, "epitomize")
    }

    func testLimitIsAppliedToFinalSortedSet() {
        let dict = (0..<8).map { i in
            DictionaryEntry(word: "epi\(i)", pos: nil, gloss: "g", cocaRank: 100 + i * 10)
        }
        let engine = makeEngine(dict: dict, history: [])
        XCTAssertEqual(engine.query("epi", limit: 3).count, 3)
    }

    func testDictHitsAndHistoryOnlyHitsCompeteForTheSameLimit() {
        let engine = makeEngine(
            dict: [
                DictionaryEntry(word: "epic",    pos: nil, gloss: "g", cocaRank: 100),
                DictionaryEntry(word: "epidemic", pos: nil, gloss: "g", cocaRank: 4000),
                DictionaryEntry(word: "epilogue", pos: nil, gloss: "g", cocaRank: 8000),
            ],
            history: [
                he("epiphany", daysAgo: 0, now: fixedNow),  // history-only, +5 bonus
                he("epitome", daysAgo: 30, now: fixedNow),  // history-only, ~0 bonus
            ]
        )
        // Limit 3: rankings (approx) — epic 9.99, epiphany 5.0, epidemic 6.0,
        // epilogue 2.0, epitome ≈ 0 + 0.07 ≈ 0.07.
        // So top 3 should be: epic, epidemic, epiphany (in that score order).
        let top3 = engine.query("epi", limit: 3).map(\.word)
        XCTAssertEqual(top3, ["epic", "epidemic", "epiphany"])
    }

    func testCocaRankAtMaxIntScoresAsUnranked() {
        // Sanity: a dict entry with cocaRank == .max (i.e. unranked, our
        // standard sentinel) must not produce a NaN/overflowing dictScore.
        let engine = makeEngine(
            dict: [DictionaryEntry(word: "epic", pos: nil, gloss: "g", cocaRank: .max)],
            history: []
        )
        let order = engine.query("epi", limit: 10).map(\.word)
        XCTAssertEqual(order, ["epic"])    // doesn't crash, returns the entry
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 排序相关用例失败（合并层目前没排序，limit 也不裁剪）。

- [ ] **Step 3: 把排序 + 打分 + limit 加进 query()**

替换 `MergedSuggestionEngine.query` 为：

```swift
func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
    let lowerPrefix = prefix.lowercased()
    guard !lowerPrefix.isEmpty else { return [] }

    let dictHits = dict.prefix(prefix, limit: limit + 4)

    var historyByLower: [String: HistoryEntry] = [:]
    for entry in historySnapshot() {
        let lower = entry.query.lowercased()
        guard lower.hasPrefix(lowerPrefix) else { continue }
        if let existing = historyByLower[lower], existing.timestamp >= entry.timestamp {
            continue
        }
        historyByLower[lower] = entry
    }

    /// Final score: dict-frequency component plus a recency bonus that
    /// decays with a 7-day half-life (see spec §6.3). The α coefficient
    /// is calibrated so a today-fresh history hit can lift a mid-frequency
    /// word ahead of a top-tier dict word.
    struct Scored {
        let item: SuggestionItem
        let score: Double
    }

    let nowDate = now()
    func dictScore(forCocaRank coca: Int) -> Double {
        let clamped = min(coca, 10000)
        return Double(10000 - clamped) / 1000.0
    }
    func historyBonus(daysSince days: Double) -> Double {
        return 5.0 * exp(-days / 7.0)
    }

    var scored: [Scored] = []
    var seenLower = Set<String>()

    for e in dictHits {
        let lower = e.word.lowercased()
        seenLower.insert(lower)
        let recentEntry = historyByLower[lower]
        let bonus: Double
        if let entry = recentEntry {
            let days = nowDate.timeIntervalSince(entry.timestamp) / 86400.0
            bonus = historyBonus(daysSince: max(0, days))
        } else {
            bonus = 0
        }
        let item = SuggestionItem(
            id: lower,
            kind: .dictionary,
            word: e.word,
            pos: e.pos,
            gloss: e.gloss,
            badge: recentEntry == nil ? .none : .recent
        )
        scored.append(Scored(item: item, score: dictScore(forCocaRank: e.cocaRank) + bonus))
    }

    for (lower, entry) in historyByLower where !seenLower.contains(lower) {
        let days = nowDate.timeIntervalSince(entry.timestamp) / 86400.0
        let item = SuggestionItem(
            id: lower,
            kind: .history,
            word: entry.query,
            pos: nil,
            gloss: "",
            badge: .recent
        )
        scored.append(Scored(item: item, score: historyBonus(daysSince: max(0, days))))
    }

    return scored
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map(\.item)
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: 新增 6 个排序测试 + 之前 8 个合并层测试都 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Suggestion/MergedSuggestionEngine.swift QDictTests/Suggestion/MergedSuggestionEngineTests.swift
git commit -m "feat(suggest): add scoring + sort + limit to MergedSuggestionEngine"
```

---

## Task 3：AppContainer 切换到 MergedSuggestionEngine

**Files:**
- Modify: `QDict/App/AppContainer.swift`

- [ ] **Step 1: 替换 wiring**

把现有的：

```swift
let dict = DictionaryLoader.loadBundled()
let suggestionEngine = DictionaryOnlySuggestionEngine(dict: dict)
```

改成：

```swift
let dict = DictionaryLoader.loadBundled()
let storeForSnapshot = store
let suggestionEngine = MergedSuggestionEngine(
    dict: dict,
    historySnapshot: { MainActor.assumeIsolated { storeForSnapshot.entries } }
)
```

`MainActor.assumeIsolated` 是 Swift 5.9 提供的同步断言：声明"此处必然在 main actor 上"，允许在非隔离闭包中读 `@MainActor HistoryStore.entries`。本工程的调用链 `TranslatorViewModel.refreshSuggestions`（@MainActor）→ `engine.query` → 这个闭包，全程在主线程，断言成立。

`storeForSnapshot = store` 这一步是为了避免在闭包里直接捕获 `self.historyStore` 时与 init 内的 `self.translator = …` 顺序产生纠葛——sequence 上 `store` 已经存在，闭包对它的强引用安全且无环（store 是 AppContainer 的属性、AppContainer 是 app 生命周期单例）。

- [ ] **Step 2: 编译并跑全套测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 全部 PASS（既有 + 新增的 14 个 M2 测试 = 132 个总 / 0 跳过）。

- [ ] **Step 3: Commit**

```bash
git add QDict/App/AppContainer.swift
git commit -m "feat(app): swap DictionaryOnly for MergedSuggestionEngine"
```

---

## Task 4：手动 smoke

**Files:** 无代码改动。

- [ ] **Step 1: 跑 Debug build 启动 app**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" build 2>&1 | tail -3
open "$(xcodebuild -scheme QDict -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F'= ' '/CONFIGURATION_BUILD_DIR/ {print $2; exit}')/QDict.app"
```

- [ ] **Step 2: 走 smoke 清单**

要求每条都能复现。**前置条件**：用 1.0.2 版查过几次词（`epitome`、`apple` 等任意两三个），让 HistoryStore 有数据；如果之前已经查过，直接跳到验证清单。

- [ ] 输入 `epi` → 下拉里至少一行带"最近"角标（你查过的那个词或词典里同名词条）。
- [ ] 选中带角标的那行后按 ↵ → 跟之前一样起 LLM 翻译。
- [ ] 历史里有但词典没有的词（自造词或 ECDICT 没收的，例如 1.0.2 词典没有 `serendipity`、`epinephrine` 等中等冷僻词）—— 输入对应前缀 → 下拉里出现一行 `🕘` 图标 + "最近"角标的"history-only"项。
- [ ] 历史里查过的常用词（如 `apple`）输入 `app` → 该词排序明显前移；不查它时输入 `app` 排第一的可能是 `apparently / appear / approach` 等 —— 至少 `apple` 因为最近被查过应该上窜。
- [ ] Cmd+Y 打开历史抽屉 → 下拉隐藏（互斥），关抽屉后下拉回归。
- [ ] 清空输入框（X 按钮 / 全选删除）→ 下拉清空，无残留。

任一条不对，停下来定位问题再说，不要赶着做收尾。

---

## 不在本计划范围内

- 拼写联想（M3 候选项；spec §2 明确排除）。
- 用户可见的"建议偏好"开关（spec §2 排除）。
- α 系数的运行时调参（保留为代码常量，见 §6.3）。
- 历史项的 gloss 回填（如果想让 `.history` kind 也显示中文短释，要拿历史的 result 摘第一行——目前 history-only 行 gloss 留空。如果发现影响体感再独立立项）。
- 版本号 bump / dmg 打包：M2 落 main 后由用户决定何时切 1.0.3，单独走，跟本计划解耦。

---

## 验收

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -5
```

Expected: 132 tests PASS, 0 skipped, 0 failures。

Spec 覆盖度 mapping：

| Spec 节 | 实施 Task |
|---|---|
| §6.3 MergedSuggestionEngine 算法 | 1, 2 |
| §10 二期测试套 | 1, 2 |
| §11.M2 历史融合 / "最近"角标 / 同词去重 | 1, 2, 3 |
| §11.不做项（拼写联想、偏好开关、运行时词库更新） | 全部不做（见"不在本计划范围内"） |
