# Input Suggestion 下拉建议 — 设计

- 日期：2026-05-05
- 涉及范围：QDict 主面板输入体验
- 目标：用户在输入框打字时实时弹出本地词典 + 历史融合的候选列表，支持键盘选择、Tab 补全、↵ 查询，达到 Raycast 风格的"输入即出"体感

---

## 1. 背景

QDict 当前是一个纯 LLM 流式翻译面板：
- `TranslatorViewModel.submit()` → `TranslationService.translate(...)` 走一次完整翻译；
- 输入框是 `TranslatorInputView` 里的普通 SwiftUI `TextField`；
- 历史靠 `HistoryStore`，通过 `Cmd+Y` 抽屉访问。

参考的 mockup（用户提供）显示：输入 `epi` 时，输入框正下方出现 6 行候选词列表，包含词性 + 中文短释 + 来源图标 + 选中态 + 右侧 `↵` 与"最近"角标，底部 hints 写明 `↑↓ 选择 / ↵ 查询 / tab 补全 / esc 关闭`。底部 hints 文案在 idle-shell 重设计里已经预先写入，本设计填上其语义。

**功能价值**
- 不需要联网就能立刻看到候选词的"长什么样"，省掉一次 LLM 往返才知道"我打的是哪个词"；
- 历史回放从 `Cmd+Y` 抽屉前移到键入路径上，老用户复查的成本降一档；
- 拼写直观：mockup 里"输入串前缀变浅、后缀变深"的 attributed 渲染让人眼能一眼校对拼写。

## 2. 范围与不做的事

**做：**
- 本地英文词典前缀建议（一期核心）；
- Tab 补全到选中项、↵ 在主动选过的情况下查选中词、Esc 撤回选择；
- 历史融合 + 同词合并 + "最近"角标 + 打分排序（二期）；
- 与现有 history drawer / streaming / IME 输入 / 键盘事件协调。

**不做（本设计明确排除）：**
- 拼写联想（mockup 里的 `Aₒ` 一类）——留作下一期，单独立项；
- 中文输入的下拉（含中文字符立即收下拉）；
- 词库的运行时更新机制（每次 release 直接换 bundle 文件）；
- 用户可见的"建议设置"开关（默认开启，不暴露偏好项）；
- 单元解耦之外的任何 SwiftPM 新依赖。

## 3. 决策汇总

| 主题 | 决定 | 备注 |
|---|---|---|
| 数据来源 | 本地内置词库 | 体验对延迟极敏感；离线可用 |
| 触发语种 | 仅英文（ASCII）输入 | 含中文字符立即收下拉 |
| 建议来源 | 词典 + 历史（二期）；不做拼写联想 | 一期只有词典 |
| 词库 | ECDICT 子集（COCA ≤ 15000 ∪ Collins ≥ 1 ∪ Oxford = 1） | 12–18 万条，bundle 5–8 MB |
| 选中后 ↵ | 用户主动按过 ↑/↓ 才用选中词；否则用输入框文本 | "Q5.C" |
| Tab 语义 | 补全到当前选中项的完整词；不触发 submit | "Q6.A" |
| 排序与融合 | 同词合并 + 打分（dictScore + α·histBonus） | α 让 3 天内查过的稳进前 3 |
| 触发条件 | 长度 ≥ 2，无 debounce | 本地查询亚毫秒级 |
| 提交后 | submit() 显式清空；streaming 期间短路；done 后键入新内容能恢复 | 与结果区不同框 |
| 末尾空格 | 收下拉（视为开始下一个词） | 中间空格不影响 — 短语词条仍可命中 |
| 节奏 | 切两期 | 一期：词典 + 下拉；二期：历史融合 + 角标 |

## 4. 总体架构

新增两个模块、修改两个现有文件。目录采用项目现有"按职能分包"约定：

