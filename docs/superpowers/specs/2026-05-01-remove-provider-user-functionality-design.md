# 删除 Provider 用户功能 — 设计文档

**日期**：2026-05-01
**目标**：移除所有面向用户的 provider 配置功能（设置面板、引导窗、状态栏指示器、Keychain），保留代码层的 multi-provider 骨架，API key 暂时硬编码到源码常量（占位空字符串）。

## 背景与动机

当前 Dictonary 让用户在 Preferences 的 Provider tab 中选择 provider、填写 API key、自定义 endpoint，并通过 Keychain 持久化。仓库未来不会公开发布，且作者计划将来用自家服务器统一做 provider 路由——意味着客户端不再需要把 provider 配置暴露给用户。

本次重构的目的：

1. 删除所有面向用户的 provider 相关 UI 与持久化路径。
2. 把 provider 配置（active provider、key、model、endpoint）收敛到一个独立的代码常量模块。
3. 保留 `ProviderKind` + 三个 `*Provider` 实现 + `TranslationService` 的多 provider 路由骨架，方便未来切换到服务器路由时不必重做。
4. `Settings` 退化为纯用户偏好（hotkey / launchAtLogin / historyLimit）。

## 范围

### 删除

- `Dictonary/Settings/UI/ProviderSettingsView.swift`
- `Dictonary/Settings/KeychainService.swift`（含 `protocol KeychainService` 与 `SystemKeychain`）
- `Dictonary/Onboarding/WelcomeView.swift`（以及 `Onboarding/` 目录如果空了）
- `DictonaryTests/KeychainServiceTests.swift`
- `DictonaryTests/Mocks/InMemoryKeychain.swift`
- `Settings` 中：`provider` / `model` / `endpoint` 字段及其 UserDefaults 持久化、`didOnboard` 字段、`apiKey(for:)` / `setAPIKey(_:for:)` / `deleteAPIKey(for:)` / `resolvedEndpoint(for:)` 方法、`keychain` 依赖、`Notification.Name.dictonaryAPIKeyChanged`
- `TranslationError.missingAPIKey` case
- `StatusBarController.needsAPIKey` 字段及其驱动的红点逻辑
- `AppDelegate`：`showWelcome()`、`refreshAPIKeyIndicator()`、`apiKeyObserver`、`welcomeWindow`、首次启动判断 `didOnboard` 的分支
- `SettingsView`：Provider tab

### 新增

- `Dictonary/Translation/ProviderConfig.swift`：硬编码 provider 配置的单一来源。

### 改动

- `Dictonary/Translation/TranslationService.swift`：构造不再依赖 `Settings`；从 `ProviderConfig` 读 active provider / key / model / endpoint。空 key 不做早返回，让 HTTP 层返回认证错误。
- `Dictonary/Settings/ProviderKind.swift`：移动到 `Dictonary/Translation/ProviderKind.swift`（纯领域类型，归到 Translation 模块更合理）。
- `Dictonary/Settings/Settings.swift`：仅保留 `hotkey` / `launchAtLogin` / `historyLimit`，构造函数去掉 `keychain` 参数。
- `Dictonary/Settings/UI/SettingsView.swift`：删除 Provider tab，去掉 `translationService` 参数。
- `Dictonary/App/AppContainer.swift`：`TranslationService(settings:)` 改为 `TranslationService()`；`SettingsView` 调用处去掉 `translationService` 参数。
- `Dictonary/App/AppDelegate.swift`：删除首次启动 Welcome 分支；启动逻辑简化为「非 login launch → show 翻译窗」；删除 API key 通知监听与状态栏红点刷新。
- `Dictonary/StatusBar/StatusBarController.swift`：删除 `needsAPIKey` 及其触发的图标切换。
- `DictonaryTests/SettingsTests.swift`：删除涉及 `provider` / `model` / `endpoint` / `apiKey` / `didOnboard` 的所有用例；保留 `hotkey` / `launchAtLogin` / `historyLimit` 用例。

### 不动

- `Translation/{DeepSeek,OpenAI,Claude}Provider.swift`、`SSEParser.swift`、`TranslationProvider.swift`
- 三个 `*ProviderTests`、`SSEParserTests`、`PromptBuilderTests`、历史相关代码与测试、`HotKeyManager`、`TranslatorWindowController` 等

## `ProviderConfig` 设计

```swift
import Foundation

enum ProviderConfig {
    /// Currently-active provider. Hardcoded; swap here to test other providers.
    static let active: ProviderKind = .deepseek

    /// API keys per provider. Empty string means "not configured yet".
    /// Filled in by the developer locally; this repo is not published.
    static let apiKeys: [ProviderKind: String] = [
        .deepseek: "",
        .openai:   "",
        .claude:   ""
    ]

    static func apiKey(for kind: ProviderKind) -> String { apiKeys[kind] ?? "" }
    static func model(for kind: ProviderKind) -> String { kind.defaultModel }
    static func endpoint(for kind: ProviderKind) -> URL { kind.defaultEndpoint }
}
```

