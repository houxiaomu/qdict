# 删除 Provider 用户功能 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all user-facing provider configuration (Provider settings tab, Welcome onboarding, status-bar red-dot indicator, Keychain) while keeping the multi-provider routing skeleton intact. API keys move to a single hardcoded `ProviderConfig` constants module (placeholders left empty for now).

**Architecture:** Introduce `ProviderConfig` as the single source of truth for active provider, API keys, model, and endpoint. `TranslationService` reads directly from `ProviderConfig` and no longer depends on `Settings`. `Settings` shrinks to user preferences only (hotkey / launchAtLogin / historyLimit). All provider-related UI, onboarding, and Keychain code is deleted along with their tests.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, XcodeGen.

**Reference spec:** `docs/superpowers/specs/2026-05-01-remove-provider-user-functionality-design.md`

---

## File Map

**New:**
- `Dictonary/Translation/ProviderConfig.swift` — hardcoded active provider, keys, model, endpoint accessors

**Move:**
- `Dictonary/Settings/ProviderKind.swift` → `Dictonary/Translation/ProviderKind.swift` (no content change; relocates with `git mv`)

**Modify:**
- `Dictonary/Translation/TranslationService.swift` — drop `Settings` dependency, read from `ProviderConfig`, drop `missingAPIKey` early-return
- `Dictonary/Translation/TranslationError.swift` — remove `.missingAPIKey` case
- `Dictonary/Settings/Settings.swift` — drop `provider`/`model`/`endpoint`/`didOnboard`/keychain helpers/notification
- `Dictonary/Settings/UI/SettingsView.swift` — drop Provider tab + `translationService` parameter
- `Dictonary/App/AppContainer.swift` — `TranslationService()` no-arg init; `SettingsView` callsite drops `translationService`
- `Dictonary/App/AppDelegate.swift` — remove `showWelcome`, `welcomeWindow`, `apiKeyObserver`, `refreshAPIKeyIndicator`, `applicationDidBecomeActive`, `didOnboard` branch
- `Dictonary/StatusBar/StatusBarController.swift` — drop `needsAPIKey`
- `DictonaryTests/SettingsTests.swift` — remove provider/key/endpoint/didOnboard cases; drop `keychain:` arg
- `DictonaryTests/TranslatorViewModelTests.swift` — drop `keychain:` and `settings:` args

**Delete:**
- `Dictonary/Settings/UI/ProviderSettingsView.swift`
- `Dictonary/Settings/KeychainService.swift`
- `Dictonary/Onboarding/WelcomeView.swift` (and the empty `Onboarding/` directory)
- `DictonaryTests/KeychainServiceTests.swift`
- `DictonaryTests/Mocks/InMemoryKeychain.swift`

---

## Conventions Used in This Plan

- **Build command:** `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
- **Test command:** `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
- **Project regen:** `xcodegen generate` (run from repo root after any add/delete/move under `Dictonary/` or `DictonaryTests/`)
- All commands run from repo root: `/Users/houxiaomu/playground/dictonary`
- This refactor is deletion-heavy. We keep the build green at every task by ordering: introduce new code → switch callers → delete obsolete code last. Tests run at every checkpoint.

---

## Task 1: Relocate `ProviderKind` to `Translation/`

`ProviderKind` is a pure domain enum. Moving it to `Translation/` makes the new `ProviderConfig` (also under `Translation/`) feel cohesive and removes the awkwardness of `Settings/` "owning" provider identity.

**Files:**
- Move: `Dictonary/Settings/ProviderKind.swift` → `Dictonary/Translation/ProviderKind.swift`
- Modify: project regen via `xcodegen generate`

- [ ] **Step 1: Move the file with git mv**

```bash
git mv Dictonary/Settings/ProviderKind.swift Dictonary/Translation/ProviderKind.swift
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `xcodegen generate`
Expected: `Generated project successfully` (or similar). No errors.

- [ ] **Step 3: Verify build still green**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: All tests pass (same as before — file content is unchanged).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(translation): move ProviderKind from Settings/ to Translation/

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `ProviderConfig`

Create the constants module that future tasks will switch callers onto. Pure additive — no caller changes yet, so build stays green.

**Files:**
- Create: `Dictonary/Translation/ProviderConfig.swift`

- [ ] **Step 1: Create `ProviderConfig.swift`**

Write `Dictonary/Translation/ProviderConfig.swift`:

```swift
import Foundation

