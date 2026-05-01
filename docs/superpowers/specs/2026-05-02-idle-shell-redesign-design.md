# 空闲态外壳重做（Idle Shell Redesign）— Design

- 日期：2026-05-02
- 范围：QDict 翻译面板的"空闲态"外观与外壳——header / 输入框 / 底部快捷键提示条 / 窗口圆角与阴影
- 不在范围：结果展示区、历史抽屉的视觉与交互（保留当前实现，由后续单独 spec 处理）
- 受影响模块：`QDict/Window/`、`TranslatorPanel`、`Resources/Assets.xcassets`

---

## 1. 背景与目标

当前面板是单一 `TranslatorContentView`：顶部直接是输入框（占位符里塞了快捷键说明），下方是结果区与历史抽屉，外壳沿用 macOS 默认 `.titled` panel。

新版示意图引入了一套更克制、更"产品化"的空闲态外观：

- 顶部品牌栏（QDict 图标 + 文字 + 齿轮）
- 简化输入框（占位符只剩"输入中文或英文"，右侧出现 × 清空按钮）
- 底部常驻快捷键提示条
- 整体改为暖米色背景、圆角 12pt、柔和阴影

目标是一次性把"空闲态外壳"做完，不动结果与历史抽屉的实现，为后续结果页重做留出干净接缝。

## 2. 设计决策摘要

| # | 主题 | 决定 |
|---|---|---|
| 1 | 范围 | 只重做空闲态外壳：header / 输入框 / 底部提示条 / 窗口外观 |
| 2 | 齿轮按钮 | 软隐藏面板 + 打开 Preferences（与 Cmd+, 同一段处理逻辑） |
| 3 | 底部提示条 | 始终常驻（空闲 / 流式 / 有结果 / 抽屉打开都显示） |
| 4 | 清空 × 按钮 | 仅输入非空时显示；点击只清空 `vm.input`，不影响 `vm.state` |
| 5 | 输入光标 | 系统默认蓝色光标（示意图里那道竖条就是 caret，不需要自定义） |
| 6 | 配色 | 浅色：暖米色；深色：暖色暗调变体 |
| 7 | 窗口外壳 | borderless `NSPanel` + 自绘圆角 + 自定义阴影 |
| 8 | 品牌区 | "QDict" 用 SwiftUI 加粗文本；图标复用 AppIcon 缩到 24pt |

## 3. 架构

### 3.1 文件结构

```
QDict/Window/
  TranslatorContentView.swift   // 改写：只做编排
  TranslatorShell.swift         // 新：borderless 外壳（背景 + 圆角 + 阴影）
  TranslatorHeaderView.swift    // 新：图标 + "QDict" + 齿轮
  TranslatorInputView.swift     // 新：输入框 + × 清空按钮
  TranslatorHintsView.swift     // 新：底部快捷键提示条
  TranslatorTheme.swift         // 新：颜色 / 字号 / 间距常量
QDict/Resources/Assets.xcassets/Colors/
  PanelBackground.colorset      // 新：暖米色 / 暖色暗调
  PanelStroke.colorset
  DividerColor.colorset
  HintKeyBackground.colorset
  HintKeyStroke.colorset
  ClearButtonFill.colorset
QDictTests/
  TranslatorContentTests.swift  // 新：齿轮回调链路（如适用）
```

### 3.2 编排骨架

```
TranslatorShell {
  TranslatorHeaderView(onSettings: …)
  themedDivider
  TranslatorInputView(vm: vm, isFocused: $inputFocused)
  themedDivider
  TranslatorHintsView()
  resultSection      // 沿用当前 switch vm.state 渲染（不改）
  drawerSection      // 沿用当前 vm.isDrawerOpen 渲染（不改）
}
```

`TranslatorContentView` 的 body 不再持有视觉细节，只做编排与焦点管理。结果区/抽屉**原封搬入**新外壳，附在 hints 之下；面板向下扩展时整体仍由 `TranslatorShell` 圆角包裹。

