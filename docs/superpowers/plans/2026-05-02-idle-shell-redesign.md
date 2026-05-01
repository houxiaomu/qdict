# 空闲态外壳重做（Idle Shell Redesign）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 spec `2026-05-02-idle-shell-redesign-design.md` 中描述的 QDict 空闲态外壳重做：新 header（图标 + QDict + 齿轮）、简化输入框（带 × 清空按钮）、常驻底部快捷键提示条、borderless panel + 暖色背景 + 圆角 + 自绘阴影。

**Architecture:** 新增 5 个 SwiftUI 文件（Theme / Shell / Header / Input / Hints）+ 1 个 Asset Catalog 颜色组；改写 `TranslatorContentView` 为编排层；`TranslatorPanel` 改为 borderless 透明；`TranslatorWindowController` 抽出 `showPreferencesAndSoftHide` 并把它注入给 ContentView。结果区与历史抽屉的渲染代码原样保留。

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (NSPanel/NSImage), xcodegen + xcodebuild。

**Spec：** [`docs/superpowers/specs/2026-05-02-idle-shell-redesign-design.md`](../specs/2026-05-02-idle-shell-redesign-design.md)

---

## 文件结构

**新增（6 个 colorset + 6 个 swift 文件 + 1 个测试）：**
- `QDict/Resources/Assets.xcassets/Colors/Contents.json` — 颜色组容器
- `QDict/Resources/Assets.xcassets/Colors/PanelBackground.colorset/Contents.json`
- `QDict/Resources/Assets.xcassets/Colors/PanelStroke.colorset/Contents.json`
- `QDict/Resources/Assets.xcassets/Colors/DividerColor.colorset/Contents.json`
- `QDict/Resources/Assets.xcassets/Colors/HintKeyBackground.colorset/Contents.json`
- `QDict/Resources/Assets.xcassets/Colors/HintKeyStroke.colorset/Contents.json`
- `QDict/Resources/Assets.xcassets/Colors/ClearButtonFill.colorset/Contents.json`
- `QDict/Window/TranslatorTheme.swift`
- `QDict/Window/TranslatorShell.swift`
- `QDict/Window/TranslatorHeaderView.swift`
- `QDict/Window/TranslatorInputView.swift`
- `QDict/Window/TranslatorHintsView.swift`
- `QDictTests/TranslatorWindowControllerTests.swift`

**修改：**
- `QDict/Window/TranslatorPanel.swift` — styleMask 改 borderless，背景透明
- `QDict/Window/TranslatorContentView.swift` — 改写 body 为编排层；新增 `onShowPreferences` 参数
- `QDict/Window/TranslatorWindowController.swift` — 抽出 `showPreferencesAndSoftHide` + 给 ContentView 注入闭包

---

## 通用命令

整个计划中以下命令会反复使用：

- 重新生成 Xcode 工程（添加新文件后必须执行）：
  ```bash
  xcodegen generate
  ```
- 构建（Debug）：
  ```bash
  xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
  ```
- 跑测试：
  ```bash
  xcodebuild -project QDict.xcodeproj -scheme QDict -derivedDataPath ./build test -quiet
  ```
- 启动 Debug 构建的 app（手动验收用）：
  ```bash
  open ./build/Build/Products/Debug/QDict.app
  ```

---

## Task 1：添加 Asset Catalog 颜色组

**目标：** 在 Asset Catalog 里建立 6 个颜色集，承载 spec §4.1 的暖色调色板。`QDict/Resources/Assets.xcassets` 已被 project.yml 列为资源目录，无需改 project.yml。

**Files:**
- Create: `QDict/Resources/Assets.xcassets/Colors/Contents.json`
- Create: `QDict/Resources/Assets.xcassets/Colors/PanelBackground.colorset/Contents.json`
- Create: `QDict/Resources/Assets.xcassets/Colors/PanelStroke.colorset/Contents.json`
- Create: `QDict/Resources/Assets.xcassets/Colors/DividerColor.colorset/Contents.json`
- Create: `QDict/Resources/Assets.xcassets/Colors/HintKeyBackground.colorset/Contents.json`
- Create: `QDict/Resources/Assets.xcassets/Colors/HintKeyStroke.colorset/Contents.json`
- Create: `QDict/Resources/Assets.xcassets/Colors/ClearButtonFill.colorset/Contents.json`

