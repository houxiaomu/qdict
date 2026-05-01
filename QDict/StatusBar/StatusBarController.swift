import AppKit

@MainActor
final class StatusBarController {
    private let item: NSStatusItem
    private var menu: NSMenu

    var onOpen: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        renderIcon()
        configureMenu()
    }

    private func renderIcon() {
        guard let button = item.button else { return }
        button.image = Self.makeTemplateIcon()
        button.imagePosition = .imageLeft
        button.contentTintColor = nil // let template image render with system tint
        button.attributedTitle = NSAttributedString()
        button.title = ""
        button.target = self
        button.action = #selector(handleClick)
        // NSStatusBarButton fires its action on left clicks only by default;
        // opt into right clicks so the context menu can show.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Book-with-"D" template icon. Template images are auto-tinted by the
    /// menu bar: white on dark, black on light. Only the alpha channel matters,
    /// so we draw a filled book glyph then punch a "D"-shaped hole through it.
    private static func makeTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let scale: CGFloat = 2 // retina

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: "QDict") ?? NSImage()
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        // Do NOT scaleBy(scale) — the rep already maps point coordinates to its
        // pixel backing via rep.size, so an extra scale would double everything.

        // Filled book body from SF Symbols.
        if let book = NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let configured = book.withSymbolConfiguration(cfg) ?? book
            let bs = configured.size
            configured.draw(
                at: NSPoint(x: (size.width - bs.width) / 2, y: (size.height - bs.height) / 2),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }

        // Punch out the letter "D" so the menu bar shows through it.
        ctx?.compositingOperation = .destinationOut
        let str = NSAttributedString(string: "D", attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .heavy),
            .foregroundColor: NSColor.black
        ])
        let ts = str.size()
        // Shift right of geometric center: book.closed.fill has a spine on
        // the left, so a centered glyph crowds it. Push past the spine.
        str.draw(at: NSPoint(
            x: (size.width - ts.width) / 2 + 1.5,
            y: (size.height - ts.height) / 2 + 1
        ))

        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        img.isTemplate = true
        return img
    }

    private func configureMenu() {
        menu.addItem(NSMenuItem(title: "打开", action: #selector(handleOpenMenu), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(handlePreferences), keyEquivalent: ","))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit QDict", action: #selector(handleQuit), keyEquivalent: "q"))
        menu.items.last?.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        // Don't guard on NSApp.currentEvent — when LSUIElement apps are inactive,
        // it can be nil and we'd swallow the click silently. Default to "open".
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRightClick {
            item.menu = menu
            item.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in self?.item.menu = nil }
        } else {
            onOpen?()
        }
    }

    @objc private func handleOpenMenu() { onOpen?() }
    @objc private func handlePreferences() { onPreferences?() }
    @objc private func handleQuit() { onQuit?() }
}
