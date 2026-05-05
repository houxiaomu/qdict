# Input Suggestion 下拉建议 — Milestone 1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 QDict 主面板加上"输入即出"的本地英文词典前缀建议下拉，含选中态、Tab 补全、↵ 路由、Esc 撤回。Milestone 1 不做历史融合（留给 M2）。

**Architecture:** 新增两个独立模块——`Dictionary/`（封装 ECDICT 子集 SQLite 与前缀查询）和 `Suggestion/`（视图层访问数据的唯一入口）；`TranslatorViewModel` 增 4 个 `@Published` + 5 个方法；新增 `TranslatorSuggestionsView` 嵌在输入框与 hints 之间；`TranslatorWindowController` 扩展键盘路由表。任何加载失败都安静降级——下拉永远为空，主流程不受影响。

**Tech Stack:** SwiftUI / Combine / XCTest（项目已有）；`import SQLite3`（系统库，无新 SwiftPM 依赖）；构建脚本用 Python 3（macOS 自带）。

**Spec 引用：** `docs/superpowers/specs/2026-05-05-input-suggestion-design.md`

---

## 文件结构总览

```
QDict/
  Dictionary/                              ← 新增模块
    DictionaryEntry.swift                  // word / pos / gloss / cocaRank
    LocalDictionary.swift                  // protocol
    EmptyLocalDictionary.swift             // 降级实现
    SQLiteDatabase.swift                   // sqlite3 C API 薄包装
    SQLiteLocalDictionary.swift            // LocalDictionary impl
    DictionaryLoader.swift                 // bundle path + 降级
    Resources/
      ecdict.sqlite                        // 预生成产物，bundle 进 app
  Suggestion/                              ← 新增模块
    SuggestionItem.swift                   // 视图统一结构
    SuggestionEngine.swift                 // protocol
    DictionaryOnlySuggestionEngine.swift   // M1 实现
  Window/
    TranslatorContentView.swift            // 改：VM 增量、视图 wiring
    TranslatorSuggestionsView.swift        // 新增视图
    TranslatorWindowController.swift       // 改：键盘路由
  App/
    AppContainer.swift                     // 改：wire LocalDictionary
  Resources/
    THIRD_PARTY_LICENSES.md                // 新增

QDictTests/
  Dictionary/
    DictionaryEntryTests.swift
    EmptyLocalDictionaryTests.swift
    SQLiteDatabaseTests.swift
    SQLiteLocalDictionaryTests.swift
    DictionaryLoaderTests.swift
  Suggestion/
    SuggestionItemTests.swift
    DictionaryOnlySuggestionEngineTests.swift
  Window/
    TranslatorViewModelSuggestionTests.swift   // 新增（与现有 TranslatorViewModelTests.swift 并列）

scripts/
  build-dictionary.py                      // 新增：CSV → SQLite

project.yml                                // 改：注册 Dictionary/Suggestion 目录 + ecdict.sqlite 资源
```

---

## 通用约定

- **测试驱动**：每个有逻辑的单元先写失败的测试，再实现。
- **小步提交**：每个 Task 末尾 commit，commit message 用 conventional commits（`feat(dict): ...`、`test(suggest): ...`、`refactor(window): ...`、`chore(project): ...`）。
- **构建命令**：`xcodegen` 后 `xcodebuild -scheme QDict -destination "platform=macOS" build`；测试 `xcodebuild -scheme QDict -destination "platform=macOS" test`。
- **每完成一个 Task 跑测试**：本地至少跑 `xcodebuild ... test`；命令在每个 Task 的"Run tests"步骤里写明。
- **新建文件后必须 `xcodegen`** 把它注册进 `.xcodeproj`，否则 `xcodebuild` 找不到。

---

## Task 1：写 ECDICT → SQLite 构建脚本

**Files:**
- Create: `scripts/build-dictionary.py`
- Create: `scripts/README-dictionary.md`

- [ ] **Step 1: 写脚本**

```python
#!/usr/bin/env python3
"""
Build QDict's bundled English dictionary from ECDICT CSV.

Usage:
    python3 scripts/build-dictionary.py /path/to/ecdict.csv \\
        QDict/Dictionary/Resources/ecdict.sqlite

Source: https://github.com/skywind3000/ECDICT — use the "ECDICT" or
"ECDICT_FREE" CSV release. License is MIT.

Filter rules (see spec §5.1):
    keep if (frq <= 15000) OR (collins >= 1) OR (oxford == 1)
    exclude if word starts with capital letter (proper nouns)
    exclude if word contains '_'
    exclude if translation empty
"""
import csv
import os
import sqlite3
import sys


GLOSS_MAX = 80


def normalize_gloss(raw: str) -> str:
    g = raw.replace("\\r", "").replace("\\n", "；").strip()
    if len(g) > GLOSS_MAX:
        g = g[: GLOSS_MAX - 1] + "…"
    return g


def normalize_pos(raw: str) -> str | None:
    p = (raw or "").strip()
    return p if p else None


def parse_int(raw: str) -> int | None:
    s = (raw or "").strip()
    if not s:
        return None
    try:
        return int(s)
    except ValueError:
        return None


def should_keep(word: str, translation: str, frq, collins, oxford) -> bool:
    if not word or not translation:
        return False
    if word[0].isupper():
        return False
    if "_" in word:
        return False
    if frq is not None and frq <= 15000:
        return True
    if collins is not None and collins >= 1:
        return True
    if oxford == 1:
        return True
    return False


def build(csv_path: str, sqlite_path: str) -> None:
    if os.path.exists(sqlite_path):
        os.remove(sqlite_path)
    os.makedirs(os.path.dirname(sqlite_path), exist_ok=True)

    conn = sqlite3.connect(sqlite_path)
    conn.execute("PRAGMA journal_mode = OFF")
    conn.execute("PRAGMA synchronous = OFF")
    conn.execute(
        """
        CREATE TABLE entries (
            word    TEXT NOT NULL PRIMARY KEY,
            display TEXT NOT NULL,
            pos     TEXT,
            gloss   TEXT NOT NULL,
            coca    INTEGER,
            collins INTEGER
        )
        """
    )

    kept = 0
    skipped = 0
    seen_lower: set[str] = set()
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = (row.get("word") or "").strip()
            translation = (row.get("translation") or "").strip()
            frq = parse_int(row.get("frq", ""))
            collins = parse_int(row.get("collins", ""))
            oxford = parse_int(row.get("oxford", ""))
            if not should_keep(word, translation, frq, collins, oxford):
                skipped += 1
                continue
            lower = word.lower()
            if lower in seen_lower:
                skipped += 1
                continue
            seen_lower.add(lower)
            conn.execute(
                "INSERT INTO entries (word, display, pos, gloss, coca, collins) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    lower,
                    word,
                    normalize_pos(row.get("pos", "")),
                    normalize_gloss(translation),
                    frq,
                    collins,
                ),
            )
            kept += 1
    conn.commit()
    conn.execute("VACUUM")
    conn.close()

    size_mb = os.path.getsize(sqlite_path) / (1024 * 1024)
    print(f"Kept {kept} entries (skipped {skipped}). Output: {sqlite_path} ({size_mb:.2f} MB)")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    build(sys.argv[1], sys.argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: 写 README**

写到 `scripts/README-dictionary.md`：

```markdown
# Dictionary build