设计说明：

- 纯 `enum`（无实例），所有成员 `static`：明确表达「单一全局配置」。
- `model` / `endpoint` 直接复用 `ProviderKind.defaultModel` / `defaultEndpoint`，目前没有偏离默认值的需求；保留方法形式，便于将来按 provider 单独覆盖。
- 不读环境变量、不读 Info.plist：作者要的就是「源码里写死」。

## `TranslationService` 改动

```swift
final class TranslationService {
    private let providers: [ProviderKind: TranslationProvider]

    init(providers: [ProviderKind: TranslationProvider]? = nil) {
        self.providers = providers ?? [
            .deepseek: DeepSeekProvider(),
            .openai:   OpenAIProvider(),
            .claude:   ClaudeProvider()
        ]
    }

    func translate(systemPrompt: String, userText: String) -> AsyncThrowingStream<String, Error> {
        let kind = ProviderConfig.active
        guard let provider = providers[kind] else {
            return AsyncThrowingStream { c in
                c.finish(throwing: TranslationError.network(message: "provider missing"))
            }
        }
        return provider.translate(
            systemPrompt: systemPrompt,
            userText: userText,
            apiKey: ProviderConfig.apiKey(for: kind),
            model: ProviderConfig.model(for: kind),
            endpoint: ProviderConfig.endpoint(for: kind)
        )
    }
}
```

要点：

- 不再持有 `Settings` 引用。
- 删除 `missingAPIKey` 早返回路径——空 key 调用走到 HTTP 401 的自然路径，错误通过现有 `TranslationError.http(...)` / `.network(...)` 表达；这与"先占位空 key"的临时性匹配。
- providers 注入参数保留，方便测试。

## 启动流程变化

`AppDelegate.applicationDidFinishLaunching` 简化后：

```swift
// 1) status bar
container.statusBar.onOpen = { ... toggle translator ... }
container.statusBar.onPreferences = { ... }
container.statusBar.onQuit = { NSApp.terminate(nil) }

// 2) hotkey
container.hotKeyManager.onPress = { [weak self] in self?.container.translator.toggle() }
_ = container.hotKeyManager.register(container.settings.hotkey)

// 3) login item
if container.settings.launchAtLogin { try? SMAppService.mainApp.register() }

// 4) first-pop heuristic — 不再做 didOnboard 分支
if !isLikelyLoginLaunch {
    DispatchQueue.main.async { [weak self] in self?.container.translator.show() }
}
```

删除字段：`welcomeWindow`、`apiKeyObserver`、`refreshAPIKeyIndicator()`、`showWelcome()`、`applicationDidBecomeActive` 中的红点刷新（整个方法可删，因为只剩这一件事）。

## 测试改动

- 删 `KeychainServiceTests.swift` / `Mocks/InMemoryKeychain.swift`。
- `SettingsTests`：删除涉及 `provider` / `model` / `endpoint` / `apiKey` / `didOnboard` 的用例；保留 / 收敛为：默认 hotkey、launchAtLogin、historyLimit 边界（0 / 50 / 500 / >500 截断）。
- 不为 `ProviderConfig` 写额外测试——它就是一组常量，没有可测的行为。

## 用户可见行为变化

| 行为 | 之前 | 之后 |
|---|---|---|
| 首次启动 | 弹 Welcome 引导去填 key | 直接弹翻译窗（与后续启动一致） |
| 状态栏图标 | 缺 key 时叠红点 | 始终无红点 |
| Preferences | General / Provider / History / About | General / History / About |
| 翻译失败提示 | 空 key → "Missing API Key" | 空 key → 透传 HTTP 401 错误（"http 401" / 网络错误文案） |

## 风险与回退

- `project.yml` 用 XcodeGen 生成 Xcode 工程，`sources` 是路径式（`- path: Dictonary` / `- path: DictonaryTests`），文件增删 / 移动后需运行 `xcodegen generate`（在仓库根目录）重新生成 `.xcodeproj`，否则 Xcode 不会感知。计划阶段会显式列出该步骤。
- 文件移动 `ProviderKind.swift` 用 `git mv` 保留历史。
- 删除 `TranslationError.missingAPIKey` 是 enum case 删除——调用方已统一在 `TranslationService` 里，外部无引用，编译期会发现遗漏。
- 回退路径：本次改动是单向的（删 UI + 删持久化），如需恢复用户配置功能，需重写 ProviderSettingsView 与 Keychain 接入，与未来"服务器路由"路线冲突；因此不准备保留兼容层。

## 不在本次范围

- 服务器端 provider 路由设计与实现。
- 已存在的 Keychain 中残留 key 的清理（macOS Keychain 中已写入的条目不主动删除；删除 keychain 代码后这些条目变成孤立项，无运行时影响）。
- General / History / About 三个 tab 的内容调整。
