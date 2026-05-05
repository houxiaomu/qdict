# 结构化词典结果渲染 · 设计文档

- 日期：2026-05-05
- 作者：houxiaomu（与 Claude 协作）
- 状态：Draft，待用户审阅

## 1. 目标与定位

把 dictionary 模式下当前的"裸 Markdown 文本"渲染替换为**结构化、渐进式呈现的词典卡片**。
设计原则：**用排版做层级，不用装饰做层级**。无衬线、清晰留白分组、章节用大写小标签分隔。

### 1.1 核心需求

- LLM 输出格式从自由 Markdown 改为**行前缀格式**，便于增量解析
- Dictionary 模式查询结果以结构化卡片显示（主译文 / 词性 / 释义 / 例句 / 近义 / 用法）
- 流式过程中**每个 section 在其数据到位的瞬间出现**，不做整页切换
- 可选 section（近义、用法）缺失时不留空位、不显示占位符

### 1.2 非目标

- ❌ Translation 模式（句子翻译）维持现状 —— 自由文本无结构化字段
- ❌ 不新增方向指示器、复制译文按钮、⌘K 快捷键提示等 UI 元素（各自独立改动）
- ❌ 不做发音、收藏、Related 词跳转
- ❌ 不对 LLM 输出做内容校验或重试 —— 字段缺失视为"自然缺失"
- ❌ 历史抽屉的展示样式不变

---

## 2. LLM 输出格式

### 2.1 行前缀格式

每行一个字段，`|` 作分隔符，按固定顺序输出：

```
TRANS|苹果
POS|名词
DEF|1|一种常见、圆形的水果，外皮通常红色、绿色或黄色，果肉白色。
DEF|2|专有名词。指 Apple Inc.，美国跨国科技公司。
EX|She ate a crisp red apple for a snack.|她吃了一个脆红苹果当点心。
EX|He works as a software engineer at Apple.|他在苹果公司担任软件工程师。
SYN|fruit, orchard, iPhone, Mac
USAGE|常与 fresh / rotten 搭配
```

### 2.2 字段定义

| 前缀 | 形式 | 必需 | 说明 |
|---|---|---|---|
| `WORD` | `WORD\|<source>` | 是 | 查询源词。LLM 回显，便于确认对齐 |
| `IPA` | `IPA\|/ˈæp.əl/` | 否 | 仅英文词有；中文查询省略 |
| `TRANS` | `TRANS\|<primary translation>` | 是 | 单一主译文 |
| `POS` | `POS\|<part of speech>` | 是 | 多词性场景见 §2.3 |
| `DEF` | `DEF\|<n>\|<text>` | 至少一条 | `n` 为 1 起的整数序号 |
| `EX` | `EX\|<source>\|<translation>` | 0–3 条 | 例句源 + 译 |
| `SYN` | `SYN\|<comma-separated>` | 否 | 近义/相关词 |
| `USAGE` | `USAGE\|<one short sentence>` | 否 | 用法/搭配/语域 |

### 2.3 多词性

多词性词（如 `run`，既动词又名词）使用 `SENSE` 区块分隔：

```
WORD|run
IPA|/rʌn/
SENSE|动词|跑；运行；经营
DEF|1|用脚快速移动。
DEF|2|使（机器、程序）工作。
DEF|3|管理或经营（业务、组织）。
SENSE|名词|奔跑；一段时期
DEF|1|快速移动的过程。
EX|She runs every morning.|她每天早上跑步。
EX|He runs a small bakery.|他经营一家小面包店。
USAGE|"run a business" 是高频搭配。
```

`SENSE|<pos>|<primary translation for this pos>` 起一个新词性块；后续 `DEF` 行属于该 sense，直到下一个 `SENSE` 或非 `DEF` 行。

单词性时不出现 `SENSE`，直接走 `TRANS|...` + `POS|...` + `DEF|...` 的简化路径。

### 2.4 解析规则

- 每行用首个 `|` 之前的前缀决定字段类型
- 用 **`split(separator: "|", maxSplits: N)`** 提取字段：`DEF` 用 `maxSplits=2`，`EX` / `SENSE` 用 `maxSplits=2`，单字段如 `TRANS` 用 `maxSplits=1`
- 未识别的前缀（包括空白行、LLM 多输出的"啰嗦"）整行丢弃
- 字段顺序遵循约定，但 parser 不强校验顺序 —— 任意顺序都能解析

