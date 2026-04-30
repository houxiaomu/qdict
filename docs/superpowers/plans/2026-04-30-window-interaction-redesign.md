# 窗口交互重设计 · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 spec `docs/superpowers/specs/2026-04-30-window-interaction-redesign-design.md`：硬关闭/软关闭双语义、5 分钟内会话恢复、热键再按改为拉前台、本地持久化历史记录抽屉。

**Architecture:** 在 `TranslatorWindowController` 区分 `hardHide()` / `softHide()`，在 `show()` 入口按快照新鲜度决定恢复或空白；新增 `HistoryStore`（JSON 文件，FIFO，`@Published` 列表）作为持久化层并注入 `AppContainer`；`TranslatorViewModel` 增加 `snapshot()` / `restore(_:)` / `loadFromHistory(_:)` 三个不发起 API 调用的状态钩子；UI 层加 `HistoryDrawerView` 和 Cmd+Y / Cmd+↑↓ 键盘路由。

**Tech Stack:** Swift 5.9, AppKit (`NSPanel`, `NSEvent.addGlobalMonitorForEvents`, `NSApplication.didResignActiveNotification`), SwiftUI, XCTest, JSON file at `~/Library/Application Support/Dictonary/history.json`.

**Build / Test commands:**
- 构建：`xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build`
- 测试：`xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test`
- 运行单个测试类：`xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test -only-testing:DictonaryTests/HistoryStoreTests`

**Pre-existing uncommitted changes**: 仓库当前在 `main` 分支有若干无关的未提交修改（icon 资源、AppDelegate 等）。本计划的每个 commit 都只 `git add` 自己声明的文件，避免把它们卷进来。

---

## File Structure

**New files:**

| 文件 | 职责 |
|---|---|
| `Dictonary/History/HistoryEntry.swift` | 数据模型 (`Codable, Identifiable`) |
| `Dictonary/History/HistoryStore.swift` | 文件持久化、FIFO、去重、`@Published var entries` |
| `Dictonary/History/SessionSnapshot.swift` | 软关闭快照 (`query, result, capturedAt`) + 新鲜度检查 |
| `Dictonary/Window/HistoryDrawerView.swift` | SwiftUI 抽屉组件 |
| `Dictonary/Settings/UI/HistorySettingsView.swift` | Settings 内的 "History" tab |
| `DictonaryTests/HistoryEntryTests.swift` | Codable round-trip |
| `DictonaryTests/HistoryStoreTests.swift` | 持久化、上限、去重、清空 |
| `DictonaryTests/SessionSnapshotTests.swift` | 5 分钟过期判断 |
| `DictonaryTests/TranslatorViewModelTests.swift` | snapshot/restore/loadFromHistory |

**Modified files:**

| 文件 | 改动 |
|---|---|
| `Dictonary/Settings/Settings.swift` | 增加 `historyLimit` 字段（UserDefaults）|
| `Dictonary/App/AppContainer.swift` | 实例化并注入 `HistoryStore` |
| `Dictonary/Window/TranslatorContentView.swift` | ViewModel 增加快照/历史钩子；ContentView 集成抽屉与键盘路由 |
| `Dictonary/Window/TranslatorWindowController.swift` | 硬/软关闭拆分、show 时按新鲜度恢复、热键拉前台、外部点击和失活监听 |
| `Dictonary/Settings/UI/SettingsView.swift` | 增加 "History" tab |

`project.yml` 的 `sources: - path: Dictonary` 是目录递归，新增 swift 文件会被自动包含，无需修改 `project.yml`。

---

## Task 1: HistoryEntry 模型

**Files:**
- Create: `Dictonary/History/HistoryEntry.swift`
- Test: `DictonaryTests/HistoryEntryTests.swift`

- [ ] **Step 1: 写失败测试**

`DictonaryTests/HistoryEntryTests.swift`:

```swift
import XCTest
@testable import Dictonary

final class HistoryEntryTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = HistoryEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            query: "hello",
            result: "你好",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: .dictionary
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test \
  -only-testing:DictonaryTests/HistoryEntryTests
```

Expected: 编译失败，`Cannot find 'HistoryEntry' in scope`。

- [ ] **Step 3: 实现模型**

`Dictonary/History/HistoryEntry.swift`:

```swift
import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let query: String
    let result: String
    let timestamp: Date
    let mode: Mode

    init(id: UUID = UUID(), query: String, result: String, timestamp: Date = Date(), mode: Mode) {
        self.id = id
        self.query = query
        self.result = result
        self.timestamp = timestamp
        self.mode = mode
    }
}

extension Mode: Codable {}
```

- [ ] **Step 4: 运行测试通过**

Expected: PASS, 1 test passes.

- [ ] **Step 5: 提交**

```bash
git add Dictonary/History/HistoryEntry.swift DictonaryTests/HistoryEntryTests.swift
git commit -m "feat(history): add HistoryEntry model"
```

---

## Task 2: HistoryStore 持久化

`HistoryStore` 是观察对象，把历史记录写到本地 JSON 文件。FIFO 上限，连续相同 query 去重，提供 `clear()` 方法。

**Files:**
- Create: `Dictonary/History/HistoryStore.swift`
- Test: `DictonaryTests/HistoryStoreTests.swift`

- [ ] **Step 1: 写失败测试（覆盖 append / 去重 / 上限 / 清空 / 持久化）**

`DictonaryTests/HistoryStoreTests.swift`:

```swift
import XCTest
@testable import Dictonary

final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore(limit: Int = 50) -> HistoryStore {
        HistoryStore(fileURL: tempDir.appendingPathComponent("h.json"), limit: limit)
    }

    func testStartsEmpty() {
        let s = makeStore()
        XCTAssertEqual(s.entries.count, 0)
    }

    func testAppendOrdersMostRecentFirst() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        XCTAssertEqual(s.entries.map { $0.query }, ["b", "a"])
    }

    func testFIFOEvictsOldest() {
        let s = makeStore(limit: 2)
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        s.append(query: "c", result: "C", mode: .dictionary)
        XCTAssertEqual(s.entries.map { $0.query }, ["c", "b"])
    }

    func testConsecutiveDuplicateRefreshesTimestampNotCount() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        let firstTs = s.entries[0].timestamp
        Thread.sleep(forTimeInterval: 0.02)
        s.append(query: "a", result: "A2", mode: .dictionary)
        XCTAssertEqual(s.entries.count, 1)
        XCTAssertGreaterThan(s.entries[0].timestamp, firstTs)
        // The fresher result wins.
        XCTAssertEqual(s.entries[0].result, "A2")
    }

    func testNonConsecutiveDuplicateIsAllowed() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        s.append(query: "a", result: "A", mode: .dictionary)
        XCTAssertEqual(s.entries.map { $0.query }, ["a", "b", "a"])
    }

    func testRemoveByID() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        s.remove(id: s.entries[0].id)
        XCTAssertEqual(s.entries.map { $0.query }, ["a"])
    }

    func testClearEmptiesEntries() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.clear()
        XCTAssertEqual(s.entries.count, 0)
    }

    func testPersistsAcrossInstances() {
        let url = tempDir.appendingPathComponent("h.json")
        let s = HistoryStore(fileURL: url, limit: 50)
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .translation)

        let s2 = HistoryStore(fileURL: url, limit: 50)
        XCTAssertEqual(s2.entries.map { $0.query }, ["b", "a"])
        XCTAssertEqual(s2.entries[0].mode, .translation)
    }

    func testCorruptedFileResetsToEmpty() throws {
        let url = tempDir.appendingPathComponent("h.json")
        try Data("{not valid json".utf8).write(to: url)
        let s = HistoryStore(fileURL: url, limit: 50)
        XCTAssertEqual(s.entries.count, 0)
        // Subsequent writes should still work.
        s.append(query: "a", result: "A", mode: .dictionary)
        XCTAssertEqual(s.entries.count, 1)
    }

    func testLimitChangeApplies() {
        let url = tempDir.appendingPathComponent("h.json")
        let s = HistoryStore(fileURL: url, limit: 50)
        for i in 0..<10 {
            s.append(query: "q\(i)", result: "r\(i)", mode: .dictionary)
        }
        s.setLimit(3)
        XCTAssertEqual(s.entries.count, 3)
        XCTAssertEqual(s.entries.map { $0.query }, ["q9", "q8", "q7"])
    }

    func testZeroLimitDisablesHistory() {
        let s = makeStore(limit: 0)
        s.append(query: "a", result: "A", mode: .dictionary)
        XCTAssertEqual(s.entries.count, 0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test \
  -only-testing:DictonaryTests/HistoryStoreTests
```

Expected: 编译失败，`Cannot find 'HistoryStore'`.

- [ ] **Step 3: 实现 HistoryStore**

`Dictonary/History/HistoryStore.swift`:

```swift
import Foundation
import Combine

/// Persists translation history as JSON. Most-recent entry first.
/// Thread-safety: file I/O is serialized via the dedicated queue.
/// `entries` is mutated on the main actor and observed via `@Published`.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private var limit: Int
    private let io = DispatchQueue(label: "app.dictonary.history.io")

    init(fileURL: URL, limit: Int) {
        self.fileURL = fileURL
        self.limit = max(0, limit)
        self.entries = Self.loadFromDisk(fileURL: fileURL)
        // If the on-disk file already exceeds the new limit, trim immediately.
        if entries.count > self.limit {
            entries = Array(entries.prefix(self.limit))
            persist()
        }
    }

    /// Convenience: store at default app-support location.
    static func defaultURL() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Dictonary", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func append(query: String, result: String, mode: Mode) {
        guard limit > 0 else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        // Consecutive duplicate: refresh timestamp + result, don't add a new row.
        if let first = entries.first, first.query == q {
            entries[0] = HistoryEntry(
                id: first.id,
                query: q,
                result: result,
                timestamp: Date(),
                mode: mode
            )
            persist()
            return
        }

        let entry = HistoryEntry(query: q, result: result, mode: mode)
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        persist()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func setLimit(_ newLimit: Int) {
        limit = max(0, newLimit)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        persist()
    }

    // MARK: - Disk I/O

    private static func loadFromDisk(fileURL: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let parsed = try? decoder.decode([HistoryEntry].self, from: data) {
            return parsed
        }
        // Corrupted → back up and start fresh.
        let backup = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return []
    }

    private func persist() {
        // Snapshot on main actor, write off-thread.
        let snapshot = entries
        let url = fileURL
        io.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }
}
```

- [ ] **Step 4: 运行测试通过**

Expected: PASS, 11 tests passing.

注意：`testPersistsAcrossInstances` 需要 disk write 落地。`persist()` 是异步的；如果测试在写入完成前实例化第二个 store 会读到空。临时方案：在测试里调用一个同步等待 — 改用 `XCTestExpectation` 监听文件出现，或者给 store 加测试用 `flush()` 同步落盘方法。我们采用后者：

补丁 `HistoryStore.swift`：

```swift
#if DEBUG
extension HistoryStore {
    /// Block until the most recent persist write reaches disk. Test-only.
    func flushForTesting() {
        io.sync { }
    }
}
#endif
```

测试里需要在每次 mutate 后调用 `s.flushForTesting()` 才读第二个实例。修改 `testPersistsAcrossInstances` 和 `testCorruptedFileResetsToEmpty` 中第二段：

```swift
func testPersistsAcrossInstances() {
    let url = tempDir.appendingPathComponent("h.json")
    let s = HistoryStore(fileURL: url, limit: 50)
    s.append(query: "a", result: "A", mode: .dictionary)
    s.append(query: "b", result: "B", mode: .translation)
    s.flushForTesting()

    let s2 = HistoryStore(fileURL: url, limit: 50)
    XCTAssertEqual(s2.entries.map { $0.query }, ["b", "a"])
    XCTAssertEqual(s2.entries[0].mode, .translation)
}
```

Re-run, Expected: PASS.

- [ ] **Step 5: 提交**

```bash
git add Dictonary/History/HistoryStore.swift DictonaryTests/HistoryStoreTests.swift
git commit -m "feat(history): add HistoryStore with FIFO persistence"
```

---

## Task 3: SessionSnapshot 模型

软关闭时记录的快照，含 `capturedAt` 和 5 分钟新鲜度判断。

**Files:**
- Create: `Dictonary/History/SessionSnapshot.swift`
- Test: `DictonaryTests/SessionSnapshotTests.swift`

- [ ] **Step 1: 写失败测试**

`DictonaryTests/SessionSnapshotTests.swift`:

```swift
import XCTest
@testable import Dictonary

final class SessionSnapshotTests: XCTestCase {
    func testFreshWithinFiveMinutes() {
        let now = Date()
        let snap = SessionSnapshot(
            input: "hi",
            state: .done("你好"),
            capturedAt: now.addingTimeInterval(-60)
        )
        XCTAssertTrue(snap.isFresh(now: now))
    }

    func testStaleAfterFiveMinutes() {
        let now = Date()
        let snap = SessionSnapshot(
            input: "hi",
            state: .done("你好"),
            capturedAt: now.addingTimeInterval(-301)
        )
        XCTAssertFalse(snap.isFresh(now: now))
    }

    func testFreshAtBoundary() {
        let now = Date()
        // exactly 300s should still count as fresh (use <= when checking).
        let snap = SessionSnapshot(
            input: "hi",
            state: .idle,
            capturedAt: now.addingTimeInterval(-300)
        )
        XCTAssertTrue(snap.isFresh(now: now))
    }

    func testIdleEmptyInputIsNotWorthCapturing() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "", state: .idle)
        XCTAssertNil(snap)
    }

    func testIdleWithInputIsCapturable() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "hi", state: .idle)
        XCTAssertNotNil(snap)
    }

    func testDoneIsCapturable() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "hi", state: .done("你好"))
        XCTAssertNotNil(snap)
    }

    func testStreamingIsCapturable() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "hi", state: .streaming("你"))
        XCTAssertNotNil(snap)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test \
  -only-testing:DictonaryTests/SessionSnapshotTests
```

Expected: 编译失败，`Cannot find 'SessionSnapshot'`.

- [ ] **Step 3: 实现**

`Dictonary/History/SessionSnapshot.swift`:

```swift
import Foundation

/// State captured when the panel is softly hidden (click-outside / Cmd+Tab).
/// Used to restore content if the user re-summons the panel within
/// `freshnessWindow` seconds.
struct SessionSnapshot: Equatable {
    static let freshnessWindow: TimeInterval = 300 // 5 minutes

    let input: String
    let state: TranslatorViewModel.State
    let capturedAt: Date

    func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(capturedAt) <= Self.freshnessWindow
    }

    /// Returns `nil` if there is nothing meaningful to restore.
    /// Empty input + idle state = no snapshot worth keeping.
    static func makeIfWorthCapturing(
        input: String,
        state: TranslatorViewModel.State,
        now: Date = Date()
    ) -> SessionSnapshot? {
        let hasInput = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasResult: Bool = {
            switch state {
            case .idle: return false
            case .streaming, .done, .error: return true
            }
        }()
        guard hasInput || hasResult else { return nil }
        return SessionSnapshot(input: input, state: state, capturedAt: now)
    }
}
```

`TranslatorViewModel.State` 已是 `Equatable`，所以 `SessionSnapshot` 自动派生 `Equatable`。

- [ ] **Step 4: 运行测试通过**

Expected: PASS, 7 tests pass.

- [ ] **Step 5: 提交**

```bash
git add Dictonary/History/SessionSnapshot.swift DictonaryTests/SessionSnapshotTests.swift
git commit -m "feat(history): add SessionSnapshot with 5-minute freshness check"
```

---

## Task 4: ViewModel 添加快照 / 恢复 / 历史钩子

`TranslatorViewModel` 增加：
- `snapshot()` 提取当前 input + state 为 `SessionSnapshot?`
- `restore(_:)` 把快照写回 input + state
- `loadFromHistory(_:)` 把 query/result 写回，**不**调 API
- 当 `submit()` 完成（streaming 结束 → `.done`）时调用 `historyStore.append(...)`

依赖注入：构造函数加可选的 `historyStore: HistoryStore?` 和 `mode: () -> Mode`（mode 由 ContentView/UI 决定，可暂以 `.dictionary` 占位，后续如果 UI 区分 dict/translate 再传入）。当前 UI 只有一个输入框走两个模板的合并 prompt，所以 `mode` 实际用作历史的标签，先简化为入参常量。

实现层的 mode 来源：观察现有 `PromptBuilder.build` 接收 dict + transl 两个模板并返回单 `systemPrompt`。历史里 `mode` 字段更多是给未来 UI 用的标识；本任务里固定 `.dictionary` 不阻塞功能。注意 spec 验收"重启 app 后历史仍在"成立。

**Files:**
- Modify: `Dictonary/Window/TranslatorContentView.swift:4-59` (TranslatorViewModel 类)
- Test: `DictonaryTests/TranslatorViewModelTests.swift`

- [ ] **Step 1: 写失败测试**

`DictonaryTests/TranslatorViewModelTests.swift`:

```swift
import XCTest
@testable import Dictonary

@MainActor
final class TranslatorViewModelTests: XCTestCase {

    private func makeVM() -> TranslatorViewModel {
        let settings = Settings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
                                keychain: InMemoryKeychain())
        let svc = TranslationService(settings: settings)
        return TranslatorViewModel(
            service: svc,
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}"
        )
    }

    func testSnapshotNilWhenIdleAndEmpty() {
        let vm = makeVM()
        XCTAssertNil(vm.snapshot())
    }

    func testSnapshotCapturesInputAndState() {
        let vm = makeVM()
        vm.input = "hello"
        XCTAssertEqual(vm.snapshot()?.input, "hello")
        XCTAssertEqual(vm.snapshot()?.state, .idle)
    }

    func testRestoreWritesInputAndState() {
        let vm = makeVM()
        let snap = SessionSnapshot(
            input: "hello",
            state: .done("你好"),
            capturedAt: Date()
        )
        vm.restore(snap)
        XCTAssertEqual(vm.input, "hello")
        XCTAssertEqual(vm.state, .done("你好"))
    }

    func testLoadFromHistoryDoesNotCallService() {
        let vm = makeVM()
        let entry = HistoryEntry(query: "hello", result: "你好", mode: .dictionary)
        vm.loadFromHistory(entry)
        XCTAssertEqual(vm.input, "hello")
        XCTAssertEqual(vm.state, .done("你好"))
        // service was constructed but no API key set, so any submit attempt
        // would surface as .error(.missingAPIKey). Assert state is plain .done.
    }

    func testResetClearsInputAndState() {
        let vm = makeVM()
        vm.input = "hi"
        vm.restore(SessionSnapshot(input: "hi", state: .done("你"), capturedAt: Date()))
        vm.reset()
        XCTAssertEqual(vm.input, "")
        XCTAssertEqual(vm.state, .idle)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test \
  -only-testing:DictonaryTests/TranslatorViewModelTests
```

Expected: 编译失败 — `snapshot`, `restore`, `loadFromHistory` 未定义。

- [ ] **Step 3: 实现 ViewModel 改动**

修改 `Dictonary/Window/TranslatorContentView.swift`，把 `TranslatorViewModel` 替换为：