/// Hardcoded provider configuration. Single source of truth for which provider
/// to call and what credentials to use.
///
/// This replaces user-configurable provider settings while keeping the
/// multi-provider routing skeleton in place. Future plan: swap these constants
/// for a server-side router.
enum ProviderConfig {
    /// Currently-active provider. Change here to test other providers.
    static let active: ProviderKind = .deepseek

    /// API keys per provider. Empty string means "not configured yet".
    /// Filled in locally; this repo is not published.
    static let apiKeys: [ProviderKind: String] = [
        .deepseek: "",
        .openai:   "",
        .claude:   ""
    ]

    static func apiKey(for kind: ProviderKind) -> String {
        apiKeys[kind] ?? ""
    }

    static func model(for kind: ProviderKind) -> String {
        kind.defaultModel
    }

    static func endpoint(for kind: ProviderKind) -> URL {
        kind.defaultEndpoint
    }
}
```

- [ ] **Step 2: Regenerate project**

Run: `xcodegen generate`
Expected: success.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Dictonary/Translation/ProviderConfig.swift Dictonary.xcodeproj
git commit -m "$(cat <<'EOF'
feat(translation): add ProviderConfig as single source of truth for provider

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Switch `TranslationService` onto `ProviderConfig`; remove `missingAPIKey`

Atomic swap of the service's dependency from `Settings` to `ProviderConfig`. `TranslationError.missingAPIKey` goes away in the same task because the only producer was the early-return inside `TranslationService.translate(...)`. We must update **all three** callers in the same commit (`AppContainer`, `ProviderSettingsView`, `TranslatorViewModelTests`) so the build stays green.

`ProviderSettingsView` — to-be-deleted in Task 4 — currently calls `translationService.translate(...)` from its "Test connection" button; that call site doesn't reference `Settings` directly so it keeps compiling after this task.

**Files:**
- Modify: `Dictonary/Translation/TranslationService.swift`
- Modify: `Dictonary/Translation/TranslationError.swift`
- Modify: `Dictonary/App/AppContainer.swift` (line 19: `TranslationService(settings: s)` → `TranslationService()`)
- Modify: `DictonaryTests/TranslatorViewModelTests.swift` (line 10: drop `settings:` arg)

- [ ] **Step 1: Rewrite `TranslationService.swift`**

Replace the entire contents of `Dictonary/Translation/TranslationService.swift` with:

```swift
import Foundation

final class TranslationService {
    private let providers: [ProviderKind: TranslationProvider]

    init(providers: [ProviderKind: TranslationProvider]? = nil) {
        self.providers = providers ?? [
            .deepseek: DeepSeekProvider(),
            .openai:   OpenAIProvider(),
            .claude:   ClaudeProvider()
        ]
    }

