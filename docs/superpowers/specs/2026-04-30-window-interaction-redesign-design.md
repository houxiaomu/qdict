# 窗口交互重设计 · Design Spec

**Date**: 2026-04-30
**Author**: brainstorming session (with houxiaomu)
**Status**: Draft, awaiting user review

---

## 背景与问题

当前实现使用 `NSPanel`（`.nonactivatingPanel` + `.floating`）配合菜单栏 app（`LSUIElement`）的形态：

- 没有 Dock 图标、Cmd+Tab 看不到 — 这是有意为之的「轻量召唤」定位（类 Spotlight/Raycast）
- 但目前存在以下交互问题：
  1. 切到后台再回来，会话数据被清空；用户预期至少在短时间内应保留
  2. 隐藏/恢复的行为没有区分用户意图（明确退出 vs 临时切走）
  3. 没有历史查询记录；查过的内容一旦清空就找不回
  4. 热键被设计成 toggle，可见时再按会隐藏，与「我想用它」的直觉相反

## 目标

保留「轻量召唤」的产品定位（仍然是菜单栏 app、无 Dock 图标、悬浮 panel），同时：

- 区分「硬关闭」与「软关闭」两种隐藏语义，分别匹配「我用完了」与「先放一边」的意图
- 短期内（5 分钟）保留软关闭的会话快照，再次召唤接续
- 提供持久化历史记录（默认 50 条），跨重启可查
- 修正热键 toggle 行为，可见时再按改为「拉到前台 + 聚焦」

## 非目标

- 不引入 Dock 图标 / 标准 NSWindow 形态
- 不做云端同步、不做加密存储
- 不引入收藏夹 / 标签 / 搜索高级筛选等历史增强功能

---

## 核心交互模型

### 隐藏语义（两类）

| 触发动作 | 语义 | 行为 |
|---|---|---|
| `Esc` 键 | 硬关闭 | 隐藏 + 立即清空会话 + 焦点还给上一个 app |
| 菜单栏图标点击（面板可见时） | 硬关闭 | 同 Esc |
| 点击面板外部 | 软关闭 | 隐藏 + 保留会话快照 + 启动 5 分钟过期计时器 + 焦点还给上一个 app |
| Cmd+Tab 切走 / app 失活 | 软关闭 | 同上 |
| 热键再按（面板可见时） | **不关闭** | 拉到最前 + 聚焦输入框 |

### 召唤行为（show）

| 当前状态 | 行为 |
|---|---|
| 面板已可见 | 拉前台 + 聚焦输入框（不重置内容） |
| 面板隐藏，存在未过期软关闭快照（≤5 分钟） | 恢复 query + result，焦点入输入框（默认全选 query） |
| 面板隐藏，无快照 / 快照已过期 / 上次为硬关闭 | 空白起点 |

### 5 分钟时长降级

- 软关闭瞬间记录 `capturedAt` 时间戳
- 下次召唤时：`now - capturedAt > 5min` → 视为快照过期，按「无快照」分支处理
- 不做强制定时清理，只在 show 时按需判断（实现简单，行为可预测）

---

## 历史记录

### 数据模型

```swift
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let query: String
    let result: String        // 完整翻译结果（streaming 完成后的最终文本）
    let timestamp: Date
    let mode: Mode            // 复用现有 Dictonary/Prompt/Mode.swift 的枚举
}
```

### 持久化

- 文件：`~/Library/Application Support/Dictonary/history.json`
- 上限默认 50 条，FIFO 淘汰；上限可在 Settings 里调整（0–500，0 = 禁用历史）
- 写入时机：每次翻译 **streaming 完成** 时追加一条；失败 / 用户中断 / Esc 中途取消都不写入
- 去重：连续两次完全相同的 query 不重复入库，覆盖最近一条的 timestamp
- 并发：使用串行 `DispatchQueue` 串行化文件读写（频率本就低，不会成为瓶颈）

### UI

- 默认隐藏，面板视觉上和现在一致
- 触发键：
  - `Cmd+Y` 切换抽屉显示/隐藏
  - `Cmd+↑` / `Cmd+↓` 打开抽屉并选中上一条/下一条
- 抽屉位置：面板下方扩展，复用现有 `setContentSize` 的 top-anchor 锚定逻辑
- 列表项格式：`[query]   [result 前 60 字]   [相对时间 5m / 2h / yesterday]`
- 抽屉内键盘交互：
  - `↑` / `↓` 选中
  - `Enter` 恢复选中条到主面板（**直接展示已存的 result，不重新调 API**），抽屉自动收起
  - `Delete` / `Backspace` 删除选中条（无二次确认；按错可重查）
  - `Esc` 优先关抽屉；抽屉已关时 Esc 才硬关面板

### 设置

Settings 新增 "History" 区块：

- "Keep last N entries"：数字输入，默认 50，范围 0–500
- "Clear History"：按钮，立即清空
- 当前条数显示

### 隐私

- 仅本地纯 JSON，不上传，不同步
- 不加密（内容是用户主动查询的文本，与 macOS 剪贴板/搜索历史一类，本地敏感性可控）