```swift
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
    private let historyStore: HistoryStore?
    private let historyMode: Mode
    private var task: Task<Void, Never>?

    init(
        service: TranslationService,
        dictTemplate: String,
        translTemplate: String,
        historyStore: HistoryStore? = nil,
        historyMode: Mode = .dictionary
    ) {
        self.service = service
        self.dictTemplate = dictTemplate
        self.translTemplate = translTemplate
        self.historyStore = historyStore
        self.historyMode = historyMode
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
                self.historyStore?.append(query: text, result: buffer, mode: self.historyMode)
            } catch let e as TranslationError {
                if case .cancelled = e { return }
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

    // MARK: - Session snapshot (soft-hide / restore)

    func snapshot(now: Date = Date()) -> SessionSnapshot? {
        SessionSnapshot.makeIfWorthCapturing(input: input, state: state, now: now)
    }

    func restore(_ snapshot: SessionSnapshot) {
        task?.cancel()
        input = snapshot.input
        state = snapshot.state
    }

    // MARK: - History recall

    /// Replay a history entry without re-calling the API.
    func loadFromHistory(_ entry: HistoryEntry) {
        task?.cancel()
        input = entry.query
        state = .done(entry.result)
    }
}
```

- [ ] **Step 4: 运行测试通过**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test \
  -only-testing:DictonaryTests/TranslatorViewModelTests
```

Expected: PASS, 5 tests pass.

- [ ] **Step 5: 提交**

```bash
git add Dictonary/Window/TranslatorContentView.swift DictonaryTests/TranslatorViewModelTests.swift
git commit -m "feat(viewmodel): add session snapshot, restore, and history recall"
```

---

## Task 5: Settings 增加 historyLimit

`Settings` 新增 `historyLimit`（默认 50，范围 0-500），UserDefaults 持久化。

**Files:**
- Modify: `Dictonary/Settings/Settings.swift`
- Test: `DictonaryTests/SettingsTests.swift` (extend)

- [ ] **Step 1: 写失败测试（追加到现有 SettingsTests）**

在 `DictonaryTests/SettingsTests.swift` 末尾追加：

```swift
extension SettingsTests {
    func testHistoryLimitDefault() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        XCTAssertEqual(s.historyLimit, 50)
    }

    func testHistoryLimitPersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults, keychain: InMemoryKeychain())
        s.historyLimit = 25
        let s2 = Settings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(s2.historyLimit, 25)
    }

    func testHistoryLimitClampsToZeroMin() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        s.historyLimit = -5
        XCTAssertEqual(s.historyLimit, 0)
    }

    func testHistoryLimitClampsToMax() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        s.historyLimit = 9999
        XCTAssertEqual(s.historyLimit, 500)
    }
}
```

注意 `makeDefaults` 在 `SettingsTests` 是 `private`，需要把它改成 `fileprivate` 或在 extension 内复制。简化：在 extension 里复用 — 把 helper 提到顶层：

修改 `SettingsTests` 类内 `makeDefaults` 从 `private` 改为 `fileprivate`，使 extension 也能访问。

- [ ] **Step 2: 运行确认失败**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test \
  -only-testing:DictonaryTests/SettingsTests
```

Expected: 编译失败，`historyLimit` 未定义。

- [ ] **Step 3: 实现**

`Dictonary/Settings/Settings.swift` 修改：

`Key` 枚举里加：
```swift
static let historyLimit = "historyLimit"
```

属性区加：
```swift
@Published var historyLimit: Int {
    didSet {
        let clamped = max(0, min(500, historyLimit))
        if clamped != historyLimit {
            historyLimit = clamped
            return // didSet 再触发，下一次走另一分支
        }
        defaults.set(clamped, forKey: Key.historyLimit)
    }
}
```

`init` 里加：
```swift
let raw = defaults.object(forKey: Key.historyLimit) as? Int
self.historyLimit = max(0, min(500, raw ?? 50))
```

⚠️ 关于 didSet 的 re-entrancy：`historyLimit = clamped` 会再触发 didSet，这次 `clamped == historyLimit` 走 `defaults.set` 落盘。Swift 的 `didSet` 不会无限递归（赋同值时仍会触发，但内部判断会退出）。安全起见，写成更明确的形式：

```swift
@Published var historyLimit: Int {
    didSet {
        let clamped = max(0, min(500, historyLimit))
        if clamped != historyLimit {
            // Reassign to clamped value; didSet will run again with clamped == historyLimit.
            historyLimit = clamped
        } else {
            defaults.set(clamped, forKey: Key.historyLimit)
        }
    }
}
```

- [ ] **Step 4: 运行测试通过**

Expected: PASS, 4 new + 6 existing = 10 tests in SettingsTests.

- [ ] **Step 5: 提交**

```bash
git add Dictonary/Settings/Settings.swift DictonaryTests/SettingsTests.swift
git commit -m "feat(settings): add historyLimit (default 50, clamped 0-500)"
```

---

## Task 6: AppContainer 注入 HistoryStore

把 `HistoryStore` 实例化挂到 container，并把 store + initial limit 传给 ViewModel。

**Files:**
- Modify: `Dictonary/App/AppContainer.swift`
- Modify: `Dictonary/Window/TranslatorWindowController.swift:14-19` (init signature)

- [ ] **Step 1: 修改 AppContainer**

`Dictonary/App/AppContainer.swift`:

```swift
import AppKit

@MainActor
final class AppContainer {
    let settings: Settings
    let translationService: TranslationService
    let hotKeyManager: HotKeyManager
    let statusBar: StatusBarController
    let translator: TranslatorWindowController
    let historyStore: HistoryStore
    let dictTemplate: String
    let translTemplate: String

    init() {
        let s = Settings()
        self.settings = s
        self.translationService = TranslationService(settings: s)
        self.hotKeyManager = HotKeyManager()
        self.statusBar = StatusBarController()

        do {
            self.dictTemplate = try PromptBuilder.loadTemplate(named: "dictionary")
            self.translTemplate = try PromptBuilder.loadTemplate(named: "translation")
        } catch {
            fatalError("Missing prompt templates: \(error)")
        }

        let url = (try? HistoryStore.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: url, limit: s.historyLimit)
        self.historyStore = store

        // Keep the store's limit in sync with Settings.historyLimit changes.
        // The cancellable is held implicitly via the closure capture chain
        // — Settings outlives the container, so this is fine for app lifetime.
        s.$historyLimit.sink { [weak store] newLimit in
            store?.setLimit(newLimit)
        }.store(in: &cancellables)

        self.translator = TranslatorWindowController(
            service: translationService,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate,
            historyStore: store
        )
    }

    private var cancellables = Set<AnyCancellable>()
}
```

注意：要 `import Combine`，且 `cancellables` 的初始化顺序问题——属性初始化时不能用 `self`。改成在 `init()` 末尾设置，把 `cancellables` 声明为 `var` 默认空。已经是了。⚠️ Swift 限制：在 `self` 完全初始化前不能 `s.$historyLimit.sink { ... }.store(in: &cancellables)` —— 这是在 `init` 末尾用，`self` 已经完成初始化（所有属性赋过值），所以合法。