    /// Translates `userText` using `ProviderConfig.active`.
    /// Yields tokens as they stream. May throw `TranslationError`.
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

- [ ] **Step 2: Drop `.missingAPIKey` from `TranslationError`**

Edit `Dictonary/Translation/TranslationError.swift`. Remove the `case missingAPIKey` declaration on line 4, the `case .missingAPIKey:` switch arm in `errorDescription` (lines 13–14), and the `.missingAPIKey` pair in the `==` operator (line 33). Final file:

```swift
import Foundation

enum TranslationError: Error, LocalizedError, Equatable {
    case network(message: String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, body: String?)
    case streamInterrupted(partial: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .network(let m):
            return "网络不可用：\(m)"
        case .unauthorized:
            return "API Key 无效或已过期"
        case .rateLimited:
            return "请求过于频繁，稍后再试"
        case .serverError(let s, _):
            return "服务异常 (HTTP \(s))"
        case .streamInterrupted:
            return "连接中断"
        case .cancelled:
            return "已取消"
        }
    }

    static func == (lhs: TranslationError, rhs: TranslationError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
             (.cancelled, .cancelled):
            return true
        case let (.network(a), .network(b)):
            return a == b
        case let (.rateLimited(a), .rateLimited(b)):
            return a == b
        case let (.serverError(s1, b1), .serverError(s2, b2)):
            return s1 == s2 && b1 == b2
        case let (.streamInterrupted(a), .streamInterrupted(b)):
            return a == b
        default:
            return false
        }
    }
}
```

- [ ] **Step 3: Update `AppContainer.swift` callsite**

Edit `Dictonary/App/AppContainer.swift`. Change line 19 from:

```swift
self.translationService = TranslationService(settings: s)
```

to:

```swift
self.translationService = TranslationService()
```

- [ ] **Step 4: Update `TranslatorViewModelTests.swift` callsite**

Edit `DictonaryTests/TranslatorViewModelTests.swift`. Replace the `makeVM()` helper (lines 7–16) with:

```swift
    private func makeVM() -> TranslatorViewModel {
        let settings = Settings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
                                keychain: InMemoryKeychain())
        let svc = TranslationService()
        return TranslatorViewModel(
            service: svc,
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}"
        )
    }
```

(We keep `Settings(defaults:keychain:)` here for now — Task 7 will drop the `keychain:` arg once we slim `Settings`. The unused `settings` local stays so the diff is small; Task 7 will remove it.)

- [ ] **Step 5: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

(Note: `ProviderSettingsView.swift` still compiles — it uses `translationService.translate(...)` which doesn't depend on the changed init signature.)

- [ ] **Step 6: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass. Provider tests still pass because they construct providers directly. `SettingsTests` are unaffected. `TranslatorViewModelTests` constructs the service with no args.

- [ ] **Step 7: Commit**

```bash
git add Dictonary/Translation/TranslationService.swift Dictonary/Translation/TranslationError.swift Dictonary/App/AppContainer.swift DictonaryTests/TranslatorViewModelTests.swift
git commit -m "$(cat <<'EOF'
refactor(translation): switch TranslationService to ProviderConfig

Drops Settings dependency, drops TranslationError.missingAPIKey
(empty key now falls through to HTTP 401 on the natural path).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Delete `ProviderSettingsView`; remove Provider tab

Drops the entire Provider tab. `SettingsView` no longer needs `translationService`, so the parameter and `AppDelegate.showPreferences()` callsite get updated together.

**Files:**
- Delete: `Dictonary/Settings/UI/ProviderSettingsView.swift`
- Modify: `Dictonary/Settings/UI/SettingsView.swift` (remove Provider tab + `translationService` param)
- Modify: `Dictonary/App/AppDelegate.swift` (line 96: drop `translationService:` from `SettingsView(...)` call)
- Regen: `xcodegen generate`

- [ ] **Step 1: Delete `ProviderSettingsView.swift`**

```bash
git rm Dictonary/Settings/UI/ProviderSettingsView.swift
```

- [ ] **Step 2: Rewrite `SettingsView.swift`**

Replace the entire contents of `Dictonary/Settings/UI/SettingsView.swift` with:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var historyStore: HistoryStore
    let onHotkeyChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, onHotkeyChanged: onHotkeyChanged)
                .tabItem { Label("General", systemImage: "gear") }

            HistorySettingsView(settings: settings, historyStore: historyStore)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 440)
    }
}
```

(Frame size unchanged from before — three tabs render fine inside the existing window; touch this only if visually off.)

- [ ] **Step 3: Update `AppDelegate.showPreferences()` callsite**

Edit `Dictonary/App/AppDelegate.swift`. Replace the `SettingsView` initialization in `showPreferences()` (lines 93–98) with:

```swift
        let view = SettingsView(
            settings: container.settings,
            historyStore: container.historyStore,
            onHotkeyChanged: { [weak self] in self?.reregisterHotkey() }
        )
```

- [ ] **Step 4: Regenerate project**

Run: `xcodegen generate`
Expected: success.

- [ ] **Step 5: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(settings): drop Provider tab and ProviderSettingsView

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Delete `WelcomeView` and onboarding flow

First-launch Welcome window goes away. App always behaves like a "subsequent launch": non-login launches pop the translator immediately.

**Files:**
- Delete: `Dictonary/Onboarding/WelcomeView.swift`
- Modify: `Dictonary/App/AppDelegate.swift` (remove `welcomeWindow`, `apiKeyObserver`, `showWelcome`, `applicationDidBecomeActive`, `refreshAPIKeyIndicator`, `didOnboard` branch)
- Regen: `xcodegen generate`

- [ ] **Step 1: Delete `WelcomeView.swift`**

```bash
git rm Dictonary/Onboarding/WelcomeView.swift
rmdir Dictonary/Onboarding 2>/dev/null || true
```

(`rmdir` is best-effort; only removes the directory if it's empty after the file is gone.)

- [ ] **Step 2: Rewrite `AppDelegate.swift`**

Replace the entire contents of `Dictonary/App/AppDelegate.swift` with:

```swift
import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let container = AppContainer()
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status bar wiring
        container.statusBar.onOpen = { [weak self] in
            guard let self else { return }
            if self.container.translator.isVisible {
                self.container.translator.hardHide()
            } else {
                self.container.translator.show()
            }
        }
        container.statusBar.onPreferences = { [weak self] in self?.showPreferences() }
        container.statusBar.onQuit = { NSApp.terminate(nil) }

        // Hotkey wiring
        container.hotKeyManager.onPress = { [weak self] in self?.container.translator.toggle() }
        if !container.hotKeyManager.register(container.settings.hotkey) {
            // Best-effort fallback: don't block startup. User can fix in Preferences.
            NSLog("[Dictonary] Failed to register hotkey \(container.settings.hotkey.displayString)")
        }

        // Login item
        if container.settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        }

        // Pop the translator on launch unless this is a boot-time auto-start.
        if !isLikelyLoginLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.container.translator.show()
            }
        }
    }

    /// Heuristic: if launch-at-login is enabled AND the system booted within
    /// the last 90s, this launch is almost certainly the auto-start. Skip the
    /// auto-popup so we don't ambush the user during boot.
    private var isLikelyLoginLaunch: Bool {
        guard container.settings.launchAtLogin else { return false }
        return ProcessInfo.processInfo.systemUptime < 90
    }

    /// Re-register hotkey when user changes it in Preferences.
    func reregisterHotkey() {
        _ = container.hotKeyManager.register(container.settings.hotkey)
    }

    /// Manage the Preferences window ourselves rather than going through the
    /// SwiftUI `Settings` scene + `showSettingsWindow:` selector dispatch.
    /// That dispatch path is flaky for LSUIElement apps because the responder
    /// chain has no resolver until the app is active, and even then the action
    /// is sometimes silently dropped. A directly-managed NSWindow is reliable.
    func showPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = preferencesWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(
            settings: container.settings,
            historyStore: container.historyStore,
            onHotkeyChanged: { [weak self] in self?.reregisterHotkey() }
        )
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.title = "Preferences"
        win.isReleasedWhenClosed = false
        win.center()
        preferencesWindow = win
        win.makeKeyAndOrderFront(nil)
    }
}
```

(Removed: `welcomeWindow`, `apiKeyObserver`, `showWelcome()`, `applicationDidBecomeActive(...)`, `refreshAPIKeyIndicator()`, the `didOnboard` branch, the `dictonaryAPIKeyChanged` notification observer, and the `apiKey(for:)` reads. Kept: status-bar wiring, hotkey, login item, translator pop, preferences window.)

- [ ] **Step 3: Regenerate project**

Run: `xcodegen generate`

- [ ] **Step 4: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

(`Settings.didOnboard` is still defined; we're just no longer reading it. Task 7 deletes the field. `Settings.apiKey(...)`, `dictonaryAPIKeyChanged`, and `StatusBarController.needsAPIKey` are also still defined but no longer referenced from AppDelegate; they go away in Tasks 6/7.)

- [ ] **Step 5: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(app): drop Welcome onboarding and API-key indicator wiring

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Remove `needsAPIKey` from `StatusBarController`

Now that no caller toggles the red dot, drop the field and the rendering branch.

**Files:**
- Modify: `Dictonary/StatusBar/StatusBarController.swift`

- [ ] **Step 1: Edit `StatusBarController.swift`**

Apply two edits:

(a) Delete the `needsAPIKey` property (lines 12–14):

```swift
    var needsAPIKey: Bool = false {
        didSet { renderIcon() }
    }
```

(b) In `renderIcon()`, replace the `if needsAPIKey { ... } else { ... }` block (lines 28–38) with the unconditional "no badge" branch:

```swift
        button.attributedTitle = NSAttributedString()
        button.title = ""
```

The full `renderIcon()` after the change:

```swift
    private func renderIcon() {
        guard let button = item.button else { return }
        button.image = Self.makeTemplateIcon()
        button.imagePosition = .imageLeft
        button.contentTintColor = nil // let template image render with system tint
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.target = self
        button.action = #selector(handleClick)
        // NSStatusBarButton fires its action on left clicks only by default;
        // opt into right clicks so the context menu can show.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add Dictonary/StatusBar/StatusBarController.swift
git commit -m "$(cat <<'EOF'
feat(statusbar): drop needsAPIKey red-dot indicator

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Slim `Settings` to user preferences only

Drop everything provider-related from `Settings`: `provider`, `model`, `endpoint`, `didOnboard`, `apiKey(for:)`, `setAPIKey`, `deleteAPIKey`, `resolvedEndpoint(for:)`, `keychain` dependency, `Notification.Name.dictonaryAPIKeyChanged`. Update `SettingsTests` and `TranslatorViewModelTests` callers in the same task.

`KeychainService` and `InMemoryKeychain` are still around after this task — they become unreferenced. Task 8 removes them.

**Files:**
- Modify: `Dictonary/Settings/Settings.swift`
- Modify: `DictonaryTests/SettingsTests.swift`
- Modify: `DictonaryTests/TranslatorViewModelTests.swift`

- [ ] **Step 1: Rewrite `Settings.swift`**

Replace the entire contents of `Dictonary/Settings/Settings.swift` with:

```swift
import Foundation
import Combine

final class Settings: ObservableObject {

    // Keys for UserDefaults
    private enum Key {
        static let hotkey       = "hotkey"
        static let launchAtLogin = "launchAtLogin"
        static let historyLimit = "historyLimit"
    }

    private let defaults: UserDefaults

    @Published var hotkey: HotkeyCombo {
        didSet { try? saveHotkey(hotkey) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var historyLimit: Int {
        didSet {
            let clamped = max(0, min(500, historyLimit))
            if clamped != historyLimit {
                historyLimit = clamped
            } else {
                defaults.set(clamped, forKey: Key.historyLimit)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.hotkey),
           let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            self.hotkey = combo
        } else {
            self.hotkey = .defaultCombo
        }
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let raw = defaults.object(forKey: Key.historyLimit) as? Int
        self.historyLimit = max(0, min(500, raw ?? 50))
    }

    private func saveHotkey(_ combo: HotkeyCombo) throws {
        let data = try JSONEncoder().encode(combo)
        defaults.set(data, forKey: Key.hotkey)
    }
}
```

- [ ] **Step 2: Rewrite `SettingsTests.swift`**

Replace the entire contents of `DictonaryTests/SettingsTests.swift` with:

```swift
import XCTest
@testable import Dictonary

final class SettingsTests: XCTestCase {
    fileprivate func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsWhenEmpty() {
        let s = Settings(defaults: makeDefaults())
        XCTAssertEqual(s.hotkey, .defaultCombo)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(s.historyLimit, 50)
    }

    func testHotkeyChangePersists() throws {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults)
        let custom = HotkeyCombo(keyCode: 36, modifiers: 1 << 8)
        s.hotkey = custom
        let s2 = Settings(defaults: defaults)
        XCTAssertEqual(s2.hotkey, custom)
    }

    func testLaunchAtLoginPersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults)
        s.launchAtLogin = true
        let s2 = Settings(defaults: defaults)
        XCTAssertTrue(s2.launchAtLogin)
    }

    func testHistoryLimitPersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults)
        s.historyLimit = 25
        let s2 = Settings(defaults: defaults)
        XCTAssertEqual(s2.historyLimit, 25)
    }

    func testHistoryLimitClampsToZeroMin() {
        let s = Settings(defaults: makeDefaults())
        s.historyLimit = -5
        XCTAssertEqual(s.historyLimit, 0)
    }

    func testHistoryLimitClampsToMax() {
        let s = Settings(defaults: makeDefaults())
        s.historyLimit = 9999
        XCTAssertEqual(s.historyLimit, 500)
    }
}
```

- [ ] **Step 3: Update `TranslatorViewModelTests.swift`**

Edit `DictonaryTests/TranslatorViewModelTests.swift`. Replace `makeVM()` with the simplified version (no `Settings` / `InMemoryKeychain` references at all):

```swift
    private func makeVM() -> TranslatorViewModel {
        let svc = TranslationService()
        return TranslatorViewModel(
            service: svc,
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}"
        )
    }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

