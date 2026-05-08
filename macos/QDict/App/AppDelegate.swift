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
        container.translator.onShowPreferences = { [weak self] in self?.showPreferences() }

        // Hotkey wiring
        container.hotKeyManager.onPress = { [weak self] in self?.container.translator.toggle() }
        if !container.hotKeyManager.register(container.settings.hotkey) {
            // Best-effort fallback: don't block startup. User can fix in Preferences.
            NSLog("[QDict] Failed to register hotkey \(container.settings.hotkey.displayString)")
        }

        // Login item
        if container.settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        }

        // SwiftUI's `Settings` scene auto-installs a "Settings…"/"Preferences…"
        // menu item with Cmd+, that opens the empty stub window. Hijack it so
        // Cmd+, opens our real Preferences instead. Done after a runloop hop
        // because SwiftUI installs the menu during launch.
        DispatchQueue.main.async { [weak self] in
            self?.rewireDefaultPreferencesMenuItem()
        }

        // Pop the translator on launch unless this is a boot-time auto-start.
        if !isLikelyLoginLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.container.translator.show()
            }
        }
    }

    /// Find the auto-installed Cmd+, menu item (created by the SwiftUI
    /// `Settings` scene) and rewire its target/action to our own handler so
    /// it doesn't open the empty stub window.
    private func rewireDefaultPreferencesMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for topItem in mainMenu.items {
            guard let submenu = topItem.submenu else { continue }
            for item in submenu.items
            where item.keyEquivalent == ","
                && item.keyEquivalentModifierMask == .command {
                item.target = self
                item.action = #selector(menuShowPreferences(_:))
            }
        }
    }

    @objc private func menuShowPreferences(_ sender: Any?) {
        showPreferences()
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