```
QDict/
  Dictionary/                        ← 新模块
    LocalDictionary.swift            // 协议 + 内存数据结构
    SQLiteLocalDictionary.swift      // 实现
    EmptyLocalDictionary.swift       // 降级实现
    DictionaryEntry.swift            // word / pos / gloss / cocaRank
    DictionaryLoader.swift           // bundle SQLite 打开 + schema 校验
    Resources/
      ecdict.sqlite                  // 预生成产物，入 bundle
  Suggestion/                        ← 新模块
    SuggestionItem.swift             // 视图层使用的统一结构
    SuggestionEngine.swift           // 协议 + 短路逻辑
    DictionaryOnlySuggestionEngine.swift   // 一期实现
    MergedSuggestionEngine.swift     // 二期实现
  Window/
    TranslatorSuggestionsView.swift  // 新增视图
    TranslatorContentView.swift      // 改：插入下拉视图、ViewModel 增量
    TranslatorWindowController.swift // 改：扩展键盘拦截
  Resources/
    THIRD_PARTY_LICENSES.md          // 新增：ECDICT 来源声明
scripts/
  build-dictionary.swift             // 新增：从 ECDICT CSV 生成 SQLite
```

**模块边界承诺**
- `LocalDictionary` 不感知 UI、不感知历史；唯一 API 是 `prefix(_ s: String, limit: Int) -> [DictionaryEntry]`；
- `SuggestionEngine` 是 UI 层访问数据的唯一入口；视图永不直接读词库或历史；
- 一期 `DictionaryOnlySuggestionEngine` 只委托词库；二期 `MergedSuggestionEngine` 注入 `LocalDictionary` + `HistoryStore` 做融合，外部接口不变；
- `TranslatorViewModel` 拥有所有可观测状态，控制器只做键盘路由。

**数据流**

```
TextField.input change
  → TranslatorViewModel.refreshSuggestions(for:)   // bindInput sink
      → 短路检查（详 §6.1）
      → SuggestionEngine.query(prefix, limit: 6)
      → vm.suggestions = items
      → vm.selectionIndex = 0
      → vm.hasUserMovedSelection = false
TranslatorSuggestionsView 渲染 vm.suggestions / vm.selectionIndex
键盘事件
  → TranslatorWindowController 决策路由（详 §7） → vm 上对应方法
```

## 5. 数据层（一期核心）

### 5.1 词库选取

源：ECDICT free 版（公开 GitHub、MIT），其 CSV 含 `word, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange, detail, audio`。

筛规则（构建脚本 `scripts/build-dictionary.py`）：

```
keep if (frq <= 15000) OR (collins >= 1) OR (oxford == 1)   // ≥1 个质量信号
exclude if word contains '_'                                 // ECDICT 内部标记词条
exclude if translation is empty
note: frq == 0 在 ECDICT 里表示"未被 COCA 收录"——视为缺失（None），不当成"第 0 名"
note: 首字母大写的词跟其他词同等对待（也必须满足质量信号）。靠信号本身就能挡住绝大多数专名长尾，比单独用大小写规则更准
```

实际入库 ~16,800 条；bundle ~1.6 MB。比 spec 起草时预估的 5-8 MB / 12-18 万条小很多——原估算高估了 ECDICT 实际带词频/Collins 信号的词条覆盖度。当前规模已经覆盖了 COCA top 15k + Collins 5 星词，对"输入即出"的核心场景足够；如果后期发现某些用户常查词不在内，可考虑把 frq 门槛放宽到 25k 或纳入 BNC 词频。

### 5.2 SQLite Schema

```sql
CREATE TABLE entries (
    word     TEXT NOT NULL PRIMARY KEY,   -- 小写形态，用于前缀查找
    display  TEXT NOT NULL,               -- 原大小写
    pos      TEXT,                        -- 已截短的词性，如 "n." / "adj."；可为 NULL
    gloss    TEXT NOT NULL,               -- 单行中文释义；分号分隔多义；超长截断
    coca     INTEGER,                     -- 词频排名，越小越常用；NULL 视作 999999
    collins  INTEGER                      -- 1..5；预留二期使用
);
-- PRIMARY KEY 已隐式建索引；前缀查询用范围比较走该索引
```

