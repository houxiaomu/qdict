import AppKit
import SwiftUI

@MainActor
final class TranslatorWindowController {
    private let panel: TranslatorPanel
    private let vm: TranslatorViewModel
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(service: TranslationService, dictTemplate: String, translTemplate: String) {
        self.vm = TranslatorViewModel(
            service: service,
            dictTemplate: dictTemplate,
            translTemplate: translTemplate
        )
        self.panel = TranslatorPanel()
        // NSHostingController + contentViewController is what makes the panel
        // actually resize when SwiftUI content changes (streaming output grows,
        // multi-line input expands). NSHostingView alone with sizingOptions just
        // reports the intrinsic size, it does NOT trigger panel resize.
        let host = NSHostingController(rootView: TranslatorContentView(vm: vm))
        panel.contentViewController = host
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        positionAtTopCenterOfMouseScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func hide() {
        removeDismissMonitors()
        panel.orderOut(nil)
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
        // Click-outside dismissal: only when the panel is "empty" (no input,
        // no in-flight request, no result). Once the user has typed or sees a
        // result, leave the panel up so they can copy text or click around.
        // Esc and the global hotkey still close it explicitly.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.vm.input.isEmpty && self.vm.state == .idle {
                self.hide()
            }
        }
    }

    private func removeDismissMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}