### 2.5 Prompt 改写

`QDict/Prompt/Prompts/dictionary.txt` 重写。要点：

- 强约束输出格式，给 6–8 个完整示例（覆盖单词性、多词性、中→英、短语、缺可选字段）
- 明确："Only output prefix lines. No prose, no markdown, no preamble."
- 保留方向（`{{direction}}`）模板变量
- 字数指引调整为"按字段输出，不要试图缩减字段"

---

## 3. 架构与模块划分

### 3.1 数据流

```
LLM token stream
      ↓
TranslationService.translate()  ──→  AsyncSequence<String>
      ↓ (每次 chunk 到达)
TranslatorViewModel
      ↓ (chunk 喂入)
StructuredStreamParser  ──→  DictionaryResult
      ↓ (@Published 发布)
DictionaryResultView  ──→  渐进式渲染
```

### 3.2 新增 / 修改模块

| 文件 | 操作 | 职责 |
|---|---|---|
| `QDict/Prompt/Prompts/dictionary.txt` | **重写** | 输出行前缀格式 |
| `QDict/Translation/DictionaryResult.swift` | **新增** | 纯数据模型 |
| `QDict/Translation/StructuredStreamParser.swift` | **新增** | 增量行扫描器 |
| `QDict/Window/DictionaryResultView.swift` | **新增** | 结构化卡片视图（B 风格）|
| `QDict/Window/TranslatorContentView.swift` | **小改** | dictionary 模式分流到新视图 |
| `QDictTests/StructuredStreamParserTests.swift` | **新增** | 解析器测试 |

### 3.3 职责边界

- **StructuredStreamParser**：纯逻辑，不知道 SwiftUI 存在，可在任何线程跑；通过 feed(chunk) → 返回最新 DictionaryResult。
- **DictionaryResult**：值类型，`Equatable`，所有字段可选或可空集合。
- **DictionaryResultView**：纯展示，从外部接收 `DictionaryResult`，无业务逻辑、无网络。
- **TranslatorViewModel**：胶水层，决定 dictionary 模式喂 parser、translation 模式走旧路径。

---

## 4. 数据模型

```swift
struct DictionaryResult: Equatable {
    var word: String?               // 源词回显
    var ipa: String?                // 仅英文词
    var primaryTranslation: String? // 单词性时的总主译文
    var primaryPOS: String?         // 单词性时的总词性
    var senses: [Sense]             // 多词性时多条；单词性时空数组
    var flatDefinitions: [Definition] // 单词性的释义；多词性时空数组（释义在 senses[i].definitions）
    var examples: [Example]
    var synonyms: [String]
    var usage: String?

    var isEmpty: Bool {
        word == nil && primaryTranslation == nil && senses.isEmpty && flatDefinitions.isEmpty
    }
}

struct Sense: Equatable {
    let pos: String                 // 例如 "动词"
    var primary: String?            // 该词性下的主译文
    var definitions: [Definition]
}

struct Definition: Equatable {
    let n: Int                      // 释义编号（1 起）
    let text: String
}

struct Example: Equatable {
    let source: String
    let translation: String
}
```

**取舍**：单词性 / 多词性两条路径在数据层就分开（`primaryTranslation` + `primaryPOS` vs `senses`），让 View 渲染逻辑直观，不需要"内部把单词性也包成单元素 senses 数组"的间接层。

---

## 5. StructuredStreamParser

### 5.1 接口

```swift
struct StructuredStreamParser {
    private(set) var result = DictionaryResult()
    private var buffer = ""
    private var currentSenseIndex: Int? = nil  // 当前 SENSE 块下标

    mutating func feed(_ chunk: String) -> DictionaryResult {
        buffer += chunk
        while let nlIdx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<nlIdx])
            buffer.removeSubrange(...nlIdx)
            consume(line: line)
        }
        return result
    }

    /// 流式结束时调用，处理最后一行没有 \n 的情形
    mutating func flush() -> DictionaryResult {
        if !buffer.isEmpty {
            consume(line: buffer)
            buffer = ""
        }
        return result
    }

    private mutating func consume(line: String) { /* ... */ }
}
```

### 5.2 行处理逻辑