`gloss` 在构建脚本里把 ECDICT 的 `translation` 字段做：`replace('\\n', '；')`、去首尾空白、超过 80 字符截断 + `…`。

### 5.3 查询 API

```swift
struct DictionaryEntry: Equatable {
    let word: String          // 即 display
    let pos: String?
    let gloss: String
    let cocaRank: Int         // 缺失时 .max
}

protocol LocalDictionary {
    func prefix(_ s: String, limit: Int) -> [DictionaryEntry]
}
```

`SQLiteLocalDictionary.prefix` SQL：

```sql
SELECT display, pos, gloss, coca
  FROM entries
 WHERE word >= ?lower AND word < ?lowerUpperBound
 ORDER BY coca ASC
 LIMIT ?limit;
```

`?lowerUpperBound` 由 `lower` 末位字符 +1 计算（仅 ASCII 输入；非 ASCII 在 §6.1 已被短路）。空 `lower` 视作非法、上层不会调到。入口处把传入串截到前 32 字节再用，防止粘贴超长输入。

### 5.4 加载与降级

App 启动时（在 `QDictApp.init` 或 `TranslatorWindowController` 注入点）：

```swift
let dict: LocalDictionary
do {
    dict = try DictionaryLoader.openBundled()    // 打开 bundle 内只读 sqlite，mmap
} catch {
    Log.warn("dictionary load failed: \\(error)")
    dict = EmptyLocalDictionary()
}
```

`EmptyLocalDictionary.prefix(...)` 永远返回 `[]`。任何加载失败 = 下拉永久为空 = QDict 退化为现有"纯 LLM 翻译"——**不弹错误对话框，不影响主流程**。

### 5.5 SQLite 接入

不引入 SwiftPM 依赖。直接用系统 `SQLite3` C API 写薄包装（约 60–100 行 Swift）：`open / prepare / bind / step / column_text / column_int / finalize / close`。理由：项目目前零三方依赖，保持现状的成本远小于带来的便利。

### 5.6 构建脚本

`scripts/build-dictionary.swift`（或 Python，与 `scripts/` 现有风格保持一致）：拉取 / 读取 ECDICT CSV → 应用 §5.1 筛规则 → 写 `QDict/Dictionary/Resources/ecdict.sqlite`。脚本不在 CI 里跑；产物入版本库，PR 里和代码一起 review。

License：bundle 时随附 `Resources/THIRD_PARTY_LICENSES.md`，引用 ECDICT 的 MIT 文本与项目地址。

## 6. 建议引擎

### 6.1 短路与触发

`TranslatorViewModel` 在 `init` 内绑定：

```swift
inputObserver = $input
    .removeDuplicates()
    .sink { [weak self] s in self?.refreshSuggestions(for: s) }
```

`refreshSuggestions` 顺序：

```
let trimmed = input.trimmingCharacters(.whitespacesAndNewlines)
let isASCII = trimmed.allSatisfy { $0.isASCII }
let endsWithSpace = input.last == " " || input.last == "\\t"
let isStreaming: Bool
if case .streaming = state { isStreaming = true } else { isStreaming = false }

if trimmed.count < 2 || !isASCII || endsWithSpace || isStreaming {
    suggestions = []
    selectionIndex = 0
    hasUserMovedSelection = false
    return
}

let items = engine.query(trimmed.lowercased(), limit: 6)
suggestions = items
selectionIndex = 0
hasUserMovedSelection = false
```

不做 debounce；本地查询足够快，60Hz 调用都安全。

注意：`refreshSuggestions` 由 `$input` 变化驱动，而 `submit()` 不改动 `input`——所以 `submit()` 内部要**显式**清空建议（在改 `state` 前一行）：

```swift
func submit() {
    suggestions = []
    selectionIndex = 0
    hasUserMovedSelection = false
    // …现有逻辑：trim、改 state、起 task
}
```

`reset()` 也同步清空。后续若用户回到 idle 重新键入，`$input` 自然驱动 `refreshSuggestions` 重新填回。