完整改动：
```swift
import AppKit
import Combine

@MainActor
final class AppContainer {
    let settings: Settings
    let translationService: TranslationService
    let hotKeyManager: HotKeyManager
    let statusBar: StatusBarController
    let translator: TranslatorWindowController
    let historyStore: HistoryStore
    let dictTemplate: String
    let translTemplate: String
    private var cancellables = Set<AnyCancellable>()

    init() {
        let s = Settings()
        self.settings = s
        self.translationService = TranslationService(settings: s)
        self.hotKeyManager = HotKeyManager()
        self.statusBar = StatusBarController()

        do {
            self.dictTemplate = try PromptBuilder.loadTemplate(named: "dictionary")
            self.translTemplate = try PromptBuilder.loadTemplate(named: "translation")
        } catch {
            fatalError("Missing prompt templates: \(error)")
        }

        let url = (try? HistoryStore.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: url, limit: s.historyLimit)
        self.historyStore = store

        self.translator = TranslatorWindowController(
            service: translationService,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate,
            historyStore: store
        )

        s.$historyLimit
            .dropFirst() // skip the initial replay; we already used the value above.
            .sink { [weak store] newLimit in
                Task { @MainActor in store?.setLimit(newLimit) }
            }
            .store(in: &cancellables)
    }
}
```

- [ ] **Step 2: 修改 `TranslatorWindowController` 构造函数签名**

`Dictonary/Window/TranslatorWindowController.swift` 的 `init`:

```swift
init(
    service: TranslationService,
    dictTemplate: String,
    translTemplate: String,
    historyStore: HistoryStore
) {
    self.historyStore = historyStore
    self.vm = TranslatorViewModel(
        service: service,
        dictTemplate: dictTemplate,
        translTemplate: translTemplate,
        historyStore: historyStore
    )
    // ... rest unchanged
}
```

并在类顶部添加：
```swift
private let historyStore: HistoryStore
```

- [ ] **Step 3: 编译通过**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: 运行测试通过**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test
```

Expected: 全部已有测试通过。

- [ ] **Step 5: 提交**

```bash
git add Dictonary/App/AppContainer.swift Dictonary/Window/TranslatorWindowController.swift
git commit -m "feat(app): wire HistoryStore through AppContainer"
```

---

## Task 7: WindowController 拆 hardHide / softHide + show 时按快照恢复

把现有的 `hide()` 拆成 `hardHide()` 和 `softHide()`，把 `show()` 改成新行为：检查 `pendingSnapshot` 决定恢复还是空白。

**Files:**
- Modify: `Dictonary/Window/TranslatorWindowController.swift`

- [ ] **Step 1: 改写 hide / show 部分**

把 `Dictonary/Window/TranslatorWindowController.swift` 中 `// MARK: - show/hide` 区域替换为：

```swift
// MARK: - Show / hide

private var pendingSnapshot: SessionSnapshot?

func toggle() {
    if panel.isVisible {
        bringToFront()
    } else {
        show()
    }
}

func show() {
    let restored: Bool
    if let snap = pendingSnapshot, snap.isFresh() {
        vm.restore(snap)
        restored = true
    } else {
        // Stale or absent → start clean.
        vm.reset()
        restored = false
    }
    pendingSnapshot = nil

    positionAtTopCenterOfMouseScreen()
    panel.makeKeyAndOrderFront(nil)
    installDismissMonitors()
    _ = restored // reserved for future telemetry / focus heuristics
}

/// Bring the already-visible panel to front and refocus its input.
func bringToFront() {
    panel.orderFrontRegardless()
    panel.makeKey()
    // The TextField captures focus on appear via @FocusState; no extra wiring needed.
}

/// Explicit dismiss (Esc / status-bar-while-visible). Clears the session.
func hardHide() {
    pendingSnapshot = nil
    removeDismissMonitors()
    panel.orderOut(nil)
    if NSApp.isActive {
        NSApp.hide(nil)
    }
    vm.reset()
}

/// Soft dismiss (click-outside / app deactivation). Preserve session for 5 minutes.
func softHide() {
    guard panel.isVisible else { return }
    pendingSnapshot = vm.snapshot()
    removeDismissMonitors()
    panel.orderOut(nil)
    if NSApp.isActive {
        NSApp.hide(nil)
    }
    // Note: vm state is intentionally NOT reset.
}

/// Backwards-compat alias used during the refactor — callers should migrate.
@available(*, deprecated, renamed: "hardHide")
func hide() { hardHide() }
```

把 `installDismissMonitors()` 中 Esc 的处理改成调 `hardHide()`：

```swift
if event.keyCode == 53 {
    self.hardHide()
    return nil
}
```

- [ ] **Step 2: 删除调用旧 `hide()` 的地方**

- `toggle()` 不再调用 `hide()` —— 已替换为 `bringToFront()`
- 让外部 caller（StatusBarController via `onOpen`）继续走 `toggle()`，行为是切换显示/拉前台，符合 spec

但 spec 要求"菜单栏图标点击（可见时）→ 硬关闭"。当前 `StatusBarController.onOpen` 关联的是 `translator.toggle()`，需要改：

修改 `Dictonary/App/AppDelegate.swift:14`:

旧：
```swift
container.statusBar.onOpen = { [weak self] in self?.container.translator.toggle() }
```

新：
```swift
container.statusBar.onOpen = { [weak self] in
    guard let self else { return }
    if self.container.translator.isVisible {
        self.container.translator.hardHide()
    } else {
        self.container.translator.show()
    }
}
```

为此需要在 `TranslatorWindowController` 暴露：
```swift
var isVisible: Bool { panel.isVisible }
```

`onPress`（hotkey）保持原有 `toggle()`，因为 spec 要求"热键再按 → 拉前台不关"，而 `toggle()` 已经把 visible-case 改为 `bringToFront()`。

- [ ] **Step 3: 编译通过**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: 手动验证**（无单元测试覆盖窗口层）

运行 app，依次验证：

1. 按热键 → 面板出现，输入 "test" 不回车
2. 按 Esc → 隐藏；再按热键 → 输入框为空 ✓
3. 按热键 → 输入 "test"，回车看到结果
4. 点击别的窗口（Finder/任意 app）→ 面板隐藏；2 分钟内按热键 → 上次输入和结果都还在 ✓
5. 同上但等 6 分钟以上 → 应空白
6. 面板可见时再按热键 → 不隐藏，停在前台 ✓
7. 菜单栏图标点击（面板可见）→ 隐藏 + 清空 ✓