- [ ] **Step 1.1：写 colorset 容器的 Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/Contents.json`：

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 1.2：写 PanelBackground.colorset/Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/PanelBackground.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0.984", "green" : "0.969", "blue" : "0.933", "alpha" : "1.000" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0.122", "green" : "0.110", "blue" : "0.094", "alpha" : "1.000" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

> 浅色为 `#FBF7EE`（251/247/238 ≈ 0.984/0.969/0.933）；深色为 `#1F1C18`（31/28/24 ≈ 0.122/0.110/0.094）。

- [ ] **Step 1.3：写 PanelStroke.colorset/Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/PanelStroke.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0", "green" : "0", "blue" : "0", "alpha" : "0.060" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "1", "green" : "1", "blue" : "1", "alpha" : "0.080" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 1.4：写 DividerColor.colorset/Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/DividerColor.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0", "green" : "0", "blue" : "0", "alpha" : "0.080" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "1", "green" : "1", "blue" : "1", "alpha" : "0.100" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 1.5：写 HintKeyBackground.colorset/Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/HintKeyBackground.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0", "green" : "0", "blue" : "0", "alpha" : "0.050" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "1", "green" : "1", "blue" : "1", "alpha" : "0.080" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 1.6：写 HintKeyStroke.colorset/Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/HintKeyStroke.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0", "green" : "0", "blue" : "0", "alpha" : "0.100" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "1", "green" : "1", "blue" : "1", "alpha" : "0.120" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 1.7：写 ClearButtonFill.colorset/Contents.json**

文件 `QDict/Resources/Assets.xcassets/Colors/ClearButtonFill.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0", "green" : "0", "blue" : "0", "alpha" : "0.180" }
      }
    },
    {
      "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "1", "green" : "1", "blue" : "1", "alpha" : "0.220" }
      }
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 1.8：重新生成 Xcode 工程，确保资源被打包**

```bash
xcodegen generate
```

预期：无报错；生成完成。

- [ ] **Step 1.9：构建确认资源能编译**

```bash
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功（颜色尚未被代码引用，所以只是验证 catalog 没坏）。

- [ ] **Step 1.10：提交**

```bash
git add QDict/Resources/Assets.xcassets/Colors
git commit -m "$(cat <<'EOF'
feat(assets): add warm color palette for translator panel

Adds six color sets with light/dark variants for the upcoming idle
shell redesign: panel background, stroke, divider, hint key fill,
hint key stroke, and clear button fill.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2：创建 `TranslatorTheme.swift`

**目标：** 集中所有视觉常量，浅深色自适应。所有后续组件都从这里取值。

**Files:**
- Create: `QDict/Window/TranslatorTheme.swift`

- [ ] **Step 2.1：写 TranslatorTheme.swift**

文件 `QDict/Window/TranslatorTheme.swift`：

```swift
import SwiftUI

/// Centralized visual tokens for the translator panel chrome (idle shell).
/// Colors come from Asset Catalog and adapt to light/dark automatically.
enum TranslatorTheme {

    // MARK: - Colors

    static var panelBackground: Color { Color("PanelBackground") }
    static var panelStroke: Color { Color("PanelStroke") }
    static var dividerColor: Color { Color("DividerColor") }
    static var hintKeyBackground: Color { Color("HintKeyBackground") }
    static var hintKeyStroke: Color { Color("HintKeyStroke") }
    static var clearButtonFill: Color { Color("ClearButtonFill") }

    static var primaryText: Color { Color.primary }
    static var secondaryText: Color { Color.secondary }

    // MARK: - Fonts

    static let brandFont: Font = .system(size: 15, weight: .semibold)
    static let inputFont: Font = .system(size: 18)
    static let hintLabelFont: Font = .system(size: 12)
    static let hintKeyFont: Font = .system(size: 11, weight: .medium, design: .rounded)

    // MARK: - Geometry