### 6.2 一期：DictionaryOnlySuggestionEngine

```swift
final class DictionaryOnlySuggestionEngine: SuggestionEngine {
    let dict: LocalDictionary
    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        dict.prefix(prefix, limit: limit).map { e in
            SuggestionItem(
                id: e.word.lowercased(),
                kind: .dictionary,
                word: e.word, pos: e.pos, gloss: e.gloss,
                badge: .none
            )
        }
    }
}
```

排序天然由 SQL `ORDER BY coca ASC` 给出。

### 6.3 二期：MergedSuggestionEngine

注入 `LocalDictionary` + `HistoryStore`：

```
1. dictHits = dict.prefix(prefix, limit: limit + 4)
2. histHits = historyStore.entries
                .filter { $0.query.lowercased().hasPrefix(prefix) }
                .map { (entry, daysSince(entry.timestamp)) }
3. merge by lowercased(word)：
     - 两边都命中 → kind = .dictionary, badge = .recent
     - 仅历史命中 → kind = .history,    badge = .recent
     - 仅词典命中 → kind = .dictionary, badge = .none
4. score:
     dictScore = (10000 - min(coca, 10000)) / 1000.0   // 0..10
     histBonus = 5.0 * exp(-daysSince / 7.0)           // 当天 ~5，1 周 ~1.8，2 周 ~0.7
     final     = dictScore + histBonus
5. sort by final DESC, take limit
```

α（`5.0`）目标是"3 天内查过的能稳进前 3"。这是常量；如未来需要微调，集中在 `MergedSuggestionEngine.swift` 顶部命名常量。

"仅历史命中"分支保留——这是历史融合相比"只刷词典"的关键增量，覆盖词典里没有但用户实际查过的词（人名、网络词、专有名词）。

### 6.4 性能预算

- 一期：`prefix` 单次 < 1ms（SQLite mmap + B-tree 索引）；
- 二期：内存内 merge / score；`HistoryStore` 上限本身不大，O(n) 全扫无忧；
- 视图：6 行行高 44pt，不上虚拟化。

## 7. UI 与 ViewModel

### 7.1 ViewModel 增量

在 `TranslatorViewModel` 上新增字段（不动现有字段）：

```swift
@Published var suggestions: [SuggestionItem] = []
@Published var selectionIndex: Int = 0
@Published private(set) var hasUserMovedSelection: Bool = false

var isSuggestionsVisible: Bool {
    !suggestions.isEmpty && !isDrawerOpen        // 与抽屉互斥可见
}
```

新增方法（语义来自 §3 决策）：

```swift
func moveSuggestionSelection(by delta: Int)
func acceptSuggestionForCompletion()                  // Tab：仅回填 input
func submitOrUseSelected()                            // ↵：移动过用选中词，否则 submit input
@discardableResult func cancelSuggestionSelection() -> Bool   // Esc 第一道
```

`acceptSuggestionForCompletion` 把 `input = item.word` 后**重置** `hasUserMovedSelection = false`——回填后再按 ↵ 走 submit，与"刚回填的词当然就是要查的词"直觉一致。

### 7.2 TranslatorSuggestionsView

```
VStack(spacing: 0) {
    ForEach(items.indices) { i in
        SuggestionRow(item: items[i], isSelected: i == selectionIndex)
            .onTapGesture { /* 回填 + submit */ }
    }
}
.frame(maxHeight: 6 * rowHeight)
```

`SuggestionRow`：
- **左图标**（24×24）：`.dictionary` 主题色背景 + 白色 "A"；选中行图标改强调色填充（mockup 里 epiphany 的橙块）；`.history`（二期）次要色 + 时钟符号；
- **主词**：`AttributedString`，前缀（用户已输入部分）次要色，剩余主色——mockup 中 "epi" 浅 + "phany" 深；
- **词性**：斜体灰；**短释**：浅灰，单行；超长 `…`；
- **右尾标**：选中行画 `↵` 图标；`badge == .recent` 行画"最近"小药丸；同时存在时 `↵` 在最右，"最近"在其左；
- 选中行整行套主题色淡背景 + 左侧 2pt 强调色竖条；
- 行高 44pt；HitTesting 整行；
- 点击 = `acceptSuggestionForCompletion()` + `submit()` 二步合成（不依赖 `hasUserMovedSelection`，因为点击本身是显式选择）。

