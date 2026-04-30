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
    private var stateSubscription: AnyCancellable?
    private var inputSubscription: AnyCancellable?

    init(service: TranslationService, dictTemplate: String, translTemplate: String, historyStore: HistoryStore) {
        self.historyStore = historyStore
        self.vm = TranslatorViewModel(
            service: service,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate,
            historyStore: historyStore
        )
        self.panel = TranslatorPanel()
        // We previously tried NSHostingController + preferredContentSize, but that
        // only auto-resizes for the first few layout passes during streaming and
        // then stops propagating updates. Instead, the SwiftUI view measures its
        // own size via a GeometryReader preference and calls back here, and we
        // explicitly resize the panel to match.
        let view = TranslatorContentView(vm: vm)
        self.host = NSHostingController(rootView: view)
        panel.contentViewController = host

        // NSHostingController only auto-propagates preferredContentSize for the
        // first few layout passes; it stops driving panel resize during a long
        // streamed update. So we drive it explicitly: every time state or input
        // changes, recompute the SwiftUI fitting size and apply it.
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
    }

    var isVisible: Bool { panel.isVisible }

    private var pendingSnapshot: SessionSnapshot?

    // MARK: - Show / hide

    func toggle() {
        if panel.isVisible {
            bringToFront()
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

            if event.keyCode == 53 { // Esc
                self.hardHide()
                return nil
            }

            // Return = 36. Plain Return submits; Shift+Return falls through.
            if event.keyCode == 36 {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let meaningful = mods.subtracting(.numericPad)
                if meaningful.isEmpty {
                    self.vm.submit()
                    return nil
                }
            }

            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // Any mouse-down outside our process means user is interacting with another app
            // — soft-dismiss so the panel doesn't sit on top of their work.
            self?.softHide()
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.softHide()
        }
    }

    private func removeDismissMonitors() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let o = resignActiveObserver {
            NotificationCenter.default.removeObserver(o)
            resignActiveObserver = nil
        }
    }
}