(After this step, `KeychainService.swift` and `Mocks/InMemoryKeychain.swift` are unreferenced but still in the build. That's fine — they'll be deleted in Task 8.)

- [ ] **Step 5: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass — including the rewritten `SettingsTests` and updated `TranslatorViewModelTests`.

- [ ] **Step 6: Commit**

```bash
git add Dictonary/Settings/Settings.swift DictonaryTests/SettingsTests.swift DictonaryTests/TranslatorViewModelTests.swift
git commit -m "$(cat <<'EOF'
refactor(settings): slim Settings to user preferences only

Removes provider/model/endpoint/didOnboard/keychain plumbing. Settings now
only stores hotkey, launchAtLogin, and historyLimit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Delete `KeychainService` and its tests

With no remaining callers, drop the Keychain code and tests entirely.

**Files:**
- Delete: `Dictonary/Settings/KeychainService.swift`
- Delete: `DictonaryTests/KeychainServiceTests.swift`
- Delete: `DictonaryTests/Mocks/InMemoryKeychain.swift`
- Regen: `xcodegen generate`

- [ ] **Step 1: Delete the files**

```bash
git rm Dictonary/Settings/KeychainService.swift DictonaryTests/KeychainServiceTests.swift DictonaryTests/Mocks/InMemoryKeychain.swift
rmdir DictonaryTests/Mocks 2>/dev/null || true
```

- [ ] **Step 2: Regenerate project**

Run: `xcodegen generate`

- [ ] **Step 3: Build**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Tests**

Run: `xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug test`
Expected: all pass. The previously-existing `KeychainServiceTests` is gone; everything else stays green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: remove KeychainService and its tests

Unused after Settings slim-down; key storage is now compile-time constants
in ProviderConfig.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: End-to-end smoke check

After all the deletions, sanity-check the running app. Pure manual verification — no code changes.

- [ ] **Step 1: Clean build & test**

```bash
xcodebuild -project Dictonary.xcodeproj -scheme Dictonary -configuration Debug clean build test
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Run the app and verify behavior**