### 7.3 整合到 TranslatorContentView

`TranslatorShell` 内子视图顺序变成：

```
TranslatorHeaderView
themedDivider
TranslatorInputView
themedDivider                       ← 始终保留；与 hints 之间的 divider 同款
TranslatorSuggestionsView           ← 新增；isSuggestionsVisible 控制显隐
TranslatorHintsView
resultSection                       ← 现有
drawerSection                       ← 现有
```

整个面板宽度复用 `TranslatorPanel` 当前自适应；下拉显示时面板高度增加 `min(suggestions.count, 6) * 44pt`。`resultSection` 在 `.idle` 下渲染 `EmptyView`，所以早期"下拉与结果区"不会同框；`submit()` 一旦进入 streaming，§6.1 短路把 suggestions 清空，下拉退场，结果区接管。

## 8. 键盘交互优先级

`TranslatorWindowController.installDismissMonitors` 的 if-链按下表组织。新逻辑是**插入分支 + 拆细 ↑/↓ 路由**，不是重写。

| 键 | 修饰 | 抽屉打开 | 建议下拉显示 | hasUserMovedSelection | 行为 |
|---|---|---|---|---|---|
| Esc | — | 是 | * | * | 关抽屉（现有） |
| Esc | — | 否 | 是 | 是 | `cancelSuggestionSelection()` 撤回选中（保留下拉） |
| Esc | — | 否 | * | 否 | hardHide（现有） |
| ↵ | 无 | 是 | * | * | `confirmSelection`（现有） |
| ↵ | 无 | 否 | * | * | `submitOrUseSelected()` ※ 替换原 submit |
| Tab | 无 | 否 | 是 | * | `acceptSuggestionForCompletion()` |
| Tab | 无 | 否 | 否 | — | 放给系统 |
| Tab | 无 | 是 | — | — | 放给系统（不在抽屉里抢 Tab） |
| ↑/↓ | 无 | 是 | — | — | `moveSelection(history)`（现有） |
| ↑/↓ | 无 | 否 | 是 | * | `moveSuggestionSelection(by:)` ※新增 |
| ↑/↓ | 无 | 否 | 否 | — | 放给系统 |
| Cmd+↑/↓ | ⌘ | * | * | * | `moveSelection(history)`（现有；强制开/动抽屉） |
| Cmd+Y | ⌘ | * | * | * | `toggleDrawer`（现有） |
| Cmd+, | ⌘ | * | * | * | 偏好设置（现有） |
| Backspace | 无 | 是 | — | — | 删除历史项（现有） |
| Backspace | 无 | 否 | 是 | * | 放给系统（删字 → 输入变化 → 下拉自然刷新） |
| 其他打字 | — | * | * | * | 放给系统 |

**约定**
- 抽屉与建议下拉互斥可见，所以表里没有"两者都显示"的格子；
- `hasUserMovedSelection` 只影响 ↵ 与 Esc 的语义，其余键不看；
- 鼠标点击行 = `acceptSuggestionForCompletion()` + `submit()`，绕开 `hasUserMovedSelection`。

`TranslatorHintsView` 文案保持不变：`↑↓ 选择 / ↵ 查询 / tab 补全 / esc 关闭`。

## 9. 边界与降级