QDict ships an offline English dictionary at
`QDict/Dictionary/Resources/ecdict.sqlite`. It is generated from
[ECDICT](https://github.com/skywind3000/ECDICT) (MIT) by
`scripts/build-dictionary.py`.

## Regenerate

1. Download ECDICT CSV (e.g. `ecdict.csv` from the project's GitHub releases).
2. From the repo root:

   ```bash
   python3 scripts/build-dictionary.py /path/to/ecdict.csv \\
       QDict/Dictionary/Resources/ecdict.sqlite
   ```

3. Commit the regenerated `ecdict.sqlite` alongside any related changes.

## Filter rules

See spec §5.1 in `docs/superpowers/specs/2026-05-05-input-suggestion-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add scripts/build-dictionary.py scripts/README-dictionary.md
git commit -m "chore(scripts): add ECDICT → SQLite build script"
```

---

## Task 2：生成并提交 ecdict.sqlite

**Files:**
- Create: `QDict/Dictionary/Resources/ecdict.sqlite`

- [ ] **Step 1: 下载 ECDICT CSV**

由开发者从 https://github.com/skywind3000/ECDICT/releases 下载 `ecdict.csv` 到本地任意位置（如 `~/Downloads/ecdict.csv`）。CSV 大小约 70–80 MB。

- [ ] **Step 2: 跑构建脚本**

```bash
mkdir -p QDict/Dictionary/Resources
python3 scripts/build-dictionary.py ~/Downloads/ecdict.csv \
    QDict/Dictionary/Resources/ecdict.sqlite
```

Expected: 控制台打印 `Kept 12000–18000 entries ... ecdict.sqlite (5–8 MB)`。如果 size 远大于 8 MB，先 `sqlite3 QDict/Dictionary/Resources/ecdict.sqlite .schema` 检查是否有意外索引。

- [ ] **Step 3: 抽样验证**

```bash
sqlite3 QDict/Dictionary/Resources/ecdict.sqlite \
    "SELECT word, pos, substr(gloss, 1, 30), coca FROM entries WHERE word LIKE 'epi%' ORDER BY coca LIMIT 10;"
```

Expected: 出现 `epic / episode / epidemic / epitome / epiphany` 等词。

- [ ] **Step 4: Commit**

```bash
git add QDict/Dictionary/Resources/ecdict.sqlite
git commit -m "chore(dict): generate bundled ECDICT subset (~XX MB)"
```

（commit message 里 XX 替换为实际产物大小，方便后续审计 PR diff）

---

## Task 3：把新目录与资源接入 project.yml

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: 改 project.yml**

把 QDict target 的 `resources` 段加入 `ecdict.sqlite`：

```yaml
    resources:
      - path: QDict/Prompt/Prompts
      - path: QDict/Resources/Assets.xcassets
      - path: QDict/Dictionary/Resources/ecdict.sqlite
```

QDict target 的 `sources: - path: QDict` 是递归的，所以新加的 `Dictionary/` 和 `Suggestion/` 目录里 `*.swift` 自动会被收进编译；不需要改 sources。

QDictTests target 的 `sources: - path: QDictTests` 同理，新建子目录里的 *.swift 自动收。

- [ ] **Step 2: 重新生成 .xcodeproj**

```bash
xcodegen
```

Expected: `Generated project successfully`。

- [ ] **Step 3: 编译验证（此时无新代码，只验证资源被打包）**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: Commit**

```bash
git add project.yml QDict.xcodeproj
git commit -m "chore(project): bundle ecdict.sqlite as app resource"
```

---

## Task 4：DictionaryEntry struct + 测试

**Files:**
- Create: `QDict/Dictionary/DictionaryEntry.swift`
- Create: `QDictTests/Dictionary/DictionaryEntryTests.swift`

- [ ] **Step 1: 写失败的测试**

```swift
// QDictTests/Dictionary/DictionaryEntryTests.swift
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
```

- [ ] **Step 2: 重新生成 project，跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'DictionaryEntry' in scope`。

- [ ] **Step 3: 实现**

```swift
// QDict/Dictionary/DictionaryEntry.swift
import Foundation

struct DictionaryEntry: Equatable {
    let word: String       // display form (original case)
    let pos: String?       // 已截短的词性，如 "n." / "adj."；nil 表示词条未提供
    let gloss: String      // 单行中文释义，已截断
    let cocaRank: Int      // 越小越常用；缺失视作 .max
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -20
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Dictionary/DictionaryEntry.swift QDictTests/Dictionary/DictionaryEntryTests.swift QDict.xcodeproj
git commit -m "feat(dict): add DictionaryEntry struct"
```

---

## Task 5：LocalDictionary protocol + EmptyLocalDictionary

**Files:**
- Create: `QDict/Dictionary/LocalDictionary.swift`
- Create: `QDict/Dictionary/EmptyLocalDictionary.swift`
- Create: `QDictTests/Dictionary/EmptyLocalDictionaryTests.swift`

- [ ] **Step 1: 写测试**

```swift
// QDictTests/Dictionary/EmptyLocalDictionaryTests.swift
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
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 编译失败，`cannot find 'LocalDictionary' in scope`。

- [ ] **Step 3: 实现 protocol**

```swift
// QDict/Dictionary/LocalDictionary.swift
import Foundation

/// Read-only English dictionary used by the suggestion dropdown.
///
/// Implementations must be safe to call from the main actor; queries should
/// be cheap (target: < 1ms) since they fire on every keystroke.
protocol LocalDictionary {
    /// Return entries whose lowercased word starts with `prefix.lowercased()`,
    /// sorted by COCA rank ascending (most common first), capped at `limit`.
    /// Inputs longer than 32 bytes are truncated by the implementation.
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry]
}
```

- [ ] **Step 4: 实现 Empty fallback**

```swift
// QDict/Dictionary/EmptyLocalDictionary.swift
import Foundation

/// Used when the bundled SQLite cannot be opened; degrades QDict to its
/// pre-suggestion behavior (no dropdown, no error UI).
struct EmptyLocalDictionary: LocalDictionary {
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry] { [] }
}
```

- [ ] **Step 5: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add QDict/Dictionary/LocalDictionary.swift QDict/Dictionary/EmptyLocalDictionary.swift QDictTests/Dictionary/EmptyLocalDictionaryTests.swift QDict.xcodeproj
git commit -m "feat(dict): add LocalDictionary protocol and EmptyLocalDictionary"
```

---

## Task 6：SQLiteDatabase 薄包装 + 测试

封装 `sqlite3` C API 的最小子集——open / close / execute / prepare / bind / step / column 读取。**只暴露我们用到的形态**，不做通用 ORM。

**Files:**
- Create: `QDict/Dictionary/SQLiteDatabase.swift`
- Create: `QDictTests/Dictionary/SQLiteDatabaseTests.swift`

- [ ] **Step 1: 写测试（用内存 DB 验证 happy path 与错误路径）**

```swift
// QDictTests/Dictionary/SQLiteDatabaseTests.swift
import XCTest
@testable import QDict

final class SQLiteDatabaseTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let db = try SQLiteDatabase(memory: ())
        try db.execute("CREATE TABLE t (k TEXT PRIMARY KEY, v INTEGER)")
        try db.execute("INSERT INTO t (k, v) VALUES ('a', 1), ('b', 2)")

        let stmt = try db.prepare("SELECT k, v FROM t ORDER BY k")
        var rows: [(String, Int)] = []
        while try stmt.step() {
            rows.append((stmt.text(0) ?? "", stmt.int(1) ?? -1))
        }
        XCTAssertEqual(rows.map(\.0), ["a", "b"])
        XCTAssertEqual(rows.map(\.1), [1, 2])
    }

    func testBindString() throws {
        let db = try SQLiteDatabase(memory: ())
        try db.execute("CREATE TABLE t (k TEXT)")
        try db.execute("INSERT INTO t (k) VALUES ('apple'), ('apricot'), ('banana')")

        let stmt = try db.prepare("SELECT k FROM t WHERE k >= ? AND k < ? ORDER BY k")
        try stmt.bind(1, "ap")
        try stmt.bind(2, "aq")

        var found: [String] = []
        while try stmt.step() { found.append(stmt.text(0) ?? "") }
        XCTAssertEqual(found, ["apple", "apricot"])
    }

    func testOpenMissingFileThrows() {
        XCTAssertThrowsError(try SQLiteDatabase(path: "/nonexistent/qdict-test.sqlite", readOnly: true))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `cannot find 'SQLiteDatabase' in scope`。

- [ ] **Step 3: 实现包装**

```swift
// QDict/Dictionary/SQLiteDatabase.swift
import Foundation
import SQLite3

/// Errors thrown by ``SQLiteDatabase`` and ``SQLiteStatement``.
enum SQLiteError: Error, CustomStringConvertible {
    case open(code: Int32, message: String)
    case prepare(code: Int32, message: String, sql: String)
    case bind(code: Int32, message: String)
    case step(code: Int32, message: String)

    var description: String {
        switch self {
        case let .open(c, m):     return "SQLite open failed (\\(c)): \\(m)"
        case let .prepare(c, m, sql): return "SQLite prepare failed (\\(c)) for [\\(sql)]: \\(m)"
        case let .bind(c, m):     return "SQLite bind failed (\\(c)): \\(m)"
        case let .step(c, m):     return "SQLite step failed (\\(c)): \\(m)"
        }
    }
}

/// Thin wrapper over the system ``sqlite3`` C API. Supports the small surface
/// our dictionary needs: open (file or memory), execute, prepare, bind, step.
final class SQLiteDatabase {
    fileprivate let db: OpaquePointer

    /// Open a database file. Pass ``readOnly: true`` for bundled resources.
    init(path: String, readOnly: Bool) throws {
        var handle: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw SQLiteError.open(code: rc, message: msg)
        }
        self.db = handle
    }

    /// Open an in-memory database (used by tests).
    init(memory: Void) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            ":memory:", &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        )
        guard rc == SQLITE_OK, let handle else {
            throw SQLiteError.open(code: rc, message: "in-memory open failed")
        }
        self.db = handle
    }

    deinit { sqlite3_close(db) }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        guard rc == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.prepare(code: rc, message: msg, sql: sql)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(code: rc, message: msg, sql: sql)
        }
        return SQLiteStatement(stmt: stmt, db: db)
    }
}

/// A prepared statement; finalize automatically on deinit.
final class SQLiteStatement {
    private let stmt: OpaquePointer
    private let db: OpaquePointer

    fileprivate init(stmt: OpaquePointer, db: OpaquePointer) {
        self.stmt = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(stmt) }

    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    func bind(_ index: Int32, _ text: String) throws {
        let rc = sqlite3_bind_text(stmt, index, text, -1, Self.SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw SQLiteError.bind(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    func bind(_ index: Int32, _ value: Int) throws {
        let rc = sqlite3_bind_int64(stmt, index, sqlite3_int64(value))
        guard rc == SQLITE_OK else {
            throw SQLiteError.bind(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Step the statement. Returns true if a row is available; false at end.
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteError.step(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    func text(_ column: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cstr)
    }

    func int(_ column: Int32) -> Int? {
        let type = sqlite3_column_type(stmt, column)
        guard type != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, column))
    }
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: 三个测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Dictionary/SQLiteDatabase.swift QDictTests/Dictionary/SQLiteDatabaseTests.swift QDict.xcodeproj
git commit -m "feat(dict): add thin sqlite3 C API wrapper"
```

---

## Task 7：SQLiteLocalDictionary + 测试

**Files:**
- Create: `QDict/Dictionary/SQLiteLocalDictionary.swift`
- Create: `QDictTests/Dictionary/SQLiteLocalDictionaryTests.swift`

- [ ] **Step 1: 写测试**

```swift
// QDictTests/Dictionary/SQLiteLocalDictionaryTests.swift
import XCTest
@testable import QDict

final class SQLiteLocalDictionaryTests: XCTestCase {
    private func makeFixtureDB() throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(memory: ())
        try db.execute("""
            CREATE TABLE entries (
                word    TEXT NOT NULL PRIMARY KEY,
                display TEXT NOT NULL,
                pos     TEXT,
                gloss   TEXT NOT NULL,
                coca    INTEGER,
                collins INTEGER
            )
        """)
        try db.execute("""
            INSERT INTO entries (word, display, pos, gloss, coca, collins) VALUES
              ('epic',     'epic',     'adj.', '史诗的；宏大的',    150,  4),
              ('episode',  'episode',  'n.',   '一集；插曲',        300,  4),
              ('epitome',  'epitome',  'n.',   '典型；缩影',       4000,  3),
              ('epiphany', 'epiphany', 'n.',   '顿悟；主显节',     6000,  2),
              ('epidemic', 'epidemic', 'n.',   '流行病；传染病',   2200,  3),
              ('epinephrine','epinephrine','n.','肾上腺素',       12000,  1),
              ('apple',    'apple',    'n.',   '苹果',               80,  5),
              ('look up to','look up to', NULL,'尊敬',             8000,  NULL)
        """)
        return db
    }

    func testPrefixReturnsAscendingByCoca() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let words = dict.prefix("epi", limit: 6).map(\.word)
        XCTAssertEqual(words, ["epic", "episode", "epidemic", "epitome", "epiphany", "epinephrine"])
    }

    func testPrefixHonorsLimit() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        XCTAssertEqual(dict.prefix("epi", limit: 2).count, 2)
    }

    func testPrefixIsCaseInsensitive() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let upper = dict.prefix("EPI", limit: 6).map(\.word)
        let lower = dict.prefix("epi", limit: 6).map(\.word)
        XCTAssertEqual(upper, lower)
    }

    func testPrefixReturnsEmptyForUnknown() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        XCTAssertEqual(dict.prefix("xyz123", limit: 6), [])
    }

    func testPrefixSupportsPhraseEntries() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let words = dict.prefix("look u", limit: 6).map(\.word)
        XCTAssertEqual(words, ["look up to"])
    }

    func testPrefixTruncatesOverlongInput() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let huge = String(repeating: "z", count: 100)
        // Must not crash; result is empty because no word matches.
        XCTAssertEqual(dict.prefix(huge, limit: 6), [])
    }

    func testEntryFieldsArePopulated() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let e = dict.prefix("epip", limit: 1).first
        XCTAssertEqual(e?.word, "epiphany")
        XCTAssertEqual(e?.pos, "n.")
        XCTAssertEqual(e?.gloss, "顿悟；主显节")
        XCTAssertEqual(e?.cocaRank, 6000)
    }

    func testEntryWithNullPosReadsAsNil() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let e = dict.prefix("look", limit: 1).first
        XCTAssertEqual(e?.word, "look up to")
        XCTAssertNil(e?.pos)
    }

    func testEmptyPrefixReturnsEmpty() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        XCTAssertEqual(dict.prefix("", limit: 6), [])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `cannot find 'SQLiteLocalDictionary' in scope`。

- [ ] **Step 3: 实现**

```swift
// QDict/Dictionary/SQLiteLocalDictionary.swift
import Foundation

/// LocalDictionary backed by a read-only SQLite file (or in-memory DB in tests).
///
/// Query strategy: range scan on the lowercased ``word`` primary key, e.g.
/// ``WHERE word >= 'epi' AND word < 'epj'``. Cheaper than ``LIKE`` and walks
/// the index directly.
final class SQLiteLocalDictionary: LocalDictionary {
    private static let maxPrefixBytes = 32

    private let db: SQLiteDatabase

    init(db: SQLiteDatabase) { self.db = db }

    func prefix(_ s: String, limit: Int) -> [DictionaryEntry] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let lower = String(trimmed.lowercased().prefix(Self.maxPrefixBytes))
        guard let upperBound = nextStringBound(after: lower) else { return [] }

        let sql = """
            SELECT display, pos, gloss, coca
              FROM entries
             WHERE word >= ? AND word < ?
             ORDER BY (CASE WHEN coca IS NULL THEN 999999 ELSE coca END) ASC,
                      word ASC
             LIMIT ?
        """

        do {
            let stmt = try db.prepare(sql)
            try stmt.bind(1, lower)
            try stmt.bind(2, upperBound)
            try stmt.bind(3, limit)

            var out: [DictionaryEntry] = []
            while try stmt.step() {
                let display = stmt.text(0) ?? ""
                let pos = stmt.text(1)              // nil 自然映射到 Swift Optional
                let gloss = stmt.text(2) ?? ""
                let coca = stmt.int(3) ?? .max
                out.append(DictionaryEntry(
                    word: display, pos: pos, gloss: gloss, cocaRank: coca
                ))
            }
            return out
        } catch {
            // Static dictionary should never fail at query time. If it does,
            // degrade silently — better than crashing the user's keystroke.
            return []
        }
    }

    /// Compute the exclusive upper bound for a prefix scan: increment the last
    /// scalar by one. Returns nil if the input is empty.
    private func nextStringBound(after s: String) -> String? {
        guard !s.isEmpty else { return nil }
        var scalars = Array(s.unicodeScalars)
        guard let last = scalars.popLast() else { return nil }
        let next = Unicode.Scalar(last.value + 1) ?? last
        scalars.append(next)
        return String(String.UnicodeScalarView(scalars))
    }
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -20
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Dictionary/SQLiteLocalDictionary.swift QDictTests/Dictionary/SQLiteLocalDictionaryTests.swift QDict.xcodeproj
git commit -m "feat(dict): add SQLiteLocalDictionary with prefix range query"
```

---

## Task 8：DictionaryLoader + 测试

**Files:**
- Create: `QDict/Dictionary/DictionaryLoader.swift`
- Create: `QDictTests/Dictionary/DictionaryLoaderTests.swift`

- [ ] **Step 1: 写测试**

```swift
// QDictTests/Dictionary/DictionaryLoaderTests.swift
import XCTest
@testable import QDict

final class DictionaryLoaderTests: XCTestCase {
    /// Bundled DB should load and return some entries for the prefix "the".
    /// Use the QDict app bundle explicitly: in unit-test runs, ``Bundle.main``
    /// is the test runner, not the host app, so default lookup would fail.
    func testLoadBundledReturnsRealDictionary() {
        let appBundle = Bundle(for: TranslatorViewModel.self)
        let dict = DictionaryLoader.loadBundled(bundle: appBundle)
        let hits = dict.prefix("the", limit: 3)
        XCTAssertFalse(hits.isEmpty, "Bundled dictionary should have entries for 'the'")
    }

    /// Missing resource → fallback. Use a synthetic empty bundle.
    func testLoadFallsBackWhenResourceMissing() {
        // Bundle.allBundles[0] is an empty test bundle host; using a freshly
        // constructed Bundle without our resource forces the fallback path.
        let empty = Bundle(for: DictionaryLoaderTests.self)
        // The test bundle does NOT contain ecdict.sqlite, so this exercises
        // the "resource missing" branch.
        let dict = DictionaryLoader.loadBundled(bundle: empty)
        XCTAssertTrue(dict is EmptyLocalDictionary)
        XCTAssertEqual(dict.prefix("the", limit: 3), [])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `cannot find 'DictionaryLoader' in scope`。

- [ ] **Step 3: 实现**

```swift
// QDict/Dictionary/DictionaryLoader.swift
import Foundation

/// Resolves the bundled SQLite file and produces a ``LocalDictionary``.
/// Any failure (missing file, open error) silently degrades to
/// ``EmptyLocalDictionary`` so the rest of the app keeps working.
enum DictionaryLoader {
    static let resourceName = "ecdict"
    static let resourceExtension = "sqlite"

    static func loadBundled(bundle: Bundle = .main) -> LocalDictionary {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            NSLog("[QDict] dictionary resource missing — suggestions disabled")
            return EmptyLocalDictionary()
        }
        do {
            let db = try SQLiteDatabase(path: url.path, readOnly: true)
            return SQLiteLocalDictionary(db: db)
        } catch {
            NSLog("[QDict] dictionary open failed: \\(error) — suggestions disabled")
            return EmptyLocalDictionary()
        }
    }
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: 两个测试均 PASS。如果 `testLoadBundledReturnsRealDictionary` 失败，说明 ecdict.sqlite 没被打包进 test host —— 检查 Task 3 的 project.yml 改动是否生效。

- [ ] **Step 5: Commit**

```bash
git add QDict/Dictionary/DictionaryLoader.swift QDictTests/Dictionary/DictionaryLoaderTests.swift QDict.xcodeproj
git commit -m "feat(dict): add DictionaryLoader with safe fallback"
```

---

## Task 9：SuggestionItem struct + 测试

**Files:**
- Create: `QDict/Suggestion/SuggestionItem.swift`
- Create: `QDictTests/Suggestion/SuggestionItemTests.swift`

- [ ] **Step 1: 写测试**

```swift
// QDictTests/Suggestion/SuggestionItemTests.swift
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
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `cannot find 'SuggestionItem' in scope`。

- [ ] **Step 3: 实现**

```swift
// QDict/Suggestion/SuggestionItem.swift
import Foundation

/// A single row in the suggestion dropdown. M1 emits only ``.dictionary``
/// items with ``.none`` badge; M2 will introduce ``.history`` and ``.recent``.
struct SuggestionItem: Identifiable, Equatable {
    enum Kind: Equatable { case dictionary, history }
    enum Badge: Equatable { case none, recent }

    let id: String          // == word.lowercased(), used for de-dup in M2
    let kind: Kind
    let word: String        // display form
    let pos: String?
    let gloss: String
    let badge: Badge
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Suggestion/SuggestionItem.swift QDictTests/Suggestion/SuggestionItemTests.swift QDict.xcodeproj
git commit -m "feat(suggest): add SuggestionItem display struct"
```

---

## Task 10：SuggestionEngine protocol + DictionaryOnlySuggestionEngine

**Files:**
- Create: `QDict/Suggestion/SuggestionEngine.swift`
- Create: `QDict/Suggestion/DictionaryOnlySuggestionEngine.swift`
- Create: `QDictTests/Suggestion/DictionaryOnlySuggestionEngineTests.swift`

- [ ] **Step 1: 写测试**

```swift
// QDictTests/Suggestion/DictionaryOnlySuggestionEngineTests.swift
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
            DictionaryEntry(word: "w\\($0)", pos: nil, gloss: "g", cocaRank: $0)
        })
        let engine = DictionaryOnlySuggestionEngine(dict: dict)
        XCTAssertEqual(engine.query("w", limit: 3).count, 3)
    }

    func testEmptyDictionaryProducesEmpty() {
        let engine = DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())
        XCTAssertEqual(engine.query("anything", limit: 6), [])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `cannot find 'DictionaryOnlySuggestionEngine' in scope`。

- [ ] **Step 3: 实现 protocol**

```swift
// QDict/Suggestion/SuggestionEngine.swift
import Foundation

/// Single entry point through which the UI obtains dropdown suggestions.
/// The view layer never accesses ``LocalDictionary`` or ``HistoryStore``
/// directly — that decision lives here.
protocol SuggestionEngine {
    /// Best-effort, synchronous, < 1 ms. Caller is responsible for short-circuit
    /// rules (length, ASCII, idle-state, etc.); see TranslatorViewModel.
    func query(_ prefix: String, limit: Int) -> [SuggestionItem]
}
```

- [ ] **Step 4: 实现 M1 engine**

```swift
// QDict/Suggestion/DictionaryOnlySuggestionEngine.swift
import Foundation

/// Milestone 1 implementation: forwards prefix queries to the local
/// dictionary and wraps results as ``SuggestionItem``. Milestone 2 will
/// add history merging in a different concrete engine.
struct DictionaryOnlySuggestionEngine: SuggestionEngine {
    let dict: LocalDictionary

    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        dict.prefix(prefix, limit: limit).map { e in
            SuggestionItem(
                id: e.word.lowercased(),
                kind: .dictionary,
                word: e.word,
                pos: e.pos,
                gloss: e.gloss,
                badge: .none
            )
        }
    }
}
```

- [ ] **Step 5: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: 全部 PASS。

- [ ] **Step 6: Commit**

```bash
git add QDict/Suggestion/SuggestionEngine.swift QDict/Suggestion/DictionaryOnlySuggestionEngine.swift QDictTests/Suggestion/DictionaryOnlySuggestionEngineTests.swift QDict.xcodeproj
git commit -m "feat(suggest): add SuggestionEngine protocol + dictionary-only impl"
```

---

## Task 11：TranslatorViewModel — 增字段 + isSuggestionsVisible + 注入 engine

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`（`TranslatorViewModel` 在这个文件里）
- Create: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

注：现有 `TranslatorViewModel` init 没有 engine 参数；本任务把它加上，默认值 `DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())` 让现有测试不破。

- [ ] **Step 1: 写测试**

```swift
// QDictTests/Window/TranslatorViewModelSuggestionTests.swift
import XCTest
@testable import QDict

private struct StubEngine: SuggestionEngine {
    let items: [SuggestionItem]
    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        Array(items.prefix(limit))
    }
}

@MainActor
final class TranslatorViewModelSuggestionTests: XCTestCase {

    private func makeVM(engine: SuggestionEngine = StubEngine(items: [])) -> TranslatorViewModel {
        TranslatorViewModel(
            service: TranslationService(),
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}",
            suggestionEngine: engine
        )
    }

    func testInitialStateIsEmptyAndHidden() {
        let vm = makeVM()
        XCTAssertEqual(vm.suggestions, [])
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
        XCTAssertFalse(vm.isSuggestionsVisible)
    }

    func testIsSuggestionsVisibleRequiresNonEmptyAndDrawerClosed() {
        let item = SuggestionItem(id: "a", kind: .dictionary, word: "a", pos: nil, gloss: "g", badge: .none)
        let vm = makeVM(engine: StubEngine(items: [item]))
        // Directly seed the @Published field — at this stage no observer exists
        // yet (refreshSuggestions wiring is added in Task 12). Even after that
        // task lands, this assignment is a redundant no-op, not a breakage.
        vm.suggestions = [item]
        XCTAssertTrue(vm.isSuggestionsVisible)
        vm.isDrawerOpen = true
        XCTAssertFalse(vm.isSuggestionsVisible)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 编译失败 — 找不到 `suggestionEngine:`/`suggestions`/`selectionIndex`/`hasUserMovedSelection`/`isSuggestionsVisible`。

- [ ] **Step 3: 改 `TranslatorViewModel`**

在 `QDict/Window/TranslatorContentView.swift` 的 `TranslatorViewModel` 里：

把现有 init 与字段段改成（**不动其他既有字段**）：

```swift
@Published var input: String = ""
@Published var state: State = .idle

// MARK: - Suggestion dropdown state (M1)
@Published var suggestions: [SuggestionItem] = []
@Published var selectionIndex: Int = 0
@Published private(set) var hasUserMovedSelection: Bool = false

var isSuggestionsVisible: Bool {
    !suggestions.isEmpty && !isDrawerOpen
}

private let service: TranslationService
private let dictTemplate: String
private let translTemplate: String
private let historyStore: HistoryStore?
private let historyMode: Mode
private let suggestionEngine: SuggestionEngine
private var task: Task<Void, Never>?

init(
    service: TranslationService,
    dictTemplate: String,
    translTemplate: String,
    historyStore: HistoryStore? = nil,
    historyMode: Mode = .dictionary,
    suggestionEngine: SuggestionEngine = DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())
) {
    self.service = service
    self.dictTemplate = dictTemplate
    self.translTemplate = translTemplate
    self.historyStore = historyStore
    self.historyMode = historyMode
    self.suggestionEngine = suggestionEngine
}
```

`isDrawerOpen` 已有，无需新增。

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -20
```

Expected: 全部 PASS（包括既有 `TranslatorViewModelTests`，因为新参数有默认值）。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift QDict.xcodeproj
git commit -m "feat(window): add suggestion state to TranslatorViewModel"
```

---

## Task 12：TranslatorViewModel — refreshSuggestions + bind to $input

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`
- Modify: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

- [ ] **Step 1: 加测试**

在 `TranslatorViewModelSuggestionTests.swift` 末尾加：

```swift
    // MARK: - refreshSuggestions short-circuits

    private func makeStubItem(_ w: String) -> SuggestionItem {
        SuggestionItem(id: w, kind: .dictionary, word: w, pos: nil, gloss: "g", badge: .none)
    }

    private func makeEngine(_ words: [String]) -> StubEngine {
        StubEngine(items: words.map { makeStubItem($0) })
    }

    func testRefreshShortCircuitsOnTooShortInput() {
        let vm = makeVM(engine: makeEngine(["a"]))
        vm.input = "a"                                  // length < 2
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshShortCircuitsOnNonASCII() {
        let vm = makeVM(engine: makeEngine(["abc"]))
        vm.input = "你好"
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshShortCircuitsOnTrailingSpace() {
        let vm = makeVM(engine: makeEngine(["look up"]))
        vm.input = "look "                              // ends with space
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshLoadsItemsForValidPrefix() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        XCTAssertEqual(vm.suggestions.map(\.word), ["epic", "episode"])
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    func testRefreshShortCircuitsDuringStreaming() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.state = .streaming("partial")
        vm.input = "epic"
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshAllowedInDoneState() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.state = .done("done text")
        vm.input = "epi"
        XCTAssertEqual(vm.suggestions.map(\.word), ["epic"])
    }

    func testRefreshResetsSelectionOnNewInput() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.selectionIndex = 1
        // simulate user-moved flag (Task 13 will own the API; here we just write
        // the field via injection — but it's private(set), so we set via the
        // public method once Task 13 ships. For now, test only the reset of
        // selectionIndex.)
        vm.input = "epis"
        XCTAssertEqual(vm.selectionIndex, 0)
    }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -20
```

Expected: 多个测试 FAIL（`vm.suggestions` 仍为空，因为没有任何刷新逻辑）。

- [ ] **Step 3: 实现 refreshSuggestions + 订阅**

在 `TranslatorViewModel` 里加（建议放在 reset() 后面）：

```swift
import Combine

// 字段段加：
private var inputObserver: AnyCancellable?

// 把 init 末尾加上 bindInput 调用：
init(
    service: TranslationService,
    dictTemplate: String,
    translTemplate: String,
    historyStore: HistoryStore? = nil,
    historyMode: Mode = .dictionary,
    suggestionEngine: SuggestionEngine = DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())
) {
    self.service = service
    self.dictTemplate = dictTemplate
    self.translTemplate = translTemplate
    self.historyStore = historyStore
    self.historyMode = historyMode
    self.suggestionEngine = suggestionEngine
    bindInput()
}

private func bindInput() {
    inputObserver = $input
        .removeDuplicates()
        .sink { [weak self] s in self?.refreshSuggestions(for: s) }
}

func refreshSuggestions(for raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let isASCII = trimmed.allSatisfy { $0.isASCII }
    let endsWithSpace: Bool
    if let last = raw.last { endsWithSpace = (last == " " || last == "\\t") } else { endsWithSpace = false }
    let isStreaming: Bool
    if case .streaming = state { isStreaming = true } else { isStreaming = false }

    if trimmed.count < 2 || !isASCII || endsWithSpace || isStreaming {
        suggestions = []
        selectionIndex = 0
        hasUserMovedSelection = false
        return
    }

    let items = suggestionEngine.query(trimmed.lowercased(), limit: 6)
    suggestions = items
    selectionIndex = 0
    hasUserMovedSelection = false
}
```

`Combine` 已在该文件链路里使用过（其它视图导入），但 `TranslatorContentView.swift` 文件顶部目前只 `import SwiftUI`。需要在文件顶部追加 `import Combine`。

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -25
```

Expected: 新增的 6 个 refresh 测试都 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift QDict.xcodeproj
git commit -m "feat(window): wire input → suggestion refresh on TranslatorViewModel"
```

---

## Task 13：moveSuggestionSelection + 测试

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`
- Modify: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

- [ ] **Step 1: 加测试**

```swift
    // MARK: - moveSuggestionSelection

    func testMoveSuggestionDownIncrementsAndSetsFlag() {
        let vm = makeVM(engine: makeEngine(["a", "b", "c"]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: 1)
        XCTAssertEqual(vm.selectionIndex, 1)
        XCTAssertTrue(vm.hasUserMovedSelection)
    }

    func testMoveSuggestionClampsAtBottom() {
        let vm = makeVM(engine: makeEngine(["a", "b"]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: 5)
        XCTAssertEqual(vm.selectionIndex, 1)
    }

    func testMoveSuggestionClampsAtTop() {
        let vm = makeVM(engine: makeEngine(["a", "b"]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: -5)
        XCTAssertEqual(vm.selectionIndex, 0)
    }

    func testMoveSuggestionNoopWhenNotVisible() {
        let vm = makeVM(engine: makeEngine([]))
        vm.input = "ab"  // engine empty → suggestions empty → not visible
        vm.moveSuggestionSelection(by: 1)
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
    }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 编译失败 — `moveSuggestionSelection` 未定义。

- [ ] **Step 3: 实现**

在 `TranslatorViewModel` 里 `refreshSuggestions(for:)` 之后加：

```swift
func moveSuggestionSelection(by delta: Int) {
    guard isSuggestionsVisible else { return }
    let next = max(0, min(suggestions.count - 1, selectionIndex + delta))
    selectionIndex = next
    hasUserMovedSelection = true
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift
git commit -m "feat(window): add moveSuggestionSelection"
```

---

## Task 14：acceptSuggestionForCompletion (Tab) + 测试

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`
- Modify: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

- [ ] **Step 1: 加测试**

```swift
    // MARK: - acceptSuggestionForCompletion (Tab)

    func testTabFillsInputWithSelectedWord() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 1)         // select "episode"
        vm.acceptSuggestionForCompletion()
        XCTAssertEqual(vm.input, "episode")
    }

    func testTabResetsHasUserMovedSelectionFlag() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 0)         // sets flag
        vm.acceptSuggestionForCompletion()
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    func testTabIsNoopWhenNoSuggestions() {
        let vm = makeVM(engine: makeEngine([]))
        vm.input = "abc"
        vm.acceptSuggestionForCompletion()
        XCTAssertEqual(vm.input, "abc")
    }

    func testTabDoesNotTriggerSubmit() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        vm.acceptSuggestionForCompletion()
        XCTAssertEqual(vm.state, .idle)           // submit would have changed this
    }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `acceptSuggestionForCompletion` 未定义。

- [ ] **Step 3: 实现**

```swift
func acceptSuggestionForCompletion() {
    guard isSuggestionsVisible else { return }
    let item = suggestions[selectionIndex]
    input = item.word
    hasUserMovedSelection = false
}
```

注意：把 `input` 写为 `item.word` 会触发 `$input` sink → `refreshSuggestions` 重跑；新的输入串就是完整词，会再次拉一批以这个词为前缀的候选（一般来说包含该词本身在第一行）。这正是预期——回填后用户能立刻看到"还有哪些以这个词起头的"，并直接 ↵ 查它。

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift
git commit -m "feat(window): add acceptSuggestionForCompletion (Tab semantics)"
```

---

## Task 15：submitOrUseSelected (↵) + 测试

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`
- Modify: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

- [ ] **Step 1: 加测试**

```swift
    // MARK: - submitOrUseSelected (Return)

    func testReturnUsesInputWhenUserDidNotMoveSelection() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        // hasUserMovedSelection == false (user just typed)
        vm.submitOrUseSelected()
        // input should remain "epi" — submit() will use it.
        XCTAssertEqual(vm.input, "epi")
        // state moves out of .idle as submit kicked off (we don't await
        // network — submit() sets .streaming("") synchronously before the
        // Task fires). Just check it's no longer idle.
        if case .idle = vm.state { XCTFail("expected non-idle after submit") }
    }

    func testReturnUsesSelectedWordAfterUserMovedSelection() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 1)              // select "episode", flag set
        vm.submitOrUseSelected()
        XCTAssertEqual(vm.input, "episode")
    }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `submitOrUseSelected` 未定义。

- [ ] **Step 3: 实现**

```swift
func submitOrUseSelected() {
    if isSuggestionsVisible && hasUserMovedSelection {
        let item = suggestions[selectionIndex]
        input = item.word
    }
    submit()
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: PASS（注意 `submit()` 会启动一个 Task 调网络；测试只检查同步状态字段，不等异步完成。`TranslationService` 默认实例在没有配置时也会立即把 state 转 `.streaming("")`，达到测试目的）。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift
git commit -m "feat(window): add submitOrUseSelected (Return semantics)"
```

---

## Task 16：cancelSuggestionSelection (Esc 第一道) + 测试

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`
- Modify: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

- [ ] **Step 1: 加测试**

```swift
    // MARK: - cancelSuggestionSelection (Esc first hit)

    func testEscCancelReturnsTrueWhenUserMoved() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 1)
        XCTAssertTrue(vm.cancelSuggestionSelection())
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
        XCTAssertFalse(vm.suggestions.isEmpty)         // dropdown stays
    }

    func testEscCancelReturnsFalseWhenNotMoved() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        XCTAssertFalse(vm.cancelSuggestionSelection())
    }

    func testEscCancelReturnsFalseWhenSuggestionsHidden() {
        let vm = makeVM(engine: makeEngine([]))
        vm.input = "abc"
        XCTAssertFalse(vm.cancelSuggestionSelection())
    }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 未定义。

- [ ] **Step 3: 实现**

```swift
@discardableResult
func cancelSuggestionSelection() -> Bool {
    guard isSuggestionsVisible && hasUserMovedSelection else { return false }
    selectionIndex = 0
    hasUserMovedSelection = false
    return true
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift
git commit -m "feat(window): add cancelSuggestionSelection (Esc first stage)"
```

---

## Task 17：submit() / reset() 显式清空 suggestions + 测试

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`
- Modify: `QDictTests/Window/TranslatorViewModelSuggestionTests.swift`

- [ ] **Step 1: 加测试**

```swift
    // MARK: - submit() / reset() clear suggestions

    func testSubmitClearsSuggestions() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        XCTAssertFalse(vm.suggestions.isEmpty)
        vm.submit()
        XCTAssertEqual(vm.suggestions, [])
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    func testResetClearsSuggestions() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        XCTAssertFalse(vm.suggestions.isEmpty)
        vm.reset()
        XCTAssertEqual(vm.suggestions, [])
    }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: `testSubmitClearsSuggestions` FAIL (suggestions 不空，因为 submit 不动 input)。`testResetClearsSuggestions` 可能 PASS（reset 会把 input 设为空，触发 refresh 短路），但显式清空更稳妥，下一步统一加上。

- [ ] **Step 3: 改 submit() 与 reset()**

在 `submit()` 顶部（trim 之前）加：

```swift
func submit() {
    suggestions = []
    selectionIndex = 0
    hasUserMovedSelection = false
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    // …其余既有逻辑保持不变
```

`reset()` 同样在顶部加：

```swift
func reset() {
    suggestions = []
    selectionIndex = 0
    hasUserMovedSelection = false
    task?.cancel()
    input = ""
    state = .idle
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -15
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add QDict/Window/TranslatorContentView.swift QDictTests/Window/TranslatorViewModelSuggestionTests.swift
git commit -m "fix(window): clear suggestions explicitly on submit and reset"
```

---

## Task 18：SuggestionRow 视图

**Files:**
- Create: `QDict/Window/TranslatorSuggestionsView.swift`（先写 SuggestionRow，下一 Task 加容器）

无测试（纯视图渲染；UI snapshot 测试不在本里程碑范围）。

- [ ] **Step 1: 实现 SuggestionRow**

```swift
// QDict/Window/TranslatorSuggestionsView.swift
import SwiftUI

/// One row in the suggestion dropdown. Pure render — no logic.
struct SuggestionRow: View {
    let item: SuggestionItem
    let isSelected: Bool
    let prefix: String          // 用户已输入的串（小写化前的原文），用于浅/深色拼接

    var body: some View {
        HStack(spacing: 8) {
            icon
            wordWithGloss
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(rowBackground)
        .overlay(alignment: .leading) { selectionBar }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(iconFill)
            Text(iconLetter)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }

    private var iconLetter: String {
        switch item.kind {
        case .dictionary: return "A"
        case .history:    return "🕘"      // M2 only; M1 never produces .history
        }
    }

    private var iconFill: Color {
        switch (item.kind, isSelected) {
        case (.dictionary, true):  return TranslatorTheme.accentColor
        case (.dictionary, false): return TranslatorTheme.iconNeutralFill
        case (.history, _):        return TranslatorTheme.iconNeutralFill
        }
    }

    @ViewBuilder
    private var wordWithGloss: some View {
        HStack(spacing: 6) {
            wordAttributed
            if let pos = item.pos {
                Text(pos)
                    .font(.system(size: 12).italic())
                    .foregroundStyle(.secondary)
            }
            Text(item.gloss)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var wordAttributed: Text {
        let lowerWord = item.word.lowercased()
        let lowerPrefix = prefix.lowercased()
        if lowerWord.hasPrefix(lowerPrefix) && !lowerPrefix.isEmpty {
            let head = String(item.word.prefix(lowerPrefix.count))
            let tail = String(item.word.dropFirst(lowerPrefix.count))
            return Text(head)
                .foregroundStyle(.secondary)
                .font(.system(size: 14, weight: .regular))
                + Text(tail)
                .foregroundStyle(.primary)
                .font(.system(size: 14, weight: .semibold))
        }
        return Text(item.word)
            .foregroundStyle(.primary)
            .font(.system(size: 14, weight: .semibold))
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if item.badge == .recent {
                Text("最近")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(TranslatorTheme.badgeFill)
                    )
            }
            if isSelected {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            TranslatorTheme.selectionRowFill
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isSelected {
            Rectangle()
                .fill(TranslatorTheme.accentColor)
                .frame(width: 2)
        }
    }
}
```

- [ ] **Step 2: 给 TranslatorTheme 加新颜色 token**

`QDict/Window/TranslatorTheme.swift`：（需要先 Read 该文件，然后在末尾加 token；如果 token 已存在就跳过）

```swift
extension TranslatorTheme {
    static let iconNeutralFill = Color.secondary.opacity(0.5)
    static let accentColor = Color.orange                          // 与 mockup 一致
    static let badgeFill = Color.secondary.opacity(0.18)
    static let selectionRowFill = Color.orange.opacity(0.10)
}
```

注：先 `cat QDict/Window/TranslatorTheme.swift` 看现有 token；如果已经定义了 `accentColor` 之类，复用即可，不要重复定义。

- [ ] **Step 3: 编译**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 4: Commit**

```bash
git add QDict/Window/TranslatorSuggestionsView.swift QDict/Window/TranslatorTheme.swift QDict.xcodeproj
git commit -m "feat(window): add SuggestionRow render"
```

---

## Task 19：TranslatorSuggestionsView 容器 + 集成到 TranslatorContentView

**Files:**
- Modify: `QDict/Window/TranslatorSuggestionsView.swift`
- Modify: `QDict/Window/TranslatorContentView.swift`

- [ ] **Step 1: 在 SuggestionRow 同文件下加容器**

```swift
struct TranslatorSuggestionsView: View {
    @ObservedObject var vm: TranslatorViewModel

    var body: some View {
        if vm.isSuggestionsVisible {
            VStack(spacing: 0) {
                ForEach(Array(vm.suggestions.enumerated()), id: \.element.id) { index, item in
                    SuggestionRow(
                        item: item,
                        isSelected: index == vm.selectionIndex,
                        prefix: vm.input
                    )
                    .onTapGesture {
                        vm.selectionIndex = index
                        // 鼠标点击 = 显式选择 + 立即查询；不依赖 hasUserMovedSelection
                        let word = vm.suggestions[index].word
                        vm.input = word
                        vm.submit()
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: 在 TranslatorContentView 里把视图插进 shell**

把 `var body` 里的 shell 内容改成：

```swift
TranslatorShell {
    TranslatorHeaderView(onSettings: onShowPreferences)
    themedDivider
    TranslatorInputView(vm: vm, isFocused: $inputFocused)
    if vm.isSuggestionsVisible {
        themedDivider
        TranslatorSuggestionsView(vm: vm)
    }
    themedDivider
    TranslatorHintsView()
    resultSection
    drawerSection
}
.onAppear { inputFocused = true }
```

如果 `TranslatorShell { … }` 实际是个 ViewBuilder（看上去如此），上述结构成立；若它接受一个具体类型而非 `@ViewBuilder` content，需要先确认其签名（`Read QDict/Window/TranslatorShell.swift` 一下）。如签名是普通 ViewBuilder，无需改它。

- [ ] **Step 3: 编译**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 4: Commit**

```bash
git add QDict/Window/TranslatorSuggestionsView.swift QDict/Window/TranslatorContentView.swift
git commit -m "feat(window): integrate suggestions dropdown into shell"
```

---

## Task 20：把 LocalDictionary / SuggestionEngine 接进 AppContainer

**Files:**
- Modify: `QDict/App/AppContainer.swift`
- Modify: `QDict/Window/TranslatorWindowController.swift`

- [ ] **Step 1: 改 AppContainer**

`AppContainer.init()` 末尾、`translator =` 之前插入：

```swift
let dict = DictionaryLoader.loadBundled()
let suggestionEngine = DictionaryOnlySuggestionEngine(dict: dict)
```

把 translator 构造改成传入 engine：

```swift
self.translator = TranslatorWindowController(
    service: translationService,
    dictTemplate: dictTemplate,
    translTemplate: translTemplate,
    historyStore: store,
    suggestionEngine: suggestionEngine
)
```

- [ ] **Step 2: 改 TranslatorWindowController init 签名**

```swift
init(
    service: TranslationService,
    dictTemplate: String,
    translTemplate: String,
    historyStore: HistoryStore,
    suggestionEngine: SuggestionEngine
) {
    self.historyStore = historyStore
    self.vm = TranslatorViewModel(
        service: service,
        dictTemplate: dictTemplate,
        translTemplate: translTemplate,
        historyStore: historyStore,
        suggestionEngine: suggestionEngine
    )
    // …其余构造保持不变
}
```

- [ ] **Step 3: 编译并跑全套测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -25
```

Expected: 全部 PASS。如果 `TranslatorWindowControllerTests` 编译失败（因为 init 签名变了），把它的 `makeController()` helper 也加上 `suggestionEngine` 参数（默认传 `DictionaryOnlySuggestionEngine(dict: EmptyLocalDictionary())`）。

- [ ] **Step 4: Commit**

```bash
git add QDict/App/AppContainer.swift QDict/Window/TranslatorWindowController.swift QDictTests/TranslatorWindowControllerTests.swift QDict.xcodeproj
git commit -m "feat(app): wire LocalDictionary through to suggestion engine"
```

---

## Task 21：键盘事件路由更新

**Files:**
- Modify: `QDict/Window/TranslatorWindowController.swift`

- [ ] **Step 1: 改 `installDismissMonitors` 的 if-链**

把现有的 `localKeyMonitor` 闭包替换成下面这个版本（保持其它字段 / 闭包不变）：

```swift
localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    guard let self else { return event }
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)

    // ── Esc = 53 ──
    if event.keyCode == 53 {
        if self.vm.isDrawerOpen {
            self.vm.closeDrawer()
            return nil
        }
        if self.vm.cancelSuggestionSelection() {
            return nil  // user-moved selection cancelled; dropdown stays
        }
        self.hardHide()
        return nil
    }

    // ── Return = 36 ──
    if event.keyCode == 36 && mods.isEmpty {
        if self.vm.isDrawerOpen {
            self.vm.confirmSelection(history: self.historyStore)
        } else {
            self.vm.submitOrUseSelected()
        }
        return nil
    }

    // ── Tab = 48 ──
    if event.keyCode == 48 && mods.isEmpty {
        if !self.vm.isDrawerOpen && self.vm.isSuggestionsVisible {
            self.vm.acceptSuggestionForCompletion()
            return nil
        }
        return event   // let system handle focus traversal otherwise
    }

    // ── Cmd+Y = 16 ──
    if event.keyCode == 16 && mods == .command {
        self.vm.toggleDrawer(history: self.historyStore)
        return nil
    }

    // ── Cmd+, = 43 ──
    if event.keyCode == 43 && mods == .command {
        self.showPreferencesAndSoftHide()
        return nil
    }

    // ── Cmd+↑/↓ = 126 / 125 ──
    if mods == .command && (event.keyCode == 126 || event.keyCode == 125) {
        let delta = (event.keyCode == 126) ? -1 : 1
        self.vm.moveSelection(in: self.historyStore, by: delta)
        return nil
    }

    // ── ↑/↓ no mods ──
    if mods.isEmpty && (event.keyCode == 126 || event.keyCode == 125) {
        let delta = (event.keyCode == 126) ? -1 : 1
        if self.vm.isDrawerOpen {
            self.vm.moveSelection(in: self.historyStore, by: delta)
            return nil
        }
        if self.vm.isSuggestionsVisible {
            self.vm.moveSuggestionSelection(by: delta)
            return nil
        }
        return event
    }

    // ── Backspace inside drawer ──
    if self.vm.isDrawerOpen && (event.keyCode == 51 || event.keyCode == 117) {
        self.vm.deleteSelection(history: self.historyStore)
        return nil
    }

    return event
}
```

- [ ] **Step 2: 改面板自动调整尺寸的订阅，让下拉变化也触发 resize**

在 init 末尾（已有 `stateSubscription / inputSubscription / drawerSubscription / historySubscription` 那里）加：

```swift
private var suggestionsSubscription: AnyCancellable?
```

并在 `init` 里挂：

```swift
suggestionsSubscription = vm.$suggestions
    .receive(on: RunLoop.main)
    .sink { _ in resize() }
```

- [ ] **Step 3: 编译并跑全套测试**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -25
```

Expected: 全部 PASS。

- [ ] **Step 4: Commit**

```bash
git add QDict/Window/TranslatorWindowController.swift QDict.xcodeproj
git commit -m "feat(window): route Tab/↑↓/Esc/↵ for suggestion dropdown"
```

---

## Task 22：手动 smoke + THIRD_PARTY_LICENSES + 收尾

**Files:**
- Create: `QDict/Resources/THIRD_PARTY_LICENSES.md`

- [ ] **Step 1: 写 THIRD_PARTY_LICENSES.md**

```markdown
# Third-Party Licenses

QDict bundles the following third-party data:

## ECDICT (https://github.com/skywind3000/ECDICT)

A subset of the ECDICT free English-Chinese dictionary is bundled at
`Dictionary/Resources/ecdict.sqlite` and used to power the input
suggestion dropdown.

License: MIT.

```
The MIT License (MIT)

Copyright (c) 2017 skywind3000

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
```

- [ ] **Step 2: 手动 smoke**

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" build 2>&1 | tail -5
open build/Build/Products/Debug/QDict.app   # 路径可能不同；视 DerivedData 实际位置
```

如果 .app 不在该路径，用：

```bash
open "$(xcodebuild -scheme QDict -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk -F'= ' '/CONFIGURATION_BUILD_DIR/ {print $2; exit}')/QDict.app"
```

手测清单（spec §8 优先级表对照）：
- [ ] 启动后键入 `epi`，输入框正下方出现下拉，第 1 行高亮，右侧有 ↵ 图标。
- [ ] 按 ↓ 选中第 2 行，按 Tab → 输入框变成 "epiphany" 之类；下拉随新前缀刷新。
- [ ] 按 ↵ 触发查询（流式结果出现，下拉收起）。
- [ ] done 之后再键入 `apple`，下拉重新出现。
- [ ] 输入"中文" → 下拉立即收起。
- [ ] 输入末尾留空格 → 下拉收起。
- [ ] 按 Cmd+Y 打开历史抽屉 → 此时下拉应隐藏；关抽屉后下拉回归。
- [ ] 选中过条目后按 Esc → 选择被撤回（高亮回到第 1 行），下拉仍在；再按 Esc → 面板软隐藏。
- [ ] 鼠标点击下拉某行 → 直接查该词。
- [ ] 在下拉里删字（Backspace 直到不足 2 字符）→ 下拉自动收起。
- [ ] 输出结果区出现后点输入框右侧的 X 清空 → 下拉应清空（reset 路径）。

任一项失败：在执行计划时停下来调，不要赶完。

- [ ] **Step 3: Commit**

```bash
git add QDict/Resources/THIRD_PARTY_LICENSES.md
git commit -m "docs: add THIRD_PARTY_LICENSES with ECDICT MIT notice"
```

---

## 验收

跑完所有 Task 后，最后一遍：

```bash
xcodegen
xcodebuild -scheme QDict -destination "platform=macOS" test 2>&1 | tail -10
```

Expected: 所有测试 PASS（既有 + 新增）。

如果 PR 合并前要核对 spec 覆盖度，spec 各小节的对应 Task：

| Spec 节 | 实施 Task |
|---|---|
| §4 总体架构、目录结构 | 3, 4–10, 18–19 |
| §5 数据层 | 1, 2, 4–8 |
| §6 建议引擎 | 9–10, 12 |
| §7.1 ViewModel 增量 | 11–17 |
| §7.2 SuggestionRow / TranslatorSuggestionsView | 18–19 |
| §7.3 整合 TranslatorContentView | 19 |
| §8 键盘交互优先级表 | 21 |
| §9 边界与降级 | 5（Empty fallback）、7（截断）、8（loader 降级）、12（短路）、17（submit 清空） |
| §10 测试 | 4–17 各 task 的 test 步骤 |
| §11 节奏 | 本文档 = M1；M2 单独 plan |
| §12 风险 | Task 22 手动 smoke + THIRD_PARTY_LICENSES |

M2 不在本计划内：历史融合、"最近"角标、`MergedSuggestionEngine`、二期测试套——M1 上线、有真实手感后再写新 plan。