    static let panelWidth: CGFloat = 560
    static let panelCornerRadius: CGFloat = 12
    static let panelShadowRadius: CGFloat = 24
    static let panelShadowYOffset: CGFloat = 8
    static let panelShadowOpacityLight: Double = 0.18
    static let panelShadowOpacityDark: Double = 0.45

    static let headerPadding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    static let inputPadding = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    static let hintsPadding = EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16)

    static let headerIconSize: CGFloat = 24
    static let clearButtonSize: CGFloat = 16
    static let touchTargetSize: CGFloat = 28
}
```

- [ ] **Step 2.2：重新生成工程并构建**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。Theme 文件目前没有引用方，但作为常量定义不会触发警告。

- [ ] **Step 2.3：提交**

```bash
git add QDict/Window/TranslatorTheme.swift
git commit -m "$(cat <<'EOF'
feat(window): introduce TranslatorTheme design tokens

Single source of truth for the idle shell's visual constants —
colors, fonts, paddings, geometry. Subsequent view files will
read from this enum.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3：创建 `TranslatorShell.swift`

**目标：** Borderless 外壳容器：背景 + 圆角 + 描边 + 自绘阴影 + 固定宽度。预留阴影绘制空间，避免被 panel 边界裁切。

**Files:**
- Create: `QDict/Window/TranslatorShell.swift`

- [ ] **Step 3.1：写 TranslatorShell.swift**

文件 `QDict/Window/TranslatorShell.swift`：

```swift
import SwiftUI

/// Borderless visual chrome for the translator panel. Wraps the entire
/// SwiftUI content tree, applies the warm background, rounded corners,
/// stroke, and a hand-drawn shadow. Reserves padding around itself so
/// the shadow has room to render without being clipped by the host
/// NSPanel's bounds.
struct TranslatorShell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(width: TranslatorTheme.panelWidth)
        .background(TranslatorTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: TranslatorTheme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TranslatorTheme.panelCornerRadius)
                .stroke(TranslatorTheme.panelStroke, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(
                colorScheme == .dark
                    ? TranslatorTheme.panelShadowOpacityDark
                    : TranslatorTheme.panelShadowOpacityLight
            ),
            radius: TranslatorTheme.panelShadowRadius,
            x: 0,
            y: TranslatorTheme.panelShadowYOffset
        )
        .padding(TranslatorTheme.panelShadowRadius)
    }
}
```

- [ ] **Step 3.2：重新生成工程并构建**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。Shell 暂无消费者。

- [ ] **Step 3.3：提交**

```bash
git add QDict/Window/TranslatorShell.swift
git commit -m "$(cat <<'EOF'
feat(window): add TranslatorShell — borderless chrome wrapper

Provides the rounded warm-background container with a hand-drawn
shadow and reserved padding so the shadow renders inside the host
panel's bounds.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4：创建 `TranslatorHintsView.swift`

**目标：** 底部常驻快捷键提示条。无状态、无依赖、可独立编译。

**Files:**
- Create: `QDict/Window/TranslatorHintsView.swift`

- [ ] **Step 4.1：写 TranslatorHintsView.swift**

文件 `QDict/Window/TranslatorHintsView.swift`：

```swift
import SwiftUI

/// Static keyboard-shortcut hint bar always shown at the bottom of the
/// idle shell. Decoupled from the actual key handling — the real
/// shortcuts are handled in `TranslatorWindowController`'s key monitor.
struct TranslatorHintsView: View {
    var body: some View {
        HStack(spacing: 18) {
            hint(keys: ["↵"],            label: "翻译")
            hint(keys: ["⇧", "+", "↵"],  label: "换行")
            hint(keys: ["⌘", "+", "Y"],  label: "历史记录")
            hint(keys: ["esc"],          label: "关闭")
            Spacer(minLength: 0)
        }
        .padding(TranslatorTheme.hintsPadding)
    }