1. **IME 合成态**：用户用中文输入法输中文时，合成期可能短暂出现 ASCII 字符，触发下拉短暂显示（< 1 秒）。短路条件 `!isASCII` 在最终选定中文那一刻立即生效。**已知行为**，不专门修。
2. **词库加载失败**：注入 `EmptyLocalDictionary`，下拉永远为空；不弹错误。
3. **建议刷新 vs submit 的竞态**：`submit()` 内部显式清空 `suggestions / selectionIndex / hasUserMovedSelection`（详 §6.1）；不依赖 `$input` 触发，因为 submit 不改 input。
4. **超长输入**：`LocalDictionary.prefix` 入口处把传入串截到前 32 字节，防止粘贴整段英文导致额外开销。
5. **大小写**：`word` 字段统一小写，`display` 保留原样；查询小写化、不触达"首字母大写"专名。
6. **多义释义**：构建脚本把 ECDICT 多行 translation 压成单行 + `；` 分隔；行内显示截断，完整释义仍由 ↵ 后的 LLM 给。

## 10. 测试

### 一期

```
QDictTests/
  DictionaryTests/
    LocalDictionaryTests.swift
      - prefix("epi", 6) 命中预期词、按 coca 升序
      - prefix("xyz123", 6) 返回空
      - 大小写不敏感（"EPI" 与 "epi" 同结果）
      - 32 字节以上输入正确截断、不崩
      - EmptyLocalDictionary 在所有输入下返回空
  SuggestionTests/
    DictionaryOnlySuggestionEngineTests.swift
      - 短语前缀 "look u" 命中含空格的词条
      - kind/badge/id 字段正确填充
  WindowTests/
    TranslatorViewModelSuggestionTests.swift
      - 短路：< 2 字符 / 含中文 / 末尾空格 / state = .streaming → suggestions = []
      - 状态为 .done 时键入新内容仍能触发建议刷新（不被短路）
      - input 变化触发 engine 调用（fake engine 验证入参）
      - moveSuggestionSelection 越界裁剪 + 设置 hasUserMovedSelection
      - acceptSuggestionForCompletion 仅回填、不 submit、重置 hasUserMovedSelection
      - submitOrUseSelected：未移动 → 用 input；移动过 → 用选中词
      - cancelSuggestionSelection 仅在"移动过且下拉可见"时返回 true 并重置选择
      - submit 进入 streaming → suggestions 清空
```

### 二期

```
SuggestionTests/
  MergedSuggestionEngineTests.swift
    - 同词在词典+历史 → kind=.dictionary, badge=.recent
    - 仅历史命中（词典里没有的词）保留，kind=.history
    - recencyDays = 0 的词得分能挤进前 3
    - recencyDays = 14 的词加成几乎消失
```

集成测试用 fake `LocalDictionary` / `HistoryStore`，不开真 SQLite。

## 11. 节奏 / Milestones

**Milestone 1 — 词典子系统 + 静态前缀建议（独立 PR）**
- `Dictionary/` 模块完整、ECDICT 子集打包脚本与产物；
- `DictionaryOnlySuggestionEngine`；
- `TranslatorSuggestionsView` 视图 + ViewModel 增量；
- 键盘事件全套：Tab / ↵ / ↑↓ / Esc 在新优先级表下工作；
- 测试套（一期范围）；
- 用户可见效果：输入即出建议、能选、能 Tab 补全、能 ↵ 查；

**Milestone 2 — 历史融合（独立 PR）**
- `MergedSuggestionEngine`；
- "最近"角标渲染；
- 同词去重；
- 测试套（二期增量）；
- 用户可见效果：历史项混入候选、查过的词在选项里能被认出。

**不做：** 拼写联想（独立后续）；用户偏好开关；运行时词库更新。

## 12. 风险与备注

- **包体增长 5–8 MB**：当前 QDict 是个轻量 macOS 工具类 app，分发渠道可承受；首次开启时间预计增加几十毫秒（mmap），不影响交互。
- **ECDICT 数据质量参差**：少量条目释义生硬。在 mockup 风格的 6 行候选里通常无伤大雅；如未来想升级，构建脚本是单一切入点。
- **键盘事件优先级表的边界**：建议在 PR 里贴一张同款表格作为 reviewer 速查；新增/修改键盘行为务必同步更新本设计与 hints 文案。
- **α 系数 5.0**：初值，需要在二期上线后凭手感调；调整点集中在 `MergedSuggestionEngine.swift` 顶部命名常量。
