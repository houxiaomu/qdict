# Rename Dictonary to QDict — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the macOS app end-to-end from `Dictonary` to `QDict` — folders, target, scheme, bundle identifiers, types, UI strings, and runtime data path. No user-data migration.

**Architecture:** Pure rename. Folder moves use `git mv` to preserve blame. The Xcode project is regenerated from `project.yml` via `xcodegen` rather than hand-edited. The intermediate state between folder rename and `xcodegen generate` does not build, so all changes ship in one logical commit at the end.

**Tech Stack:** Swift / SwiftUI / AppKit, `xcodegen`, `xcodebuild`, git.

**Spec:** `docs/superpowers/specs/2026-05-01-rename-app-to-qdict-design.md`

---

## Pre-flight

- [ ] **Step 1: Confirm clean working tree on `main`**

Run:
```bash
git status
```
Expected: working tree clean (or only the untracked plan you're about to follow). If dirty, stash or commit first — this plan does a single all-or-nothing commit and rebasing on a dirty tree is messy.

- [ ] **Step 2: Confirm tools available**

Run:
```bash
which xcodegen && xcodegen --version
xcodebuild -version
```
Expected: both print versions. Install `xcodegen` via `brew install xcodegen` if missing.

- [ ] **Step 3: Baseline: tests pass before any change**

Run:
```bash
xcodebuild -scheme Dictonary -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **`. If this fails, stop — the rename is not the cause of any pre-existing breakage and we want a clean baseline.

---

## Task 1: Rename source folders and individual files

**Files:**
- Move: `Dictonary/` → `QDict/`
- Move: `DictonaryTests/` → `QDictTests/`
- Move: `QDict/Resources/Dictonary.entitlements` → `QDict/Resources/QDict.entitlements`
- Move: `QDict/App/DictonaryApp.swift` → `QDict/App/QDictApp.swift`

- [ ] **Step 1: Move the two top-level source folders**

Run:
```bash
git mv Dictonary QDict
git mv DictonaryTests QDictTests
```
Expected: no output, exit 0. `git status` now shows two folder renames staged.

- [ ] **Step 2: Rename the entitlements file**

Run:
```bash
git mv QDict/Resources/Dictonary.entitlements QDict/Resources/QDict.entitlements
```
Expected: no output, exit 0.

- [ ] **Step 3: Rename the App entry-point Swift file**

Run:
```bash
git mv QDict/App/DictonaryApp.swift QDict/App/QDictApp.swift
```
Expected: no output, exit 0.

- [ ] **Step 4: Verify renames are staged**

Run:
```bash
git status
```
Expected: four `renamed:` lines covering the two folders, the entitlements file, and the app file. No new task; we're not committing yet.

---

## Task 2: Rename the Swift type and update string literals

**Files:**
- Modify: `QDict/App/QDictApp.swift`
- Modify: `QDict/App/AppDelegate.swift`
- Modify: `QDict/StatusBar/StatusBarController.swift`
- Modify: `QDict/Settings/UI/SettingsView.swift`
- Modify: `QDict/History/HistoryStore.swift`
- Modify: `scripts/generate-icon.swift`

- [ ] **Step 1: Rename the `DictonaryApp` type**

Edit `QDict/App/QDictApp.swift` line 4. Replace:
```swift
struct DictonaryApp: App {
```
with:
```swift
struct QDictApp: App {
```
Leave the rest of the file unchanged.

- [ ] **Step 2: Update the AppDelegate log prefix**

Edit `QDict/App/AppDelegate.swift` line 28. Replace:
```swift
NSLog("[Dictonary] Failed to register hotkey \(container.settings.hotkey.displayString)")
```
with:
```swift
NSLog("[QDict] Failed to register hotkey \(container.settings.hotkey.displayString)")
```

- [ ] **Step 3: Update StatusBarController accessibility label**

Edit `QDict/StatusBar/StatusBarController.swift` line 52. Replace:
```swift
return NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: "Dictonary") ?? NSImage()
```
with:
```swift
return NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: "QDict") ?? NSImage()
```

- [ ] **Step 4: Update StatusBarController quit menu title**

Edit `QDict/StatusBar/StatusBarController.swift` line 104. Replace:
```swift
menu.addItem(NSMenuItem(title: "Quit Dictonary", action: #selector(handleQuit), keyEquivalent: "q"))
```
with:
```swift
menu.addItem(NSMenuItem(title: "Quit QDict", action: #selector(handleQuit), keyEquivalent: "q"))
```

- [ ] **Step 5: Update SettingsView about label**

Edit `QDict/Settings/UI/SettingsView.swift` line 45. Replace:
```swift
Text("Dictonary")
```
with:
```swift
Text("QDict")
```

- [ ] **Step 6: Update HistoryStore Application-Support path**

Edit `QDict/History/HistoryStore.swift` line 32. Replace:
```swift
).appendingPathComponent("Dictonary", isDirectory: true)
```
with:
```swift
).appendingPathComponent("QDict", isDirectory: true)
```

- [ ] **Step 7: Update `scripts/generate-icon.swift` references**

Edit `scripts/generate-icon.swift`:
- Line 3: replace `// Generate Dictonary's AppIcon set.` with `// Generate QDict's AppIcon set.`
- Line 8: replace `// Dictonary/Resources/Assets.xcassets/AppIcon.appiconset/.` with `// QDict/Resources/Assets.xcassets/AppIcon.appiconset/.`
- Line 178: replace `.appendingPathComponent("Dictonary")` with `.appendingPathComponent("QDict")`

- [ ] **Step 8: Verify no `Dictonary` references remain in source**

Run:
```bash
grep -rn 'Dictonary' QDict QDictTests scripts 2>/dev/null
```
Expected: no output. If any line prints, fix it before continuing.

---

## Task 3: Update Info.plist

**Files:**
- Modify: `QDict/Resources/Info.plist`

- [ ] **Step 1: Update CFBundleDisplayName**

Edit `QDict/Resources/Info.plist` line 8. Replace:
```xml
	<string>Dictonary</string>
```
with:
```xml
	<string>QDict</string>
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -n 'Dictonary' QDict/Resources/Info.plist
```
Expected: no output.

---

## Task 4: Rewrite project.yml

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Replace `project.yml` with the renamed version**

Overwrite the file with this exact content:

```yaml
name: QDict
options:
  bundleIdPrefix: app.qdict
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
  developmentLanguage: en
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "1.0.1"
    CURRENT_PROJECT_VERSION: "2"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
targets:
  QDict:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: QDict
    resources:
      - path: QDict/Prompt/Prompts
      - path: QDict/Resources/Assets.xcassets
    info:
      path: QDict/Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: QDict
        NSHumanReadableCopyright: "© 2026"
    entitlements:
      path: QDict/Resources/QDict.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.network.client: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.qdict.QDict
        CODE_SIGN_STYLE: Manual
        DEVELOPMENT_TEAM: ""
        ENABLE_HARDENED_RUNTIME: YES
        COMBINE_HIDPI_IMAGES: YES
      configs:
        Debug:
          # Use a stable signing identity for Debug too. Ad-hoc ("-") changes
          # the signature on every build, which invalidates the Keychain ACL
          # for the saved API key and re-prompts for the login password.
          CODE_SIGN_IDENTITY: "simonkey dev"
          CODE_SIGNING_REQUIRED: YES
          # Hardened runtime blocks Xcode's incremental-link debug dylib from
          # loading because that dylib is ad-hoc signed by Xcode. Disable for
          # Debug so the app can launch; Release keeps it on.
          ENABLE_HARDENED_RUNTIME: NO
        Release:
          CODE_SIGN_IDENTITY: "simonkey dev"
          CODE_SIGNING_REQUIRED: YES
  QDictTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: QDictTests
    dependencies:
      - target: QDict
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.qdict.QDictTests
        CODE_SIGN_STYLE: Manual
        # Match the host app's signing identity so the test bundle dylib can
        # load into the QDict process. Ad-hoc here would mismatch the
        # simonkey-dev-signed host and fail at load time.
        CODE_SIGN_IDENTITY: "simonkey dev"
        CODE_SIGNING_REQUIRED: YES
        ENABLE_HARDENED_RUNTIME: NO
        DEVELOPMENT_TEAM: ""
        GENERATE_INFOPLIST_FILE: YES
schemes:
  QDict:
    build:
      targets:
        QDict: all
        QDictTests: [test]
    test:
      targets:
        - QDictTests
```

- [ ] **Step 2: Verify no stale references**

Run:
```bash
grep -n 'Dictonary\|dictonary' project.yml
```
Expected: no output.

---

## Task 5: Regenerate the Xcode project

**Files:**
- Delete: `Dictonary.xcodeproj/`
- Create: `QDict.xcodeproj/`

- [ ] **Step 1: Remove the old `.xcodeproj`**

Run:
```bash
git rm -r Dictonary.xcodeproj
```
Expected: deletion staged.

- [ ] **Step 2: Generate the new `.xcodeproj`**

Run:
```bash
xcodegen generate
```
Expected: `Loaded project … Created project at …/QDict.xcodeproj`.

- [ ] **Step 3: Stage the new project**

Run:
```bash
git add QDict.xcodeproj
```

- [ ] **Step 4: Confirm everything is staged**

Run:
```bash
git status
```
Expected: shows the renamed folders, the renamed entitlements & app file, the file edits, the deleted `Dictonary.xcodeproj`, and the new `QDict.xcodeproj`. No untracked source files outside `build/`.

---

## Task 6: Build, test, and commit

- [ ] **Step 1: Clean build to flush any cached references to the old target**

Run:
```bash
xcodebuild -scheme QDict -destination 'platform=macOS' clean build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. If it fails, read the error — most likely a missed string in Task 2 or a path typo in Task 4.

- [ ] **Step 2: Run the test suite**

Run:
```bash
xcodebuild -scheme QDict -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Verify zero `Dictonary` references in tracked source**

Run:
```bash
grep -rn 'Dictonary' --exclude-dir=docs --exclude-dir=.git --exclude-dir=build --exclude-dir='*.xcodeproj' .
```
Expected: no output. (Anything inside `docs/`, `.git/`, `build/`, or any `.xcodeproj/` is acceptable — `docs/` is intentionally preserved per spec; the others are not tracked or are regenerated.)

If `QDict.xcodeproj/` itself contains "Dictonary" — that's a real bug. Investigate.

- [ ] **Step 4: Smoke-launch the app and eyeball the UI**

Run:
```bash
xcodebuild -scheme QDict -destination 'platform=macOS' -derivedDataPath build/dd build 2>&1 | tail -5
open build/dd/Build/Products/Debug/QDict.app
```
Expected: app launches as a menu-bar icon. Verify:
- Click the menu-bar icon → quit menu reads **Quit QDict**
- About panel (Cmd+, → about row, or wherever it surfaces) shows **QDict**
- Trigger one translation and confirm `~/Library/Application Support/QDict/` is created (`ls ~/Library/Application\ Support/ | grep QDict`)

If anything still says "Dictonary" in the UI, fix and rerun the test step.

- [ ] **Step 5: Commit**

Run:
```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: rename app from Dictonary to QDict

Folders, target, scheme, bundle identifiers, Swift type names, UI strings,
and the Application Support data directory all migrate from Dictonary to
QDict. No user-data migration: existing UserDefaults under the old bundle
ID and the old Application Support folder are not carried over (per
2026-05-01-rename-app-to-qdict-design.md).
EOF
)"
```
Expected: a single commit. Bundle of renames + edits + xcodeproj regeneration.

- [ ] **Step 6: Final sanity**

Run:
```bash
git log --oneline -3
git status
```
Expected: working tree clean, latest commit is the rename. Done.

---

## Rollback

If Task 6 build/test fails and the cause is unclear, abandon and start over rather than patching:

```bash
git reset --hard HEAD
git clean -fd
```

This restores the pre-rename state. Re-attempt the plan top-down. Do not partially commit a half-renamed tree.