---

## 架构 / 文件级影响

### 新增文件

- `Dictonary/History/HistoryEntry.swift` — 数据模型
- `Dictonary/History/HistoryStore.swift` — 文件持久化、FIFO、`@Published var entries`、注入 `AppContainer`
- `Dictonary/Window/HistoryDrawerView.swift` — SwiftUI 抽屉组件

### 修改文件

**`TranslatorWindowController.swift`** — 主要改动点
- 拆 `hide()` → `hardHide()` / `softHide()`
- 改 `toggle()`：可见时调 `bringToFront()`（`makeKeyAndOrderFront` + 重聚焦），不再 hide
- 新增 `SessionSnapshot { query, result, capturedAt }`，由 ViewModel 提供 `snapshot()` / `restore(_:)`
- `show()` 内部判断快照新鲜度（5 分钟）决定恢复 / 空白
- `installDismissMonitors()` 增加：
  - global mouse monitor（点击面板外 → `softHide()`）
  - `NSApplication.didResignActiveNotification` 观察（→ `softHide()`）
- `hardHide()` 调 `vm.reset()`；`softHide()` 不 reset，记录快照时间戳
- localMonitor 中 `Esc` 调 `hardHide()`；`Cmd+Y` / `Cmd+↑↓` 转交给抽屉

**`TranslatorViewModel.swift`**
- `reset()` 保留
- 新增 `snapshot() -> SessionSnapshot?`（input/state 非空时返回快照）
- 新增 `restore(_ snapshot: SessionSnapshot)`
- 新增 `loadFromHistory(_ entry: HistoryEntry)`：把 query + result 直接塞回当前 state，不触发 API
- `submit()` 流式完成路径：调 `HistoryStore.append(...)`

**`TranslatorContentView.swift`**
- 主区下方加可选 `HistoryDrawerView` 子视图
- 抽屉显隐由 ViewModel 状态驱动

**`SettingsView.swift`**
- 新增 "History" 区块（输入上限、Clear History、当前条数）

**`AppContainer.swift`**
- 注入 `HistoryStore`

**`AppDelegate.swift`**
- 无大改动，依赖 container 中新加的 store

### 不变的文件

- `TranslatorPanel.swift` — styleMask / collectionBehavior 不动
- 菜单栏图标、热键管理、Onboarding、Prompt 配置等

---

## 边缘场景与风险

### 风险点

1. **`didResignActive` 触发覆盖范围**：需实测点击当前桌面 / Finder 是否触发（用户期望「点别处都软关闭」，覆盖范围应符合直觉）。
2. **全局 mouse monitor 资源**：`hide` 时必须移除，否则常驻消耗事件。
3. **抽屉展开高度变化**：复用现有 `TranslatorPanel.setContentSize` 的 top-anchor 锚定逻辑；测多种结果长度组合下的抽屉展开是否平滑。
4. **5 分钟过期校验**：用 show 时按需判断而非定时器，避免 macOS 后台 app 的 timer 漂移问题。
5. **历史文件并发写**：串行 queue；首次启动文件不存在 → 静默初始化为空；JSON 解析失败 → 备份原文件并重建空库。
6. **streaming 中途用户硬关闭**：取消请求，不写入历史。

### 边缘交互

- 翻译进行中按热键再按 → 拉前台 + 聚焦，但不打断 streaming
- 软关闭后 5 分钟内多次重新召唤 → 每次都恢复同一份快照（直到 Esc 或新 query 替换）
- 抽屉打开时按 Cmd+Y → 关闭抽屉
- 抽屉里翻历史时，原 query/result 是否保留？→ 抽屉内**预览**用临时态显示选中条；按 Esc 关抽屉时回到原 query/result，按 Enter 才正式替换
- 历史空时按 Cmd+Y / Cmd+↑↓ → 抽屉打开但显示空状态文案

---

## 验收标准

- [ ] Esc 隐藏后再次召唤，输入框为空，无残留 result
- [ ] 点击面板外部 5 分钟内召唤，恢复上次 query + result
- [ ] 点击面板外部超过 5 分钟召唤，输入框为空
- [ ] Cmd+Tab 切走再 Cmd+Tab 回（隔 1 分钟），召唤恢复上次会话
- [ ] 面板可见时按热键，面板拉到最前并聚焦输入框，会话不被清
- [ ] 翻译完成后历史中多一条；连续相同 query 不重复入库
- [ ] 重启 app 后历史仍在
- [ ] Cmd+Y 打开/关闭抽屉；Cmd+↑↓ 进入抽屉并选中
- [ ] 抽屉内 Enter 恢复条目时不发起 API 调用
- [ ] Settings → "Clear History" 后历史立即清空
- [ ] 历史上限调小后多余条目被裁掉
- [ ] 抽屉打开/关闭时面板顶边不超出屏幕

---

## 后续可考虑（明确不在本次范围）

- 历史搜索（filter）
- 历史导出 / 导入
- 历史项打星 / 收藏夹
- 加密存储
- iCloud 同步
- 鼠标右键菜单
