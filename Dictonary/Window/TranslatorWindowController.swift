import AppKit
import SwiftUI
import Combine

@MainActor
final class TranslatorWindowController {
    private let panel: TranslatorPanel
    private let vm: TranslatorViewModel
    private let host: NSHostingController<TranslatorContentView>
    private let historyStore: HistoryStore
    private var localMonitor: Any?
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

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        positionAtTopCenterOfMouseScreen()
        // Don't NSApp.activate — that steals focus from the previous app and
        // means hiding the panel can't return focus to it. The panel is a
        // .nonactivatingPanel and overrides canBecomeKey, so makeKeyAndOrderFront
        // alone gives it keyboard input without flipping the app to frontmost.
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func hide() {
        removeDismissMonitors()
        panel.orderOut(nil)
        // Belt-and-suspenders: if the app did become frontmost (e.g. user
        // clicked into the panel from another app), hand focus back so the
        // user lands in their previous window after dismissing.
        if NSApp.isActive {
            NSApp.hide(nil)
        }
        vm.reset()
    }

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

    // MARK: - Esc + click-outside dismissal

    private func installDismissMonitors() {
        removeDismissMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Esc = 53 → hide.
            if event.keyCode == 53 {
                self.hide()
                return nil
            }

            // Return = 36. Plain Return submits; Shift+Return falls through so
            // axis: .vertical TextField inserts a newline naturally.
            if event.keyCode == 36 {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let meaningful = mods.subtracting(.numericPad) // Enter key sets numericPad
                if meaningful.isEmpty {
                    self.vm.submit()
                    return nil
                }
            }

            return event
        }
    }

    private func removeDismissMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }
}