```
对每一 line：
  trim 前后空白
  按首个 "|" 切前缀
  switch prefix {
    case "WORD":  result.word = rest
    case "IPA":   result.ipa = rest
    case "TRANS": result.primaryTranslation = rest
    case "POS":   result.primaryPOS = rest
    case "SENSE":
      // SENSE|<pos>|<primary?>
      let parts = rest.split(maxSplits: 1)
      append new Sense; currentSenseIndex = senses.count - 1
    case "DEF":
      // DEF|<n>|<text>
      解析 n 与 text
      if let idx = currentSenseIndex {
        result.senses[idx].definitions.append(...)
      } else {
        // 单词性：DEF 之间有顺序但 model 没承载，用 senses[0]?
        // 决定：单词性也存到一个隐式 sense，但 View 看 primaryTranslation 是否为非空决定走单词性渲染
        // → 见 §5.3
      }
    case "EX":    result.examples.append(...)
    case "SYN":   result.synonyms = rest.split(",").map(trim)
    case "USAGE": result.usage = rest
    default:      ignore
  }
```

### 5.3 单词性的 DEF 归属

单词性时输出顺序为 `WORD → IPA → TRANS → POS → DEF*`，没有 SENSE。
此时 `DEF` 行没有 `currentSenseIndex` 可归。处理：

- 把这些 `DEF` 追加到 `result.flatDefinitions`（模型字段已在 §4 定义）
- View 渲染时：`if senses.isEmpty { 渲染 primaryTranslation + primaryPOS + flatDefinitions } else { 渲染 senses }`

### 5.4 容错

- 未知前缀的行：丢弃，**不报错**
- 字段格式异常（如 `DEF|abc|text` 中 n 不是数字）：丢弃该行，继续
- UTF-8 跨 chunk 边界：`String += String` 在 Swift 中不会破坏 grapheme，安全
- 流式被取消：parser 状态丢弃即可，无需清理

### 5.5 测试覆盖

至少包括：

- ✅ 完整输入一次喂入
- ✅ 输入按 1-byte / 1-line / 跨行 chunk 切分喂入，结果一致
- ✅ 单词性、多词性各一组
- ✅ 中→英方向
- ✅ 缺 IPA / SYN / USAGE 的极简词
- ✅ 含 `|` 的释义文本（验证 `maxSplits` 正确）
- ✅ 未知前缀混入（验证容错）
- ✅ `flush()` 处理无尾换行
- ✅ Empty input

---

## 6. DictionaryResultView 渲染规范

### 6.1 视觉风格（B · 现代极简）

- 字体：`-apple-system`（即 `.system`）；中文走 PingFang SC
- 主词标题：24pt semibold，字距 -0.3
- IPA：12pt secondary
- 主译文：18pt medium
- 词性 pill：11pt secondary，1pt 边框，圆角 4pt
- 章节小标签：10pt 600 大写，字距 0.8，颜色 `#a89e80`
- 释义 / 例句正文：13.5pt
- 例句译文：12.5pt secondary

### 6.2 渐进渲染

视图直接 reactive 绑定 `vm.dictionaryResult`：

```swift
if let word = result.word { 标题行 }
if let ipa = result.ipa { IPA 行 }
if let trans = result.primaryTranslation, result.senses.isEmpty {
    主译文 + POS pill 行
}
if !result.senses.isEmpty { ForEach senses ... }
if !result.flatDefinitions.isEmpty || hasSenseDefs { 释义 section }
if !result.examples.isEmpty { 例句 section }
if !result.synonyms.isEmpty { 近义 section }
if let usage = result.usage { 用法 section }
```

每次 `result` 变更（@Published），SwiftUI 自动 diff，已存在的 section 不重渲染。

### 6.3 流式期间的过渡

- 第一个 token 到达前：显示现有的 `ProgressView`（保留当前实现）
- spinner 消失的触发条件：**`!dictionaryResult.isEmpty`**（即解析出至少一个有效字段）。这避免 LLM 先吐废话或空行时 spinner 提前消失留出空白
- 后续 section 各自就位
- 流式完成（task 自然结束）：调 `parser.flush()`，确保最后一行被处理；状态由 `streaming` 转为 `done`

### 6.4 错误状态

错误状态保持现有逻辑：

```swift
case .error(let msg): "⚠️ \(msg)" 红字
```

不影响结构化渲染。如果错误发生在流式中途（已有部分 result），决定：**清空 result，只显示错误**。理由：半截结果对用户没有价值，反而误导。

---

## 7. ViewModel 改动

