# Mac 中英翻译 App · 设计文档

- 日期：2026-04-30
- 作者：houxiaomu（与 Claude 协作）
- 状态：Draft，待用户审阅

## 1. 目标与定位

一个常驻 macOS 后台、通过快捷键或状态栏图标唤起的极简中英互译工具。
设计原则：**非常小巧、非常快、零打扰**。

### 1.1 核心需求

- 常驻后台（不在 Dock 显示）
- 唤起方式：全局快捷键 + 顶部状态栏图标点击
- 单输入框界面，回车后下方显示翻译及简短解释
- 支持中英双向（自动判方向）

### 1.2 性能与体积目标

- 包体积：< 5 MB
- 冷启动：< 150 ms
- 唤起到可输入：< 50 ms（窗口预创建）
- 翻译首字出现：< 500 ms（依赖 LLM provider）

### 1.3 非目标（明确不做）

- 不做翻译历史记录（v1 YAGNI）
- 不做离线词典 / 本地模型
- 不做语音输入 / TTS
- 不做 OCR 截图翻译
- 不做云同步设置

---

## 2. 技术选型

| 层 | 选择 | 备注 |
|---|---|---|
| 语言 / UI | Swift + SwiftUI | macOS 13 (Ventura) 起步 |
| 状态栏 | `MenuBarExtra` (SwiftUI 4) | 简化状态栏代码 |
| 全局快捷键 | Carbon `RegisterEventHotKey` | 系统原生、无依赖 |
| 翻译引擎 | 在线 LLM（多 provider 可切换） | 默认 DeepSeek |
| 流式协议 | SSE（OpenAI 兼容；Claude 走 messages stream） | |
| Key 存储 | macOS Keychain (`SecItem*` API) | service: `app.dictonary.api-keys` |
| 偏好存储 | UserDefaults | 仅非敏感字段 |
| 自启 | `SMAppService.mainApp` | macOS 13+ 原生 API |

---

## 3. 架构与模块划分

```
┌─────────────────────────────────────────────────────┐
│  AppDelegate (NSApplicationDelegate)                │
│   · 启动后隐藏 Dock 图标 (LSUIElement = true)        │
│   · 装配下面 6 个模块                                │
└─────────────────────────────────────────────────────┘
        │
        ├─ StatusBarController     状态栏图标 + 菜单（设置 / 退出）
        ├─ HotKeyManager           全局快捷键注册（Carbon API）
        ├─ TranslatorWindow        Spotlight 风格的 NSPanel
        ├─ TranslationService      LLM Provider 抽象 + 流式调用
        ├─ Settings                偏好持久化（UserDefaults + Keychain）
        └─ PromptBuilder           D 模式输入分类 + prompt 组装
```

### 3.1 模块职责与边界

- **StatusBarController**：仅负责状态栏图标与菜单，发"打开窗口"事件，不知道 LLM 存在。
- **HotKeyManager**：与 StatusBarController 对称，仅发"打开窗口"事件，注册失败要可捕获。
- **TranslatorWindow**：纯 UI，从外部接收 Settings 与 TranslationService，自身无业务逻辑。
- **TranslationService**：协议 + 多个实现（`DeepSeekProvider` / `OpenAIProvider` / `ClaudeProvider`）；新增 provider 不改动 UI。
- **PromptBuilder**：无副作用纯函数，输入文本 → 返回 `(mode, direction, prompt)`，单元测试友好。
- **Settings**：`ObservableObject`；UI 绑定后改设置即时生效。

### 3.2 关键设计原则

- 模块通过协议交互；UI 不直接依赖具体 provider 实现。
- `PromptBuilder` 与 `TranslationService` 都不持有窗口引用，可独立测试。
- 全局状态仅存在于 `Settings`；其余模块按需注入。

---

## 4. 交互流程

### 4.1 启动流程（一次性）

```
launch
  → AppDelegate.applicationDidFinishLaunching
  → 读取 Settings（provider / hotkey / 默认值）
  → StatusBarController 注册图标
  → HotKeyManager 注册快捷键（默认 ⌥Space）
  → TranslatorWindow 预创建但不显示（保证唤起 < 50ms）
  → 检查 Keychain 是否已有 API Key；缺失则在状态栏图标加红点
```

### 4.2 唤起 → 翻译 → 隐藏

