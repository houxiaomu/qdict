import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let container = AppContainer()
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status bar wiring
        container.statusBar.onOpen = { [weak self] in self?.container.translator.toggle() }
        container.statusBar.onPreferences = { Self.openPreferences() }
        container.statusBar.onQuit = { NSApp.terminate(nil) }
        container.statusBar.needsAPIKey = (container.settings.apiKey(for: container.settings.provider) ?? "").isEmpty

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

        // First-launch
        if !container.settings.didOnboard {
            showWelcome()
        }

        // React to API-key changes for the red-dot indicator.
        // Simple poll-on-change via NotificationCenter would require more wiring;
        // for v1 we refresh on every translator open.
        // (See `applicationDidBecomeActive` below.)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        let key = container.settings.apiKey(for: container.settings.provider) ?? ""
        container.statusBar.needsAPIKey = key.isEmpty
    }

    /// Re-register hotkey when user changes it in Preferences.
    func reregisterHotkey() {
        _ = container.hotKeyManager.register(container.settings.hotkey)
    }

    static func openPreferences() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWelcome() {
        let welcome = WelcomeView(
            openPreferences: { [weak self] in
                Self.openPreferences()
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