```swift
@Published private(set) var dictionaryResult = DictionaryResult()

private var parser = StructuredStreamParser()

func submit() {
    // ... 现有代码
    if historyMode == .dictionary {
        parser = StructuredStreamParser()  // reset
        dictionaryResult = DictionaryResult()
    }
    task = Task { [weak self] in
        // ...
        for try await token in service.translate(...) {
            buffer += token
            if historyMode == .dictionary {
                self.dictionaryResult = self.parser.feed(token)
            } else {
                self.state = .streaming(buffer)  // 旧路径
            }
        }
        if historyMode == .dictionary {
            self.dictionaryResult = self.parser.flush()
        }
        self.state = .done(buffer)  // buffer 仍然存（用于历史/复制）
        // ...
    }
}
```

**注意**：`buffer` 保留 raw 字符串，原因：

1. 历史记录仍然存原始流（HistoryEntry 不变）
2. 复制译文功能（未来）可基于 raw 或 result 任意一种
3. 调试时能看 raw 输出

### 7.1 历史回放

`loadFromHistory(entry)`：raw `entry.result` 是行前缀文本。需要把它通过 parser 一次性转成 `DictionaryResult`，再赋给 `dictionaryResult`。

```swift
func loadFromHistory(_ entry: HistoryEntry) {
    task?.cancel()
    input = entry.query
    state = .done(entry.result)
    if entry.mode == .dictionary {  // HistoryEntry.mode 字段，与 ViewModel.historyMode 对齐
        parser = StructuredStreamParser()
        dictionaryResult = parser.feed(entry.result)
        dictionaryResult = parser.flush()
    } else {
        dictionaryResult = DictionaryResult()
    }
}
```

### 7.2 历史向后兼容

历史记录里可能存有**旧 Markdown 格式**的条目。处理：

- Parser 喂入旧 Markdown 时，所有行不命中前缀 → `dictionaryResult.isEmpty` 为 true
- View 检测到 `isEmpty` 且 raw 非空 → fallback 渲染 raw（沿用旧 `Text(LocalizedStringKey)` 路径）

不写迁移脚本，让旧记录在被打开时自动 fallback 即可。

---

## 8. TranslatorContentView 改动

`resultSection` switch 内部按 mode 分流：

```swift
case .streaming, .done:
    if vm.historyMode == .dictionary && !vm.dictionaryResult.isEmpty {
        DictionaryResultView(result: vm.dictionaryResult)
    } else {
        // 现有 ScrollView + Text(LocalizedStringKey(s)) 路径
        legacyMarkdownView(s)
    }
```

---

## 9. 测试策略

### 9.1 单元测试（必做）

`StructuredStreamParserTests`：覆盖 §5.5 列表

### 9.2 视图快照（建议）

`DictionaryResultView` 对四种边界 case（apple / 苹果 / run / give up / serendipity）出快照。本次 spec 不强制要求，但若新增视图后没有视觉验证手段，建议补上。

### 9.3 端到端

不引入新的 E2E 框架。手动验收：

- 启动 app，dictionary 模式查询 `apple` / `run` / `serendipity` / `苹果` / `give up`
- 校验流式过程中 section 渐进出现
- 校验从历史里点旧记录（旧格式 Markdown）能 fallback 显示
- 校验 translation 模式句子翻译不受影响

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| LLM 不严格遵守行前缀格式 | Prompt 给 6+ 示例；parser 容错跳过非法行；首版上线后采集 raw 输出统计违规率 |
| `\|` 出现在内容里把字段切错 | `maxSplits` 控制只切前 N 个 `\|`，尾部保留；释义/例句里出现 `\|` 概率极低 |
| 多词性的 SENSE 区块解析复杂 | Parser 维护 `currentSenseIndex` 单状态，逻辑清晰可测 |
| 历史里旧 Markdown 记录打不开 | `isEmpty` fallback 自动走旧渲染路径 |
| Prompt 改后 LLM 回归质量下降 | spec 通过后实施时与旧 prompt 对照测试 5 个常见词，确保解释质量不退步 |

---

## 11. 实施顺序建议

1. 写 `DictionaryResult` 模型 + `StructuredStreamParser` + 完整单测（**parser 先到位**）
2. 改写 `dictionary.txt` prompt，本地用 `swift test` 跑 parser 测试
3. 写 `DictionaryResultView`（先脱机用 mock data 跑）
4. 接入 `TranslatorViewModel` + `TranslatorContentView`
5. 端到端手动验收

每一步独立可跑，便于增量提交。
