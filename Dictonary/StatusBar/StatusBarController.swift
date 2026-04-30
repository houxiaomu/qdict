import AppKit

@MainActor
final class StatusBarController {
    private let item: NSStatusItem
    private var menu: NSMenu

    var onOpen: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    var needsAPIKey: Bool = false {
        didSet { renderIcon() }
    }

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        renderIcon()
        configureMenu()
    }

    private func renderIcon() {
        guard let button = item.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Dictonary")
        button.image = base?.withSymbolConfiguration(cfg)
        if needsAPIKey {
            // Add a tiny red dot indicator by appending another image inside the cell.
            button.title = "•"
            button.imagePosition = .imageLeft
            button.contentTintColor = .systemRed
        } else {
            button.title = ""
            button.contentTintColor = nil
        }
        button.target = self
        button.action = #selector(handleClick)
    }

    private func configureMenu() {
        menu.addItem(NSMenuItem(title: "打开", action: #selector(handleOpenMenu), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(handlePreferences), keyEquivalent: ","))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dictonary", action: #selector(handleQuit), keyEquivalent: "q"))
        menu.items.last?.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            item.menu = menu
            item.button?.performClick(nil)
            // Reset so the next left click triggers onOpen instead of menu.
            DispatchQueue.main.async { [weak self] in self?.item.menu = nil }
        } else {
            onOpen?()
        }
    }

    @objc private func handleOpenMenu() { onOpen?() }
    @objc private func handlePreferences() { onPreferences?() }
    @objc private func handleQuit() { onQuit?() }
}