```
快捷键按下 / 状态栏图标点击
  ↓
TranslatorWindow.show()
  · 计算屏幕中心偏上位置（多屏：以鼠标所在屏幕为准）
  · NSPanel.becomesKey = true，输入框自动获得焦点
  · 切换到非激活模式（不抢前台 App 焦点状态）
  ↓
用户输入文本 → 按回车
  ↓
PromptBuilder.build(text) → (mode, direction, systemPrompt)
  ↓
TranslationService.translate(systemPrompt:, userText:) → AsyncThrowingStream<String>
  · 调用所选 provider 的流式接口，增量 yield token
  ↓
SwiftUI @State 增量拼接 → 输出区即时刷新
  ↓
用户按 Esc / 点击窗口外 / 再次按快捷键
  ↓
TranslatorWindow.hide()  // 不销毁，留作下次秒开；清空输入与输出
```

### 4.3 取消行为

- 流式过程中重新输入并回车 → `Task.cancel()` 取消上一次请求，再发新请求。
- 流式过程中按 Esc → 取消请求并隐藏窗口。
- 取消视为正常路径，不展示错误。

### 4.4 默认快捷键

- `⌥Space`（Option+Space）：单手好按、与 Spotlight 的 `⌘Space` 区分。
- 用户可在设置内修改；冲突或注册失败则保留旧值并以状态栏气泡提示。

---

## 5. Prompt 与输入分类（D 模式核心）

逻辑收敛在 `PromptBuilder` 纯函数内。

### 5.1 模式判定（`classify`）

```swift
enum Mode { case dictionary, translation }

// 预处理：trim、压缩多余空白
// 1. 含句末标点（. ! ? 。！？）→ translation（视为完整句子）
// 2. 英文（按空格切词）：词数 ≤ 3 → dictionary
// 3. 中文（去除空格与标点后按 CJK 字符计数）：≤ 6 字 → dictionary
//    （此规则天然覆盖 4 字成语）
// 4. 其余 → translation
```

显式边界处理：

- 含句末标点（`Hello, world.` / `How are you?` / `好！`）→ translation
- 内部标点但无句末标点的短输入（如 `co-worker`）→ 按英文规则计算词数
- 纯数字 / 纯符号 → translation（让 LLM 处理）

### 5.2 语言方向（`detectDirection`）

```swift
enum Direction { case zhToEn, enToZh }
// 统计 CJK 字符占比，> 30% → zhToEn，否则 → enToZh
```

中英混杂走 `zhToEn`，LLM 会保留英文部分。

### 5.3 Prompt 模板

存放为 bundle 资源 `dictionary.txt` / `translation.txt`，方便迭代不改代码、测试可替换。

`dictionary.txt`（意图节选，最终文案在实现时精修）

```
You are a bilingual dictionary. Output Markdown:
- Line 1: → <translation>
- Then: 词性 / Part of speech
- Then: 释义 / Definition (1-3 senses, numbered if multiple)
- Then: 例句 / Examples (1-2, with translation)

Be concise. No preamble. No "here is the translation".
Direction: {{direction}}
```

`translation.txt`

```
You are a translator. Output Markdown:
- Line 1: <translation only>
- Blank line
- One short note about register, tone, or context (1 sentence, prefixed with "💡 "). Skip if nothing useful.

Be concise. No preamble.
Direction: {{direction}}
```

### 5.4 Provider 抽象

```swift
protocol TranslationProvider {
    func translate(systemPrompt: String, userText: String)
        -> AsyncThrowingStream<String, Error>
}
// 实现：DeepSeekProvider / OpenAIProvider / ClaudeProvider
// 三家统一通过 SSE 流式协议；Claude 使用 messages API + stream:true
```

---

## 6. 设置界面 与 首次启动

### 6.1 Settings 三个 Tab

```
General   · Hotkey 录制（默认 ⌥Space）
          · Launch at login
          · Show in menu bar

Provider  · Provider 下拉（DeepSeek / OpenAI / Claude）
          · API Key 输入 + Test 按钮
          · Model 选择
          · Endpoint（高级，覆盖默认）

About     · 版本、license、源码链接
```

- **Hotkey 录制**：捕获下一次组合键，注册成功才落库。
- **API Key 存储**：Keychain（service `app.dictonary.api-keys`，account = provider 名）。
- **`Test` 按钮**：发一个极短 ping 请求（`max_tokens=1`），结果即时显示在按钮旁。
- **UserDefaults**：仅存 hotkey、provider 选择、model、endpoint 覆盖等非敏感字段。

### 6.2 首次启动流程