    private func hint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                if key == "+" {
                    Text("+")
                        .font(TranslatorTheme.hintLabelFont)
                        .foregroundStyle(TranslatorTheme.secondaryText)
                } else {
                    keyCap(key)
                }
            }
            Text(label)
                .font(TranslatorTheme.hintLabelFont)
                .foregroundStyle(TranslatorTheme.secondaryText)
                .padding(.leading, 2)
        }
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(TranslatorTheme.hintKeyFont)
            .foregroundStyle(TranslatorTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(TranslatorTheme.hintKeyBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(TranslatorTheme.hintKeyStroke, lineWidth: 0.5)
            )
    }
}
```

- [ ] **Step 4.2：重新生成工程并构建**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。

- [ ] **Step 4.3：提交**

```bash
git add QDict/Window/TranslatorHintsView.swift
git commit -m "$(cat <<'EOF'
feat(window): add TranslatorHintsView — bottom shortcut bar

Always-visible keyboard hint bar showing Enter/Shift+Enter/Cmd+Y/Esc.
Static rendering — actual key handling stays in the window controller.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5：创建 `TranslatorHeaderView.swift`

**目标：** 顶部 header：左侧 AppIcon + "QDict" 文字，右侧齿轮按钮。齿轮通过 `onSettings` 闭包透传到 ContentView，ContentView 再透传到 Controller。

**Files:**
- Create: `QDict/Window/TranslatorHeaderView.swift`

- [ ] **Step 5.1：写 TranslatorHeaderView.swift**

文件 `QDict/Window/TranslatorHeaderView.swift`：

```swift
import SwiftUI
import AppKit

struct TranslatorHeaderView: View {
    let onSettings: () -> Void
    @State private var settingsHovered = false

    var body: some View {
        HStack(spacing: 8) {
            brandMark
            Text("QDict")
                .font(TranslatorTheme.brandFont)
                .foregroundStyle(TranslatorTheme.primaryText)

            Spacer(minLength: 0)

            settingsButton
        }
        .padding(TranslatorTheme.headerPadding)
    }

    private var brandMark: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(
                width: TranslatorTheme.headerIconSize,
                height: TranslatorTheme.headerIconSize
            )
            .accessibilityHidden(true)
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16))
                .foregroundStyle(
                    settingsHovered
                        ? TranslatorTheme.primaryText
                        : TranslatorTheme.secondaryText
                )
                .frame(
                    width: TranslatorTheme.touchTargetSize,
                    height: TranslatorTheme.touchTargetSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { settingsHovered = $0 }
        .accessibilityLabel("偏好设置")
        .help("偏好设置（⌘,）")
    }
}
```

- [ ] **Step 5.2：重新生成工程并构建**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。

- [ ] **Step 5.3：提交**

```bash
git add QDict/Window/TranslatorHeaderView.swift
git commit -m "$(cat <<'EOF'
feat(window): add TranslatorHeaderView — brand + settings row

AppIcon + "QDict" wordmark on the left, gear button on the right.
The gear invokes the injected onSettings closure; hover reveals a
subtle foreground change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6：创建 `TranslatorInputView.swift`

**目标：** 输入框 + × 清空按钮（仅非空时显示）。占位符简化为「输入中文或英文」。`@FocusState.Binding` 由 ContentView 注入。

**Files:**
- Create: `QDict/Window/TranslatorInputView.swift`

- [ ] **Step 6.1：写 TranslatorInputView.swift**

文件 `QDict/Window/TranslatorInputView.swift`：

```swift
import SwiftUI