如果 4 不工作，说明点外部还没有对应监听 —— 这是 Task 8 的内容，预期此时只有"Esc 后清空 + 热键拉前台"两条工作。

- [ ] **Step 5: 提交**

```bash
git add Dictonary/Window/TranslatorWindowController.swift Dictonary/App/AppDelegate.swift
git commit -m "feat(window): split hardHide/softHide and refit toggle to bring-to-front"
```

---

## Task 8: 外部点击监听 + app deactivate 触发 softHide

加全局鼠标监听和 `NSApplication.didResignActiveNotification` 观察，实现"点别处/Cmd+Tab → 软关闭"。

**Files:**
- Modify: `Dictonary/Window/TranslatorWindowController.swift`

- [ ] **Step 1: 增加监听器并接入 install / remove**

修改 `installDismissMonitors()` / `removeDismissMonitors()` 区域为：

```swift
// MARK: - Esc + outside click + app deactivation dismissal

private var localKeyMonitor: Any?
private var globalMouseMonitor: Any?
private var resignActiveObserver: NSObjectProtocol?

private func installDismissMonitors() {
    removeDismissMonitors()

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }

        if event.keyCode == 53 { // Esc
            self.hardHide()
            return nil
        }

        // Return = 36. Plain Return submits; Shift+Return falls through.
        if event.keyCode == 36 {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let meaningful = mods.subtracting(.numericPad)
            if meaningful.isEmpty {
                self.vm.submit()
                return nil
            }
        }

        return event
    }

    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
        // Any mouse-down outside our process means user is interacting with another app
        // — soft-dismiss so the panel doesn't sit on top of their work.
        self?.softHide()
    }

    resignActiveObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.softHide()
    }
}

private func removeDismissMonitors() {
    if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    if let o = resignActiveObserver {
        NotificationCenter.default.removeObserver(o)
        resignActiveObserver = nil
    }
}
```

把旧的 `localMonitor` 字段删掉（已替换为 `localKeyMonitor`）。

- [ ] **Step 2: 编译通过**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: 手动验证完整场景**

1. 召唤 → 输入 "abc" → 点 Finder → 面板隐藏
2. 立刻再按热键 → 面板回来，输入框还是 "abc" ✓
3. 召唤 → 输入并翻译 → Cmd+Tab 切走 → 切回（仍在 5 分钟内）→ 召唤 → 输入和结果都在 ✓
4. 软关闭 → 等 6 分钟（或临时把 `freshnessWindow` 改成 5 秒方便测试，验证完改回）→ 召唤 → 空白 ✓
5. 软关闭 → 立即 Esc 不可触发（面板已隐藏）；再次召唤后按 Esc → 清空 ✓

⚠️ 注意：`addGlobalMonitorForEvents` 不会捕获本进程内的事件，所以点击面板自己不会触发 softHide。这正是我们要的。

- [ ] **Step 4: 提交**

```bash
git add Dictonary/Window/TranslatorWindowController.swift
git commit -m "feat(window): soft-hide on outside click and app deactivation"
```

---

## Task 9: HistoryDrawerView 组件

抽屉 SwiftUI 视图，展示历史列表，支持上下导航和选中条目预览。

**Files:**
- Create: `Dictonary/Window/HistoryDrawerView.swift`

- [ ] **Step 1: 写组件**

`Dictonary/Window/HistoryDrawerView.swift`:

```swift
import SwiftUI

struct HistoryDrawerView: View {
    @ObservedObject var store: HistoryStore
    @Binding var selectedID: UUID?
    let onPick: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void

    var body: some View {
        if store.entries.isEmpty {
            Text("尚无历史记录")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.entries) { entry in
                            row(entry)
                                .id(entry.id)
                                .background(
                                    selectedID == entry.id
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(entry) }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .onChange(of: selectedID) { _, new in
                    if let id = new {
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.query)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)

            Text(preview(entry.result))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(relative(entry.timestamp))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func preview(_ s: String) -> String {
        let stripped = s
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.count <= 60 { return stripped }
        return String(stripped.prefix(60)) + "…"
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
```

- [ ] **Step 2: 编译通过**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build
```

Expected: BUILD SUCCEEDED. (尚未集成到 ContentView，所以 UI 看不到效果，只验证类型可用。)

- [ ] **Step 3: 提交**

```bash
git add Dictonary/Window/HistoryDrawerView.swift
git commit -m "feat(history): add HistoryDrawerView SwiftUI component"
```

---

## Task 10: ContentView 集成抽屉 + 键盘路由

在 `TranslatorContentView` 中加入抽屉，处理 Cmd+Y / Cmd+↑↓ / Enter / Backspace / Esc 的键盘交互。

**Files:**
- Modify: `Dictonary/Window/TranslatorContentView.swift`
- Modify: `Dictonary/Window/TranslatorWindowController.swift`

- [ ] **Step 1: ViewModel 增加抽屉状态**

在 `TranslatorViewModel` 类内追加：

```swift
// MARK: - History drawer state

@Published var isDrawerOpen: Bool = false
@Published var selectedHistoryID: UUID?

func toggleDrawer(history: HistoryStore?) {
    if isDrawerOpen {
        isDrawerOpen = false
        selectedHistoryID = nil
    } else {
        isDrawerOpen = true
        // Default selection: top entry, if any.
        selectedHistoryID = history?.entries.first?.id
    }
}

func moveSelection(in history: HistoryStore, by delta: Int) {
    // Opening via arrow keys: ensure drawer is open, then start at top/bottom.
    if !isDrawerOpen {
        isDrawerOpen = true
        selectedHistoryID = (delta < 0)
            ? history.entries.first?.id
            : history.entries.last?.id
        return
    }
    guard !history.entries.isEmpty else { return }
    let ids = history.entries.map(\.id)
    let currentIdx = ids.firstIndex(where: { $0 == selectedHistoryID }) ?? 0
    let newIdx = max(0, min(ids.count - 1, currentIdx + delta))
    selectedHistoryID = ids[newIdx]
}

func closeDrawer() {
    isDrawerOpen = false
    selectedHistoryID = nil
}

func confirmSelection(history: HistoryStore) {
    guard let id = selectedHistoryID,
          let entry = history.entries.first(where: { $0.id == id }) else { return }
    loadFromHistory(entry)
    closeDrawer()
}