### 3.3 不变的边界

- `TranslatorViewModel` 公共 API：完全不变
- `HistoryStore` / `HistoryDrawerView`：不动
- `AppContainer` / `AppDelegate` / `StatusBarController` / Hotkey：不动
- 设置面板（`SettingsView` 等）：不动
- 历史抽屉所有交互（↑↓ / Cmd+Y / Backspace / Enter / Esc）：不动
- `TranslatorWindowController` 的 dismiss monitors / softHide / hardHide / 位置计算：不动

## 4. 组件设计

### 4.1 `TranslatorTheme`（设计令牌）

集中视觉常量，浅深色自适应。`enum TranslatorTheme` + 静态属性，不持有状态。

**颜色**（用 Asset Catalog colorset，Any/Dark 双值；Theme 通过 `Color("Name", bundle: .main)` 引用）：

| 令牌 | Light | Dark |
|---|---|---|
| `panelBackground` | `#FBF7EE` | `#1F1C18` |
| `panelStroke` | `Color.black.opacity(0.06)` | `Color.white.opacity(0.08)` |
| `dividerColor` | `Color.black.opacity(0.08)` | `Color.white.opacity(0.10)` |
| `primaryText` | `Color.primary` | `Color.primary` |
| `secondaryText` | `Color.secondary` | `Color.secondary` |
| `hintKeyBackground` | `Color.black.opacity(0.05)` | `Color.white.opacity(0.08)` |
| `hintKeyStroke` | `Color.black.opacity(0.10)` | `Color.white.opacity(0.12)` |
| `clearButtonFill` | `Color.black.opacity(0.18)` | `Color.white.opacity(0.22)` |

**字号 / 字重：**

| 令牌 | 值 | 用途 |
|---|---|---|
| `brandFont` | `.system(size: 15, weight: .semibold)` | header "QDict" |
| `inputFont` | `.system(size: 18)` | 输入框（比当前 15pt 显著增大） |
| `hintLabelFont` | `.system(size: 12)` | 提示条文字 |
| `hintKeyFont` | `.system(size: 11, weight: .medium, design: .rounded)` | 键帽 |

**间距 / 尺寸：**

| 令牌 | 值 |
|---|---|
| `panelCornerRadius` | `12` |
| `panelShadowRadius` | `24` |
| `panelShadowOpacity` | `0.18` (light) / `0.45` (dark) |
| `panelShadowYOffset` | `8` |
| `headerPadding` | `EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)` |
| `inputPadding` | `EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)` |
| `hintsPadding` | `EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16)` |
| `panelWidth` | `560` |
| `headerIconSize` | `24` |
| `clearButtonSize` | `16` |

**深浅色判定：** colorset 天然适配；阴影 opacity 通过 `@Environment(\.colorScheme)` 在 `TranslatorShell` 内 runtime 选择。

### 4.2 `TranslatorShell`

泛型容器，吃 `@ViewBuilder` content；负责暖色背景、12pt 圆角、描边、自绘柔和阴影、统一宽度 560pt。

关键点：

1. **阴影绘制空间**：`.padding(panelShadowRadius)` 为阴影预留绘制区域，避免被 panel 边界裁切。`fittingSize` 含此 padding，`TranslatorWindowController` 现有 resize 订阅自动适配。
2. **panel 透明**：`TranslatorPanel` 设 `isOpaque = false; backgroundColor = .clear; hasShadow = false`，把外观完全交给 SwiftUI。
3. **Divider 自绘**：使用 `Rectangle().fill(TranslatorTheme.dividerColor).frame(height: 0.5)` 替代系统 `Divider`，保证在自定义背景上颜色可控。

### 4.3 `TranslatorHeaderView`

```
[icon 24pt] QDict (15pt semibold) ────────────── [gear 16pt]
```