struct TranslatorInputView: View {
    @ObservedObject var vm: TranslatorViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            textField
            if !vm.input.isEmpty {
                clearButton
            }
        }
        .padding(TranslatorTheme.inputPadding)
        .animation(.easeOut(duration: 0.12), value: vm.input.isEmpty)
    }

    @ViewBuilder
    private var textField: some View {
        let base = TextField("输入中文或英文", text: $vm.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(TranslatorTheme.inputFont)
            .lineLimit(1...8)
            .focused(isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)

        if #available(macOS 15.0, *) {
            base.writingToolsBehavior(.disabled)
        } else {
            base
        }
    }

    private var clearButton: some View {
        Button(action: { vm.input = "" }) {
            ZStack {
                Circle().fill(TranslatorTheme.clearButtonFill)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(
                width: TranslatorTheme.clearButtonSize,
                height: TranslatorTheme.clearButtonSize
            )
            .frame(
                width: TranslatorTheme.touchTargetSize,
                height: TranslatorTheme.touchTargetSize,
                alignment: .center
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清空输入")
    }
}
```

> 注意：`@FocusState.Binding` 通过 `FocusState<Bool>.Binding` 类型传递（与 SwiftUI 标准模式一致）。

- [ ] **Step 6.2：重新生成工程并构建**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。

- [ ] **Step 6.3：提交**

```bash
git add QDict/Window/TranslatorInputView.swift
git commit -m "$(cat <<'EOF'
feat(window): add TranslatorInputView — input field + clear button

Plain TextField with simplified placeholder; the clear (×) button
appears only when input is non-empty and clears just vm.input
(not vm.state). Focus is driven via an injected FocusState binding.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7：重构 `TranslatorWindowController` — 抽出 `showPreferencesAndSoftHide`

**目标：** 把 Cmd+, 处理逻辑里的「软隐藏 + 调用 onShowPreferences」抽成独立方法，方便齿轮按钮共用。本任务**不改变行为**，只重排结构。

**Files:**
- Modify: `QDict/Window/TranslatorWindowController.swift:178-186`

- [ ] **Step 7.1：在 controller 上加私有方法**

在 `TranslatorWindowController` 类内部、`removeDismissMonitors()` 之前的合适位置插入：

```swift
    /// Soft-hide the panel and notify the host (AppDelegate) to open
    /// Preferences. Shared by the Cmd+, key handler and the gear button
    /// in the header.
    fileprivate func showPreferencesAndSoftHide() {
        let openPrefs = onShowPreferences
        softHide()
        openPrefs?()
    }
```

> 用 `fileprivate` 而不是 `private`，是为了让 `@testable import QDict` 在测试目标内可以访问（详见 Task 10）。

- [ ] **Step 7.2：替换 Cmd+, 分支**

`TranslatorWindowController.swift` 第 181-186 行（Cmd+, 分支）：

```swift
            // Cmd+, = 43. LSUIElement apps have no main menu, so the standard
            // Preferences shortcut never reaches a responder while the panel is
            // key. Route it explicitly. Soft-hide first so the session is
            // preserved if the user dismisses Preferences.
            if event.keyCode == 43 && mods == .command {
                let openPrefs = self.onShowPreferences
                self.softHide()
                openPrefs?()
                return nil
            }
```

替换为：

```swift
            // Cmd+, = 43. Same path as the gear button in the header.
            if event.keyCode == 43 && mods == .command {
                self.showPreferencesAndSoftHide()
                return nil
            }
```

- [ ] **Step 7.3：构建并验证现有行为不变**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。

- [ ] **Step 7.4：跑一遍现有测试**

```bash
xcodebuild -project QDict.xcodeproj -scheme QDict -derivedDataPath ./build test -quiet
```

预期：所有现有测试通过。

- [ ] **Step 7.5：提交**

```bash
git add QDict/Window/TranslatorWindowController.swift
git commit -m "$(cat <<'EOF'
refactor(window): extract showPreferencesAndSoftHide

Pulls the Cmd+, handler body into a fileprivate method so the
upcoming gear button can reuse the exact same path. Behavior
unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8：把新外壳接进 ContentView + Panel + Controller

**目标：** 这是本计划唯一一个跨文件的"集成任务"——三个文件需要同步修改才能让面板从旧外观切换到新外观。

**Files:**
- Modify: `QDict/Window/TranslatorContentView.swift`（改写 body 与构造参数）
- Modify: `QDict/Window/TranslatorPanel.swift`（borderless + transparent）
- Modify: `QDict/Window/TranslatorWindowController.swift`（注入闭包）

- [ ] **Step 8.1：改写 TranslatorContentView 的 struct 与 body**

将 `TranslatorContentView.swift:147-225` 整个 `struct TranslatorContentView` 替换为：

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
            resultSection
            drawerSection
        }
        .onAppear { inputFocused = true }
    }

    // MARK: - Result section (preserved from previous implementation)

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

    // MARK: - History drawer section (preserved)

    @ViewBuilder
    private var drawerSection: some View {
        if vm.isDrawerOpen {
            VStack(alignment: .leading, spacing: 0) {
                themedDivider
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
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
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    private var themedDivider: some View {
        Rectangle()
            .fill(TranslatorTheme.dividerColor)
            .frame(height: 0.5)
    }
}
```

> 关键变化：
> - 新增 `onShowPreferences: () -> Void` 构造参数
> - 移除原 body 顶层的 `.padding(14)` 和 `.frame(width: 560)`（这两个职责现在归 `TranslatorShell`）
> - 结果区/抽屉的内部 padding 重新分布到 16pt 水平 + 10pt 垂直，以匹配新外壳的内部留白；功能逻辑不变
> - `themedDivider` 替代之前的系统 `Divider()`

- [ ] **Step 8.2：改写 TranslatorPanel.swift**

打开 `QDict/Window/TranslatorPanel.swift`，把 `init()` 整体替换为：

```swift
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.level = .floating
        // We previously set hidesOnDeactivate = true so the panel disappeared when
        // the app lost focus. That made the window vanish on any outside click and,
        // combined with status-bar reactivation quirks, sometimes left it
        // unreachable. Keep it visible until the user explicitly dismisses (Esc,
        // hotkey, or status-bar toggle).
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
```

> 关键变化：
> - styleMask 从 `[.titled, .fullSizeContentView, .nonactivatingPanel]` 改为 `[.borderless, .nonactivatingPanel]`
> - 删除 `titleVisibility` / `titlebarAppearsTransparent` 两行（borderless 没有标题栏）
> - 新增 `isOpaque = false; backgroundColor = .clear; hasShadow = false`（让 SwiftUI 自绘外观）
> - 删除 `standardWindowButton(.closeButton/.miniaturizeButton/.zoomButton)?.isHidden = true` 三行（borderless 不存在这些按钮）
> - `canBecomeKey` / `canBecomeMain` / `setContentSize(_:)` 三个 override **完全保留**

- [ ] **Step 8.3：在 TranslatorWindowController 里给 ContentView 注入闭包**

在 `TranslatorWindowController.swift:38` 处，把：

```swift
        let view = TranslatorContentView(vm: vm, historyStore: historyStore)
```

改为：

```swift
        let view = TranslatorContentView(
            vm: vm,
            historyStore: historyStore,
            onShowPreferences: { [weak self] in
                self?.showPreferencesAndSoftHide()
            }
        )
```

- [ ] **Step 8.4：构建**

```bash
xcodegen generate
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
```

预期：构建成功。

- [ ] **Step 8.5：跑现有测试**

```bash
xcodebuild -project QDict.xcodeproj -scheme QDict -derivedDataPath ./build test -quiet
```

预期：所有测试通过。

- [ ] **Step 8.6：提交**

```bash
git add QDict/Window/TranslatorContentView.swift QDict/Window/TranslatorPanel.swift QDict/Window/TranslatorWindowController.swift
git commit -m "$(cat <<'EOF'
feat(window): wire new idle-shell components

Composes TranslatorShell { Header / Input / Hints / result / drawer }
in TranslatorContentView, switches TranslatorPanel to a transparent
borderless NSPanel, and wires the gear-button callback through to
showPreferencesAndSoftHide().

Result and history drawer rendering are preserved with mildly
adjusted padding to fit the new shell's gutters; behavior unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9：手动验收

**目标：** 按 spec §7.2 的 13 项清单逐一 smoke-test。这是真正确认重做完成的关卡——SwiftUI 视觉无法靠测试覆盖。

**Files:** 无代码改动。

- [ ] **Step 9.1：构建并启动 Debug 版**

```bash
xcodebuild -project QDict.xcodeproj -scheme QDict -configuration Debug -derivedDataPath ./build build -quiet
open ./build/Build/Products/Debug/QDict.app
```

- [ ] **Step 9.2：浅色模式下走完 13 项手动验收**

切系统外观为 **浅色**，依次确认：

1. 面板背景为暖米色（≈ `#FBF7EE`），圆角 12pt 可见，柔和阴影向下散开
2. （此项 Step 9.3 检查）
3. Header 左侧显示 AppIcon + "QDict"；hover 齿轮，图标颜色变深
4. 点击齿轮：面板软隐藏 + 偏好设置窗口打开（与触发 Cmd+, 行为一致）。关闭偏好设置后再次 toggle 面板（hotkey）应在 5 分钟内恢复 session
5. 输入框为空时不显示 ×；输入"hello"后 × 出现；点击 × 仅清空输入文字，下方结果区（若有）保留不变
6. 输入光标颜色为系统蓝（accent color）
7. 底部提示条始终显示，文案为 `↵ 翻译 / ⇧+↵ 换行 / ⌘+Y 历史记录 / esc 关闭`
8. 输入框 Shift+Enter 换行，多行下面板自动增高
9. 按 Enter 触发翻译；流式过程中面板平滑增高，hints 紧贴输入框，结果显示在 hints 之下
10. 历史抽屉：Cmd+Y 打开 → ↑↓ 选择 → Enter 选中 → Backspace 删除一项 → Esc 关闭抽屉。所有交互不变
11. 面板可见时 Cmd+Tab 切走 → 面板消失（软隐藏）；hotkey 重新唤起 → session 恢复
12. 面板可见时按 Esc → 面板消失（硬隐藏）；hotkey 重新唤起 → 干净状态（输入空、无结果）
13. 拖动面板到屏幕其他位置后，按 hotkey 切换隐藏/显示，行为正常

如有任意一项不通过，记下问题并回到对应 Task 修复，再回到本步骤重测。

- [ ] **Step 9.3：深色模式下重测同样 13 项**

切系统外观为 **深色**，重做 Step 9.2 全部清单。重点确认第 2 项：面板为暖色暗调（≈ `#1F1C18`），整体不刺眼，与系统深色环境融合自然。

- [ ] **Step 9.4：完成后把验收记录提交（可选）**

如果发现需要轻微调整（如某 padding 需要微调 1–2pt），就地修改并 amend 进 Task 8 的 commit；如无修改，直接进入 Task 10。

---

## Task 10：添加 controller 测试

**目标：** 用单元测试覆盖 `showPreferencesAndSoftHide()` 的调用契约：先软隐藏面板，再触发 `onShowPreferences`。

**Files:**
- Create: `QDictTests/TranslatorWindowControllerTests.swift`

- [ ] **Step 10.1：写失败的测试**

文件 `QDictTests/TranslatorWindowControllerTests.swift`：

```swift
import XCTest
@testable import QDict

@MainActor
final class TranslatorWindowControllerTests: XCTestCase {

    private func makeController() -> TranslatorWindowController {
        let svc = TranslationService()
        let history = HistoryStore()
        return TranslatorWindowController(
            service: svc,
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}",
            historyStore: history
        )
    }

    func testShowPreferencesAndSoftHide_invokesCallbackAfterSoftHide() {
        let controller = makeController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "panel should be visible after show()")

        var prefsOpened = 0
        var visibilityWhenCallbackFired: Bool?
        controller.onShowPreferences = {
            prefsOpened += 1
            visibilityWhenCallbackFired = controller.isVisible
        }

        controller.showPreferencesAndSoftHide()

        XCTAssertEqual(prefsOpened, 1, "onShowPreferences must be invoked exactly once")
        XCTAssertEqual(visibilityWhenCallbackFired, false,
                       "panel must already be soft-hidden when the callback fires")
        XCTAssertFalse(controller.isVisible, "panel must remain hidden after the call")
    }

    func testShowPreferencesAndSoftHide_isSafeWhenNoCallbackInstalled() {
        let controller = makeController()
        controller.show()

        controller.onShowPreferences = nil
        controller.showPreferencesAndSoftHide()

        XCTAssertFalse(controller.isVisible)
    }
}
```

> 注意：测试需访问 fileprivate `showPreferencesAndSoftHide()`。`@testable import` 把 `internal` 暴露给测试，但访问不到 fileprivate。**调整：** Task 7 已用 `fileprivate`——这里需要把它升级为 `internal`（即把 `fileprivate` 关键字直接删除，使用默认 `internal`）。在写完测试后实施 Step 10.2。

- [ ] **Step 10.2：把 `showPreferencesAndSoftHide` 的可见性从 fileprivate 改为 internal**

在 `QDict/Window/TranslatorWindowController.swift` 中找到 Task 7 添加的方法定义：

```swift
    fileprivate func showPreferencesAndSoftHide() {
```

改为：

```swift
    func showPreferencesAndSoftHide() {
```

（删掉 `fileprivate` 关键字，使用 Swift 默认的 `internal` 访问级别。）

- [ ] **Step 10.3：重新生成工程**

```bash
xcodegen generate
```

- [ ] **Step 10.4：跑测试，确认通过**

```bash
xcodebuild -project QDict.xcodeproj -scheme QDict -derivedDataPath ./build test -quiet
```

预期：所有测试通过，含两个新增测试。

- [ ] **Step 10.5：提交**

```bash
git add QDictTests/TranslatorWindowControllerTests.swift QDict/Window/TranslatorWindowController.swift
git commit -m "$(cat <<'EOF'
test(window): cover showPreferencesAndSoftHide contract

Verifies the gear/Cmd+, code path: the panel must be soft-hidden
before onShowPreferences fires, and the call is safe when no
callback is installed. Promotes the helper from fileprivate to
internal so @testable can reach it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 自审

**1. Spec 覆盖率：**

- §3.1 文件结构：Task 1（colorsets）+ Task 2 + Task 3 + Task 4 + Task 5 + Task 6 + Task 8（改写 ContentView）+ Task 8（Panel）+ Task 8（Controller）+ Task 10（测试）✓
- §3.2 编排骨架：Task 8 Step 8.1 ✓
- §4.1 设计令牌（颜色/字号/间距）：Task 1 + Task 2 ✓
- §4.2 TranslatorShell（含阴影 padding 与 panel 透明）：Task 3 + Task 8 Step 8.2 ✓
- §4.3 Header（含 hover 反馈与 a11y）：Task 5 ✓
- §4.4 Input（含 caret 不自定义、× 动画）：Task 6 ✓
- §4.5 Hints（静态、`+` 纯文本、esc 小写）：Task 4 ✓
- §4.6 ContentView 改写（含 themedDivider）：Task 8 Step 8.1 ✓
- §4.7 Panel 调整：Task 8 Step 8.2 ✓
- §4.8 Controller 改动（抽方法 + 注入闭包）：Task 7 + Task 8 Step 8.3 ✓
- §5 数据流（齿轮 → onSettings → onShowPreferences → controller）：Task 5 + Task 8 Step 8.1/8.3 ✓
- §6 错误与边界：NSImage fallback 在 Task 5；阴影区域不触发软隐藏由 Task 9 Step 9.2 第 11 项验证 ✓
- §7.1 自动化测试（controller showPrefs 调用契约）：Task 10 ✓
- §7.2 手动验收 13 项：Task 9 ✓

无遗漏。

**2. Placeholder 扫描：** 无 TBD/TODO/"similar to N"/"add appropriate ..." 等占位。每个 step 都有具体代码或具体命令。

**3. 类型一致性：**

- `onShowPreferences` 在 ContentView/Header/Controller 三处一致：均为 `() -> Void`
- `showPreferencesAndSoftHide()` 在 Task 7 创建为 `fileprivate`，Task 10 升级为 `internal`，链路一致
- `TranslatorTheme` 在 Theme/Shell/Header/Input/Hints/ContentView 中引用的属性名与 Task 2 定义完全一致（`panelBackground`/`panelStroke`/`dividerColor`/`hintKeyBackground`/`hintKeyStroke`/`clearButtonFill`/`brandFont`/`inputFont`/`hintLabelFont`/`hintKeyFont`/`primaryText`/`secondaryText`/`panelWidth`/`panelCornerRadius`/`panelShadowRadius`/`panelShadowYOffset`/`panelShadowOpacityLight`/`panelShadowOpacityDark`/`headerPadding`/`inputPadding`/`hintsPadding`/`headerIconSize`/`clearButtonSize`/`touchTargetSize`）
- ContentView 构造签名 `(vm:historyStore:onShowPreferences:)` 在 Task 8 Step 8.1 定义、Step 8.3 调用，参数顺序一致
- Spec §4.4 提到 `@FocusState.Binding` —— Task 6 用 `FocusState<Bool>.Binding`（Swift 标准写法），Task 8 ContentView 用 `$inputFocused` 传入，匹配
