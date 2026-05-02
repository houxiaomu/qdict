import AppKit
import SwiftUI
import Combine

@MainActor
final class TranslatorWindowController {
    private let panel: TranslatorPanel
    private let vm: TranslatorViewModel
    private let host: NSHostingController<TranslatorContentView>
    private let historyStore: HistoryStore
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var workspaceActivateObserver: NSObjectProtocol?
    private var stateSubscription: AnyCancellable?
    private var inputSubscription: AnyCancellable?
    private var drawerSubscription: AnyCancellable?
    private var historySubscription: AnyCancellable?

    /// Called when the user presses Cmd+, while the panel is key. Lets the app
    /// delegate open Preferences without relying on the (absent) main menu.
    var onShowPreferences: (() -> Void)?

    init(service: TranslationService, dictTemplate: String, translTemplate: String, historyStore: HistoryStore) {
        self.historyStore = historyStore
        self.vm = TranslatorViewModel(
            service: service,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate,
            historyStore: historyStore
        )
        self.panel = TranslatorPanel()
        // The gear callback needs to capture self, but we cannot reference self
        // inside the same expression that initializes our `host` stored property.
        // Construct the hosting controller first with a no-op callback, then
        // replace its rootView with the real callback once self is fully bound.
        let placeholderView = TranslatorContentView(
            vm: vm,
            historyStore: historyStore,
            onShowPreferences: {}
        )
        self.host = NSHostingController(rootView: placeholderView)
        panel.contentViewController = host
        host.rootView = TranslatorContentView(
            vm: vm,
            historyStore: historyStore,
            onShowPreferences: { [weak self] in
                self?.showPreferencesAndSoftHide()
            }
        )

        // We previously tried NSHostingController + preferredContentSize, but that
        // only auto-resizes for the first few layout passes during streaming and
        // then stops propagating updates. Instead, every time state or input
        // changes, recompute the SwiftUI fitting size and apply it explicitly.
        let resize: () -> Void = { [weak self] in
            guard let self else { return }
            let fitting = self.host.view.fittingSize
            guard fitting.width > 0, fitting.height > 0 else { return }
            self.panel.setContentSize(fitting)
        }
        stateSubscription = vm.$state
            .receive(on: RunLoop.main)
            .sink { _ in resize() }
        inputSubscription = vm.$input
            .receive(on: RunLoop.main)
            .sink { _ in resize() }
        drawerSubscription = vm.$isDrawerOpen
            .receive(on: RunLoop.main)
            .sink { _ in resize() }
        historySubscription = historyStore.$entries
            .receive(on: RunLoop.main)
            .sink { _ in resize() }
    }

    var isVisible: Bool { panel.isVisible }

    private var pendingSnapshot: SessionSnapshot?

    // MARK: - Show / hide

    func toggle() {
        if panel.isVisible {
            softHide()
        } else {
            show()
        }
    }

    func show() {
        if let snap = pendingSnapshot, snap.isFresh() {
            vm.restore(snap)
        } else {
            // Stale or absent → start clean.
            vm.reset()
        }
        pendingSnapshot = nil

        positionAtTopCenterOfMouseScreen()
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    /// Bring the already-visible panel to front and refocus its input.
    func bringToFront() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// Explicit dismiss (Esc / status-bar-while-visible). Clears the session.
    func hardHide() {
        pendingSnapshot = nil
        removeDismissMonitors()
        panel.orderOut(nil)
        if NSApp.isActive {
            NSApp.hide(nil)
        }
        vm.reset()
    }

    /// Soft dismiss (click-outside / app deactivation). Preserve session for 5 minutes.
    func softHide() {
        guard panel.isVisible else { return }
        pendingSnapshot = vm.snapshot()
        removeDismissMonitors()
        panel.orderOut(nil)
        if NSApp.isActive {
            NSApp.hide(nil)
        }
        // Note: vm state is intentionally NOT reset.
    }

    /// Backwards-compat alias used during the refactor — callers should migrate.
    @available(*, deprecated, renamed: "hardHide")
    func hide() { hardHide() }

    // MARK: - Position

    private func positionAtTopCenterOfMouseScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main!
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = visibleFrame.midX - panelSize.width / 2
        let y = visibleFrame.maxY - panelSize.height - (visibleFrame.height * 0.18)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Esc + outside click + app deactivation dismissal

    private func installDismissMonitors() {
        removeDismissMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)

            // Esc = 53. Drawer-open: close drawer; otherwise: hard hide.
            if event.keyCode == 53 {
                if self.vm.isDrawerOpen {
                    self.vm.closeDrawer()
                } else {
                    self.hardHide()
                }
                return nil
            }

            // Return = 36. In drawer: confirm. Otherwise: submit.
            if event.keyCode == 36 {
                if mods.isEmpty {
                    if self.vm.isDrawerOpen {
                        self.vm.confirmSelection(history: self.historyStore)
                    } else {
                        self.vm.submit()
                    }
                    return nil
                }
            }

            // Cmd+Y = 16. Toggle drawer.
            if event.keyCode == 16 && mods == .command {
                self.vm.toggleDrawer(history: self.historyStore)
                return nil
            }

            // Cmd+, = 43. Same path as the gear button in the header.
            if event.keyCode == 43 && mods == .command {
                self.showPreferencesAndSoftHide()
                return nil
            }

            // Cmd+↑ = 126, Cmd+↓ = 125.
            if mods == .command && (event.keyCode == 126 || event.keyCode == 125) {
                let delta = (event.keyCode == 126) ? -1 : 1
                self.vm.moveSelection(in: self.historyStore, by: delta)
                return nil
            }

            // ↑ / ↓ inside drawer (no modifiers).
            if self.vm.isDrawerOpen && mods.isEmpty && (event.keyCode == 126 || event.keyCode == 125) {
                let delta = (event.keyCode == 126) ? -1 : 1
                self.vm.moveSelection(in: self.historyStore, by: delta)
                return nil
            }

            // Backspace / Delete = 51 / 117 inside drawer.
            if self.vm.isDrawerOpen && (event.keyCode == 51 || event.keyCode == 117) {
                self.vm.deleteSelection(history: self.historyStore)
                return nil
            }

            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // Any mouse-down outside our process means user is interacting with another app
            // — soft-dismiss so the panel doesn't sit on top of their work. Hop to the main
            // actor since softHide is MainActor-isolated.
            Task { @MainActor [weak self] in self?.softHide() }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.softHide() }
        }

        // didResignActive only fires if our app was active — but with
        // .nonactivatingPanel + LSUIElement, the panel often shows without
        // activating us, so Cmd+Tab to another app produces no resign event.
        // Observe the workspace-level activation instead: when ANY other app
        // becomes frontmost, soft-hide.
        workspaceActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor [weak self] in self?.softHide() }
        }
    }

    /// Soft-hide the panel and notify the host (AppDelegate) to open
    /// Preferences. Shared by the Cmd+, key handler and the gear button
    /// in the header.
    func showPreferencesAndSoftHide() {
        let openPrefs = onShowPreferences
        softHide()
        openPrefs?()
    }

    private func removeDismissMonitors() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let o = resignActiveObserver {
            NotificationCenter.default.removeObserver(o)
            resignActiveObserver = nil
        }
        if let o = workspaceActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            workspaceActivateObserver = nil
        }
    }
}