- `onSettings: () -> Void` 作为构造参数
- AppIcon 通过 `NSImage(named: "AppIcon")` 桥接（`.icns` 多分辨率资源在 SwiftUI `Image("AppIcon")` 不稳定）
- 齿轮按钮命中区扩到 28×28pt（`.contentShape(Rectangle()).frame(width: 28, height: 28)`），视觉仍是 16pt 图标
- 悬停反馈：`.onHover` 切换 `foregroundStyle`（secondary → primary）
- `.accessibilityLabel("偏好设置")` + `.help("偏好设置（⌘,）")`

### 4.4 `TranslatorInputView`

```
[caret][输入文本/占位符]                              [×]
```

- 持有 `@ObservedObject vm`，焦点通过 `@FocusState.Binding` 由 ContentView 注入
- 占位符简化为 `"输入中文或英文"`
- `axis: .vertical` + `lineLimit(1...8)` 行为与现状一致
- `writingToolsBehavior(.disabled)` 在 macOS 15+ 下保留
- × 按钮渲染条件：`!vm.input.isEmpty`；视觉为深色半透明圆形 + 白色 `xmark` 图标，命中区 28×28pt
- × 出现/消失加 `.animation(.easeOut(duration: 0.12), value: vm.input.isEmpty)` 抑制跳动
- × 点击 → `vm.input = ""`；不调用 `vm.reset()`，不影响下方结果区
- 不对 caret 做任何自定义渲染——使用系统默认（accent color，默认为蓝色）

### 4.5 `TranslatorHintsView`

```
↵  翻译    ⇧ + ↵  换行    ⌘ + Y  历史记录    esc  关闭
```

- 静态视图，无状态，始终常驻
- 键帽用统一 `keyCap(_:)` 渲染：6pt 水平 padding、2pt 垂直 padding、4pt 圆角、半透明背景 + 边框
- `+` 用纯文本（不画键帽框）
- `esc` 全小写，与示意图一致
- 左对齐 + 右侧 `Spacer()`
- 键帽不可点击；快捷键的实际处理仍在 `TranslatorWindowController.installDismissMonitors()` 的 `localKeyMonitor`，本组件与之解耦

### 4.6 `TranslatorContentView` 改写

```swift
struct TranslatorContentView: View {
    @ObservedObject var vm: TranslatorViewModel
    @ObservedObject var historyStore: HistoryStore
    let onShowPreferences: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        TranslatorShell {
            TranslatorHeaderView(onSettings: onShowPreferences)
            themedDivider
            TranslatorInputView(vm: vm, isFocused: $inputFocused)
            themedDivider
            TranslatorHintsView()
            resultSection      // 沿用当前 switch vm.state
            drawerSection      // 沿用当前 vm.isDrawerOpen
        }
        .onAppear { inputFocused = true }
    }
}
```

`themedDivider` 是 `TranslatorContentView` 内部的一个 `private var`，渲染为 `Rectangle().fill(TranslatorTheme.dividerColor).frame(height: 0.5)`。

**hints 与结果的相对位置**：hints 紧贴输入区，结果区出现在 hints 下方。理由：当结果较长时 hints 不会被挤出视野；空闲与有结果两种状态下 hints 视觉位置一致。后续做结果页重做时可再调整。

### 4.7 `TranslatorPanel` 调整

```swift
super.init(
    contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
    styleMask: [.borderless, .nonactivatingPanel],   // 去掉 .titled / .fullSizeContentView
    backing: .buffered,
    defer: false
)
self.isOpaque = false
self.backgroundColor = .clear
self.hasShadow = false
self.isMovableByWindowBackground = true
self.level = .floating
self.hidesOnDeactivate = false
self.becomesKeyOnlyIfNeeded = false
self.isReleasedWhenClosed = false
self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
// standardWindowButton 隐藏代码删除（borderless 不存在这些按钮）
```

`canBecomeKey` / `canBecomeMain` / `setContentSize` 三个 override 完全保留。

### 4.8 `TranslatorWindowController` 改动

只两处：