func deleteSelection(history: HistoryStore) {
    guard let id = selectedHistoryID else { return }
    let ids = history.entries.map(\.id)
    let currentIdx = ids.firstIndex(of: id) ?? 0
    history.remove(id: id)
    // Move selection to next available entry, or close drawer if empty.
    if history.entries.isEmpty {
        closeDrawer()
    } else {
        let newIdx = min(currentIdx, history.entries.count - 1)
        selectedHistoryID = history.entries[newIdx].id
    }
}
```

`moveSelection` 等签名拿 `history: HistoryStore` 是为了不在 VM 里强引用 store；保持职责清晰（VM 不持有 store 之外的 UI-level 状态依赖。）

实际上 VM 已经 `historyStore: HistoryStore?`，可以直接用而不必从外部传。简化：

```swift
func toggleDrawer() {
    guard let store = historyStore else { return }
    // ... uses store directly
}
```

但是 `historyStore` 当前是 `private`。改为 `private(set)` 暴露给同模块测试。或者保持 private、提供包装函数。

为了减少重构，**保留 private**，让所有 drawer 方法接收 store 参数，由调用方（ContentView 持有 store）传入。`toggleDrawer(history:)` 等。修复上面签名：所有 drawer 方法都加 `history: HistoryStore` 参数。

更新版（覆盖上面）：

```swift
@Published var isDrawerOpen: Bool = false
@Published var selectedHistoryID: UUID?

func toggleDrawer(history: HistoryStore) {
    if isDrawerOpen {
        closeDrawer()
    } else {
        isDrawerOpen = true
        selectedHistoryID = history.entries.first?.id
    }
}

func moveSelection(in history: HistoryStore, by delta: Int) {
    if !isDrawerOpen {
        isDrawerOpen = true
        selectedHistoryID = (delta < 0)
            ? history.entries.first?.id
            : history.entries.last?.id
        return
    }
    guard !history.entries.isEmpty else { return }
    let ids = history.entries.map(\.id)
    let currentIdx = ids.firstIndex(where: { $0 == selectedHistoryID }) ?? 0
    let newIdx = max(0, min(ids.count - 1, currentIdx + delta))
    selectedHistoryID = ids[newIdx]
}

func closeDrawer() {
    isDrawerOpen = false
    selectedHistoryID = nil
}

func confirmSelection(history: HistoryStore) {
    guard let id = selectedHistoryID,
          let entry = history.entries.first(where: { $0.id == id }) else { return }
    loadFromHistory(entry)
    closeDrawer()
}

func deleteSelection(history: HistoryStore) {
    guard let id = selectedHistoryID else { return }
    let ids = history.entries.map(\.id)
    let currentIdx = ids.firstIndex(of: id) ?? 0
    history.remove(id: id)
    if history.entries.isEmpty {
        closeDrawer()
    } else {
        let newIdx = min(currentIdx, history.entries.count - 1)
        selectedHistoryID = history.entries[newIdx].id
    }
}
```

- [ ] **Step 2: ContentView 接收 store + 集成抽屉**

替换 `TranslatorContentView`：

```swift
struct TranslatorContentView: View {
    @ObservedObject var vm: TranslatorViewModel
    @ObservedObject var historyStore: HistoryStore
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputField

            switch vm.state {
            case .idle:
                EmptyView()
            case .streaming(let s) where s.isEmpty:
                Divider()
                ProgressView().controlSize(.small)
                    .padding(.vertical, 4)
            case .streaming(let s), .done(let s):
                Divider()
                ScrollView {
                    Text(LocalizedStringKey(s))
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            case .error(let msg):
                Divider()
                Text("⚠️ \(msg)")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            if vm.isDrawerOpen {
                Divider()
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                HistoryDrawerView(
                    store: historyStore,
                    selectedID: Binding(
                        get: { vm.selectedHistoryID },
                        set: { vm.selectedHistoryID = $0 }
                    ),
                    onPick: { entry in
                        vm.loadFromHistory(entry)
                        vm.closeDrawer()
                    },
                    onDelete: { entry in
                        historyStore.remove(id: entry.id)
                    }
                )
            }
        }
        .padding(14)
        .frame(width: 560)
        .onAppear { inputFocused = true }
    }

    @ViewBuilder
    private var inputField: some View {
        let base = TextField(
            "输入中文或英文，回车翻译（Shift+回车换行）",
            text: $vm.input,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .lineLimit(1...8)
        .focused($inputFocused)

        if #available(macOS 15.0, *) {
            base.writingToolsBehavior(.disabled)
        } else {
            base
        }
    }
}
```

- [ ] **Step 3: WindowController 中传入 store + 处理快捷键**

修改 `Dictonary/Window/TranslatorWindowController.swift` 的 `init`，构造 ContentView 时传入 store：

```swift
let view = TranslatorContentView(vm: vm, historyStore: historyStore)
self.host = NSHostingController(rootView: view)
```

修改 `installDismissMonitors()` 中 `localKeyMonitor` 增加键路由：

```swift
localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    guard let self else { return event }
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)

    // Esc = 53. Drawer-open: close drawer; otherwise: hard hide.
    if event.keyCode == 53 {
        if self.vm.isDrawerOpen {
            self.vm.closeDrawer()
        } else {
            self.hardHide()
        }
        return nil
    }

    // Return = 36. In drawer: confirm. Otherwise: submit.
    if event.keyCode == 36 {
        if mods.isEmpty {
            if self.vm.isDrawerOpen {
                self.vm.confirmSelection(history: self.historyStore)
            } else {
                self.vm.submit()
            }
            return nil
        }
    }

    // Cmd+Y = 16. Toggle drawer.
    if event.keyCode == 16 && mods == .command {
        self.vm.toggleDrawer(history: self.historyStore)
        return nil
    }

    // Cmd+↑ = 126, Cmd+↓ = 125.
    if mods == .command && (event.keyCode == 126 || event.keyCode == 125) {
        let delta = (event.keyCode == 126) ? -1 : 1
        self.vm.moveSelection(in: self.historyStore, by: delta)
        return nil
    }

    // ↑ / ↓ inside drawer.
    if self.vm.isDrawerOpen && mods.isEmpty && (event.keyCode == 126 || event.keyCode == 125) {
        let delta = (event.keyCode == 126) ? -1 : 1
        self.vm.moveSelection(in: self.historyStore, by: delta)
        return nil
    }

    // Backspace / Delete = 51 (delete-key) / 117 (forward-delete) inside drawer.
    if self.vm.isDrawerOpen && (event.keyCode == 51 || event.keyCode == 117) {
        self.vm.deleteSelection(history: self.historyStore)
        return nil
    }

    return event
}
```

- [ ] **Step 4: 编译**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: 手动验证**

1. 翻译 "hello" → 完成 → 看 history.json 文件应有一条
2. Cmd+Y → 抽屉打开，光标在第一条
3. Cmd+↓ → 选中第二条；Cmd+↑ → 选中第一条
4. Enter → 主区域显示选中条的 result，抽屉关闭
5. Cmd+Y 再开 → Backspace → 选中条被删
6. 抽屉打开按 Esc → 抽屉关，面板还在
7. 抽屉关闭按 Esc → 面板硬关闭
8. 历史空时 Cmd+Y → 抽屉显示"尚无历史记录"

- [ ] **Step 6: 提交**

```bash
git add Dictonary/Window/TranslatorContentView.swift Dictonary/Window/TranslatorWindowController.swift Dictonary/Window/HistoryDrawerView.swift
git commit -m "feat(window): integrate history drawer with keyboard navigation"
```

---

## Task 11: Settings UI 增加 History tab

**Files:**
- Create: `Dictonary/Settings/UI/HistorySettingsView.swift`
- Modify: `Dictonary/Settings/UI/SettingsView.swift`
- Modify: `Dictonary/App/AppDelegate.swift` (传 store 到 SettingsView)

- [ ] **Step 1: HistorySettingsView**

`Dictonary/Settings/UI/HistorySettingsView.swift`:

```swift
import SwiftUI

