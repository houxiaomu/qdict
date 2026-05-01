# Rename App from Dictonary to QDict

Date: 2026-05-01

## Goal

Rename the application end-to-end from `Dictonary` to `QDict`. After this change, no live source, build artifact, or runtime path should reference the misspelled `Dictonary`. Historical documents under `docs/` and git history are preserved as-is.

## Scope

Full rename across:

- Source folders, Xcode project, target, and scheme names
- Bundle identifiers and prefix
- `CFBundleDisplayName`
- Entitlements file name
- Swift type names that embed the app name
- UI strings and log prefixes referencing the old name
- Runtime data folder under `Application Support`
- Helper scripts that reference the old name

Out of scope: migrating any existing user data (`UserDefaults` under the old bundle ID, JSON files under `~/Library/Application Support/Dictonary/`). The new app starts with a clean state.

## Naming Map

| Old | New |
|---|---|
| Folder `Dictonary/` | `QDict/` |
| Folder `DictonaryTests/` | `QDictTests/` |
| Xcode project `Dictonary.xcodeproj` | `QDict.xcodeproj` |
| Target / scheme `Dictonary` | `QDict` |
| Test target `DictonaryTests` | `QDictTests` |
| Bundle ID prefix `app.dictonary` | `app.qdict` |
| App bundle ID `app.dictonary.Dictonary` | `app.qdict.QDict` |
| Test bundle ID `app.dictonary.DictonaryTests` | `app.qdict.QDictTests` |
| `CFBundleDisplayName: Dictonary` | `QDict` |
| Entitlements file `Dictonary/Resources/Dictonary.entitlements` | `QDict/Resources/QDict.entitlements` |
| Swift type `DictonaryApp` (in `App/DictonaryApp.swift`) | `QDictApp` (in `App/QDictApp.swift`) |
| `~/Library/Application Support/Dictonary/` | `~/Library/Application Support/QDict/` |
| Log prefix `[Dictonary]` in `AppDelegate` | `[QDict]` |
| Status bar accessibility label `"Dictonary"` | `"QDict"` |
| Menu item `"Quit Dictonary"` | `"Quit QDict"` |
| About panel `Text("Dictonary")` | `Text("QDict")` |
| `scripts/generate-icon.swift` comments and `appendingPathComponent("Dictonary")` | `QDict` |

Specific code locations that must change (verified via grep):

- `Dictonary/App/DictonaryApp.swift:4` — `struct DictonaryApp: App`
- `Dictonary/App/AppDelegate.swift:28` — `NSLog("[Dictonary] …")`
- `Dictonary/StatusBar/StatusBarController.swift:52,104` — accessibility label and quit menu title
- `Dictonary/Settings/UI/SettingsView.swift:45` — about-panel `Text("Dictonary")`
- `Dictonary/Resources/Info.plist:8` — `CFBundleDisplayName`
- `Dictonary/History/HistoryStore.swift:32` — `appendingPathComponent("Dictonary", …)`
- `scripts/generate-icon.swift:3,8,178` — header comments and asset path

## Execution Approach

1. Use `git mv` for folder renames (`Dictonary/` → `QDict/`, `DictonaryTests/` → `QDictTests/`) so blame and history are preserved per file.
2. Rename `Dictonary/Resources/Dictonary.entitlements` to `QDict/Resources/QDict.entitlements`.
3. Rename `Dictonary/App/DictonaryApp.swift` to `QDict/App/QDictApp.swift` and update the type name inside.
4. Update `project.yml` in place: `name`, `bundleIdPrefix`, target keys (`Dictonary` → `QDict`, `DictonaryTests` → `QDictTests`), all `path:` fields, `info.path`, `entitlements.path`, `PRODUCT_BUNDLE_IDENTIFIER` for both targets, scheme name and target references, `CFBundleDisplayName`. Do not change signing identity or any other settings.
5. Regenerate the Xcode project: `xcodegen generate`. The old `Dictonary.xcodeproj` directory is replaced by `QDict.xcodeproj`. Do not hand-edit `project.pbxproj`.
6. Update remaining string literals enumerated in the naming map.
7. Verify with `grep -rn 'Dictonary' .` excluding `docs/` and `.git/` — should be empty.

## Out of Scope

- `docs/superpowers/specs/` and `docs/superpowers/plans/` are historical artifacts that describe past work; they keep the old name.
- Git history (`git log`, commit messages) is not rewritten.
- No migration of `UserDefaults` from the old bundle ID.
- No migration or cleanup of `~/Library/Application Support/Dictonary/`. The user will deal with their local copy manually.
- App icon assets (`AppIcon.appiconset`) keep their internal asset-catalog identifier; only the script comments referencing the old name are updated.

## Verification

After execution:

1. `xcodegen generate` succeeds and produces `QDict.xcodeproj`.
2. `xcodebuild -scheme QDict build` succeeds.
3. `xcodebuild -scheme QDict test` passes all unit tests.
4. Launching the app:
   - Menu-bar icon's accessibility label reads `QDict`.
   - Status-bar menu shows `Quit QDict`.
   - About panel displays `QDict`.
   - A new directory `~/Library/Application Support/QDict/` is created on first history write.
5. `grep -rn 'Dictonary' .` excluding `docs/` and `.git/` returns no matches.

## Risks

- The user's existing local preferences and history are written under the old bundle ID and old Application Support path. After this rename they will appear to "disappear" from the new app. This is the chosen behavior (option A: clean start, no migration).
- `xcodegen` regeneration changes every internal UUID inside the `.pbxproj`. The diff will be large and effectively a full replacement of the project file. This is expected.
- Code signing identity `simonkey dev` is unchanged and continues to apply to the renamed targets.

## Non-goals

- No refactoring, restructuring, or feature changes ride along with the rename.
- No introduction of automated rename tooling beyond `git mv` and direct edits.
