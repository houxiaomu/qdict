import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let container = AppContainer()
    private var welcomeWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var apiKeyObserver: NSObjectProtocol?

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
        refreshAPIKeyIndicator()

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

        // First-launch shows Welcome; subsequent launches pop the translator
        // immediately, on the assumption the user just clicked the app to use it.
        // Boot-time launch-at-login is suppressed via a system-uptime heuristic
        // so the window doesn't ambush the user during login.
        if !container.settings.didOnboard {
            showWelcome()
        } else if !isLikelyLoginLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.container.translator.show()
            }
        }

        // Refresh the red-dot indicator immediately when the user adds/changes an API key.
        apiKeyObserver = NotificationCenter.default.addObserver(
            forName: .dictonaryAPIKeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAPIKeyIndicator() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAPIKeyIndicator()
    }

    private func refreshAPIKeyIndicator() {
        let key = container.settings.apiKey(for: container.settings.provider) ?? ""
        container.statusBar.needsAPIKey = key.isEmpty
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
            translationService: container.translationService,
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

    private func showWelcome() {
        let welcome = WelcomeView(
            openPreferences: { [weak self] in
                self?.showPreferences()
                self?.container.settings.didOnboard = true
                self?.welcomeWindow?.close()
            },
            skip: { [weak self] in
                self?.container.settings.didOnboard = true
                self?.welcomeWindow?.close()
            }
        )
        let host = NSHostingController(rootView: welcome)
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable]
        win.title = "Welcome"
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = win
    }
}
