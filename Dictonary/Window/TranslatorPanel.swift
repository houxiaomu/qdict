import AppKit

final class TranslatorPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.level = .floating
        // We previously set hidesOnDeactivate = true so the panel disappeared when
        // the app lost focus. That made the window vanish on any outside click and,
        // combined with status-bar reactivation quirks, sometimes left it
        // unreachable. Keep it visible until the user explicitly dismisses (Esc,
        // hotkey, or status-bar toggle).
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Resize while keeping the TOP edge anchored. NSPanel's default behaviour
    /// keeps the bottom-left origin fixed, so a growing content area extends
    /// the top upward — which sends the panel off the screen for tall results.
    /// We compensate by shifting the origin down by the height delta.
    override func setContentSize(_ size: NSSize) {
        let oldFrame = self.frame
        super.setContentSize(size)
        let newFrame = self.frame
        guard newFrame.size.height != oldFrame.size.height else { return }
        let oldTop = oldFrame.origin.y + oldFrame.size.height
        let newOriginY = oldTop - newFrame.size.height
        self.setFrameOrigin(NSPoint(x: newFrame.origin.x, y: newOriginY))
    }
}