```
首次启动检测：UserDefaults 没有 didOnboard 标记
  ↓
弹出 Welcome 面板（不打开 TranslatorWindow）
  · 一句话：「Set your API Key to start translating.」
  · [Open Preferences] → 直接跳到 Provider tab
  · [Skip for now] → 关闭面板，状态栏图标加红点
  ↓
配置完 Key 并 Test 通过
  ↓
didOnboard = true，红点消失
  ↓
后续启动直接进入待命状态
```

### 6.3 未配置 Key 的兜底

直接按快捷键时，输入框正常出现；按回车后下方显示
`⚠️ Please configure your API Key in Preferences ⌘,`，附按钮直达设置。
不弹窗、不卡死。

### 6.4 Login Item

`SMAppService.mainApp.register()` 注册开机自启；失败时友好提示但不阻塞使用。

---

## 7. 错误处理

仅在用户能感知的位置处理错误，内部不写防御性 `try?` 吞错。

### 7.1 错误分类

| 场景 | 检测点 | 用户看到 |
|---|---|---|
| 未配置 Key | 请求前 | `⚠️ 未配置 API Key`，按钮跳转设置 |
| 网络断开 | URLSession | `⚠️ 网络不可用，请检查连接`，按 Enter 重试 |
| Key 无效 | HTTP 401 | `⚠️ API Key 无效或已过期`，跳转设置 |
| 限流 | HTTP 429 | `⚠️ 请求过于频繁，稍后再试` |
| 服务端错误 | HTTP 5xx | `⚠️ <provider> 服务异常，可切换其他 provider` |
| 流中断 | 流式途中失败 | 已显示内容保留，末尾追加 `⚠️ 连接中断` |
| 快捷键注册失败 | 启动 | 状态栏气泡：`快捷键 ⌥Space 已被占用，请在设置修改` |
| Keychain 失败 | 设置时 | Alert 提示重启或检查权限 |

### 7.2 统一错误类型

```swift
enum TranslationError: LocalizedError {
    case missingAPIKey
    case network(underlying: Error)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, body: String?)
    case streamInterrupted(partial: String)
    case cancelled  // 用户主动取消，不展示
}
```

`TranslationService` 把底层错误映射到此枚举；UI 只做"枚举 → 文案"。

### 7.3 不做

- 不做错误日志持久化
- 不做自动重试队列
- 不做错误上报后端

---

## 8. 测试策略

聚焦逻辑层；UI 通过 SwiftUI Preview 覆盖各类状态。

### 8.1 单元测试

- **PromptBuilderTests**：模式判定 + 方向判定，覆盖单词 / 短语 / 成语 / 句子 / 标点 / 中英混杂 / 空白 / 极端长度。覆盖率目标 100%。
- **SettingsTests**：UserDefaults 读写 + Keychain 封装 mock。
- **TranslationProviderTests**：使用 `URLProtocol` mock 网络层，验证：
  - 三家 provider 请求体格式正确
  - SSE 流式增量解析正确
  - 各类 HTTP 错误正确映射到 `TranslationError`

### 8.2 集成测试

- 可选 target，需环境变量 `DEEPSEEK_API_KEY`；CI 不跑，本地手动验证。
- 用例：输入 `apple`，断言返回包含 "苹果"。

### 8.3 SwiftUI Preview

- 所有视图（`TranslatorWindow` 子视图、各 Settings tab）都有 `#Preview`。
- 注入 `MockTranslationService` 覆盖 loading / 流式中 / 完成 / 各类错误。

### 8.4 不测

- 全局快捷键真实注册（依赖系统状态）
- 状态栏图标渲染
- 真实 Keychain 写入（protocol mock 即可）

---

## 9. 开放问题（实现阶段决定）

- App 名称（仓库目录名 `dictonary` 看起来是 typo，发布前确认正式名称）
- App 图标设计
- DMG 打包与 notarization 流程（v1 是否分发到非自用机器）
- 未来若加历史记录，存储位置（SQLite / 文件 / Core Data）—— v1 不实现

---

## 10. 验收标准

- [ ] 启动后 Dock 无图标，状态栏出现图标
- [ ] 按 `⌥Space` 唤起窗口居中偏上；再按或 Esc 隐藏
- [ ] 输入 `apple` 回车，下方流式显示词典风格的中文释义
- [ ] 输入 `今天天气真好` 回车，流式显示英文翻译 + 一句风格提示
- [ ] 设置内切换 provider 后即时生效
- [ ] 未配置 Key 时按回车不会崩溃，提示清晰
- [ ] 包体积 < 5 MB，冷启动 < 150 ms（在 M 系列芯片上）
- [ ] PromptBuilder 单元测试 100% 覆盖