1. 抽出私有方法 `private func showPreferencesAndSoftHide()`，封装"软隐藏 + 调用 `onShowPreferences`"。`localKeyMonitor` 中处理 Cmd+, 的分支改为调用此方法。
2. 构造 `TranslatorContentView` 时注入 `onShowPreferences: { [weak self] in self?.showPreferencesAndSoftHide() }`。

无其他改动。`vm.input` / `vm.state` / `vm.isDrawerOpen` / `historyStore.$entries` 的 resize 订阅照旧。

## 5. 数据流

齿轮点击的链路：

```
TranslatorHeaderView.gearButton.action
  → onSettings()
  → TranslatorContentView.onShowPreferences  // 闭包透传
  → TranslatorWindowController.showPreferencesAndSoftHide()
      → softHide()                             // 已有
      → self.onShowPreferences?()              // 已有，AppDelegate 注入
```

无新观察者、无新数据源。

## 6. 错误与边界处理

- `NSImage(named: "AppIcon")` 返回 nil（理论上不会发生）：使用空 `NSImage()` 作 fallback，不崩
- 点击面板阴影区域：阴影属于 panel.contentView 范围，`globalMouseMonitor` 不会把它判为"面板外"，不会触发软隐藏
- borderless panel + `isMovableByWindowBackground`：现有行为保持；测试需验证拖拽不与 SwiftUI 内的命中区冲突
- `setContentSize` top-anchored 修正：阴影 padding 改变了 fittingSize，但因为 fittingSize 始终自洽（含 padding），原有补偿逻辑仍然正确

## 7. 测试与验收

### 7.1 自动化测试

- macOS SwiftUI View 单测难度高，**不引入新依赖**（如 ViewInspector）
- 新增 `QDictTests/TranslatorWindowControllerTests.swift`：通过 `@testable import QDict`，覆盖 `showPreferencesAndSoftHide()`：注入一个测试用的 `onShowPreferences` 闭包，验证调用顺序为 `softHide()`（panel 不可见）→ `onShowPreferences` 闭包被调用一次
- 现有 VM/Service/Prompt 测试照常通过，作为回归基线

### 7.2 手动验收清单

1. 浅色模式下面板背景为暖米色，圆角 12pt，柔和阴影
2. 深色模式下面板为暖色暗调，无强烈反差
3. Header 左侧显示 AppIcon + "QDict"；右侧齿轮悬停高亮
4. 点击齿轮：面板软隐藏 + 偏好设置窗口打开（与 Cmd+, 行为一致）
5. 输入框为空时不显示 ×；输入后 × 出现；点击 × 仅清空 input，不影响下方结果区
6. 输入光标为系统默认蓝色
7. 底部提示条始终显示，文案与键位与示意图一致（↵ 翻译 / ⇧+↵ 换行 / ⌘+Y 历史记录 / esc 关闭）
8. 输入跨多行（Shift+Enter）时面板自适应增高
9. 流式输出过程中面板平滑增高，hints 紧贴输入框，结果在 hints 下方
10. 历史抽屉 Cmd+Y 打开、↑↓ 选择、Enter 选中、Backspace 删除、Esc 关闭——全部行为不变
11. Cmd+Tab 切走 / 点面板外 → 软隐藏；5 分钟内重新唤起恢复 session
12. Esc → 硬隐藏，重新唤起为干净状态
13. 面板被拖动后再唤起仍正常工作

### 7.3 回归风险点

- borderless panel + `isMovableByWindowBackground` 与 SwiftUI 命中区的兼容性
- `setContentSize` top-anchored 修正在新阴影 padding 下的正确性
- `globalMouseMonitor` 对阴影区域点击的行为（预期：算面板内，不软隐藏）

## 8. 不在本 spec 范围

以下内容由后续 spec 处理，本次实现保持现状：

- 结果展示区的视觉重做（字号 / 间距 / 样式）
- 历史抽屉的视觉重做
- hints 在不同状态下显示不同内容（如抽屉打开时换为抽屉相关键位）
- 齿轮菜单（"偏好设置 / 关于 / 退出"等多入口）
- AppIcon 之外的独立 brand mark 资源
