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
        let host = NSHostingView(rootView: TranslatorContentView(vm: vm))
        panel.contentView = host
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
            // Esc = 53
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeDismissMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}