struct HistorySettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var historyStore: HistoryStore

    var body: some View {
        Form {
            Section {
                Stepper(
                    value: $settings.historyLimit,
                    in: 0...500,
                    step: 10
                ) {
                    LabeledContent("Keep last") {
                        Text("\(settings.historyLimit) entries")
                    }
                }
            } footer: {
                Text("Set to 0 to disable history. Range: 0–500.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Stored entries", value: "\(historyStore.entries.count)")
            }

            Section {
                Button("Clear History", role: .destructive) {
                    historyStore.clear()
                }
                .disabled(historyStore.entries.isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
```

- [ ] **Step 2: SettingsView 增加 tab**

修改 `Dictonary/Settings/UI/SettingsView.swift`：

```swift
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var historyStore: HistoryStore
    let translationService: TranslationService
    let onHotkeyChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, onHotkeyChanged: onHotkeyChanged)
                .tabItem { Label("General", systemImage: "gear") }

            ProviderSettingsView(settings: settings, translationService: translationService)
                .tabItem { Label("Provider", systemImage: "cloud") }

            HistorySettingsView(settings: settings, historyStore: historyStore)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 440)
    }
}
```

- [ ] **Step 3: AppDelegate 传 store 给 SettingsView**

修改 `Dictonary/App/AppDelegate.swift` 的 `showPreferences()`:

```swift
let view = SettingsView(
    settings: container.settings,
    historyStore: container.historyStore,
    translationService: container.translationService,
    onHotkeyChanged: { [weak self] in self?.reregisterHotkey() }
)
```

- [ ] **Step 4: 编译**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: 手动验证**

1. 打开 Preferences → 看到第三个 tab "History"
2. Stepper 调整数字，回到主面板触发翻译，看 disk 上 history.json 是否被裁切
3. "Clear History" 按下后立即 entries 清零；当列表空时按钮 disabled

- [ ] **Step 6: 提交**

```bash
git add Dictonary/Settings/UI/HistorySettingsView.swift Dictonary/Settings/UI/SettingsView.swift Dictonary/App/AppDelegate.swift
git commit -m "feat(settings): add History tab with limit and clear controls"
```

---

## Task 12: 全量回归 & spec 验收单核对

**Files:** 无新增；这是验证步骤。

- [ ] **Step 1: 跑完整测试套件**

```
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary test
```

Expected: 全部测试通过（含原有 + 新增 4 个测试文件 = `HistoryEntryTests`, `HistoryStoreTests`, `SessionSnapshotTests`, `TranslatorViewModelTests`）。

- [ ] **Step 2: spec 验收单逐项手动验证**

按 spec 第「验收标准」节核对：

- [ ] Esc 隐藏后再次召唤，输入框为空，无残留 result
- [ ] 点击面板外部 5 分钟内召唤，恢复上次 query + result
- [ ] 点击面板外部超过 5 分钟召唤，输入框为空（可临时改 `freshnessWindow = 5` 秒做快速验证，验证后**改回 300**！）
- [ ] Cmd+Tab 切走再 Cmd+Tab 回（隔 1 分钟），召唤恢复上次会话
- [ ] 面板可见时按热键，面板拉到最前并聚焦输入框，会话不被清
- [ ] 翻译完成后历史中多一条；连续相同 query 不重复入库
- [ ] 重启 app 后历史仍在
- [ ] Cmd+Y 打开/关闭抽屉；Cmd+↑↓ 进入抽屉并选中
- [ ] 抽屉内 Enter 恢复条目时不发起 API 调用（Network tab 监控或临时插入 print）
- [ ] Settings → "Clear History" 后历史立即清空
- [ ] 历史上限调小后多余条目被裁掉
- [ ] 抽屉打开/关闭时面板顶边不超出屏幕（在屏幕顶部测，原 panel 锚定逻辑应已 cover）

- [ ] **Step 3: 修任何回归后再 commit；无问题则跳过**

如发现 bug，逐 commit 修复，每个 commit subject 形如 `fix(window): ...`。

---

## Self-Review 备忘

写完这份计划后我自查的几个点：

- ✅ Spec 「核心交互模型」表格全部映射到 Tasks 7-8（hardHide/softHide/show 重构 + 监听）
- ✅ Spec 「历史记录」全部映射到 Tasks 1-2-9-10-11
- ✅ Spec 「时长智能恢复」映射到 Task 3（SessionSnapshot.isFresh）+ Task 7（show 时校验）
- ✅ Spec 「Settings 新增」映射到 Tasks 5 + 11
- ✅ 验收单 11 条均对应到 Task 12 的 manual checklist
- ✅ 类型一致性：`HistoryEntry`、`HistoryStore`、`SessionSnapshot`、`Mode`（复用现有）、`TranslatorViewModel.State`（复用现有）的方法名贯通各任务
- ✅ 每个 task 包含完整代码，无 "implement later" 或类似占位符

**风险提示**（在执行时留意）：
1. `addGlobalMonitorForEvents` + `didResignActiveNotification` 可能双触发 `softHide()` —— `softHide` 第一行 `guard panel.isVisible else { return }` 提供幂等保护
2. `TranslatorViewModel` 改动是替换整个类定义，注意保留现有的所有公开 API（`submit`, `reset` 等）
3. Settings `historyLimit` 的 didSet 钳位重赋值依赖 Swift didSet 行为；如果将来观察到死循环，改用显式 `_historyLimit` storage + computed wrapper
4. `flushForTesting()` 是 `#if DEBUG` 包裹的；release 构建不可见 —— 测试 target 在 Debug 构建下跑，没问题