Launch the app from Xcode (`⌘R`) and verify:

- [ ] No Welcome window on first launch (delete `~/Library/Containers/app.dictonary.Dictonary` first if you want a true first-launch state — note: app is unsandboxed per `project.yml`, so check `~/Library/Preferences/app.dictonary.Dictonary.plist` instead).
- [ ] Status-bar icon shows no red dot.
- [ ] Preferences window opens with three tabs only: General / History / About.
- [ ] Hotkey still toggles the translator window.
- [ ] Translation attempt with empty key fails with HTTP error (e.g., "API Key 无效或已过期" / `unauthorized` / `serverError`) — not "未配置 API Key".

If all checks pass, the refactor is complete. If any check fails, fix in a separate commit.

---

## Recap of Final State

After Task 8 + Task 9 verification:

- `Translation/` owns: `ProviderKind`, `ProviderConfig`, `TranslationService`, `TranslationError`, `TranslationProvider`, `{DeepSeek,OpenAI,Claude}Provider`, `SSEParser`
- `Settings/` owns: `HotkeyCombo`, `Settings` (3 fields), `UI/{General,History,About,SettingsView,HotkeyRecorderView}`
- `Onboarding/` directory removed
- No `KeychainService` anywhere
- No "Provider" tab, no Welcome window, no red-dot indicator
- Empty-key behavior: HTTP 401 surfaced via existing `TranslationError` paths
- Total commits: 8 (one per task; Task 9 is verification only)
