import SwiftUI

@main
struct DictonaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView(
                settings: appDelegate.container.settings,
                translationService: appDelegate.container.translationService,
                onHotkeyChanged: { appDelegate.reregisterHotkey() }
            )
        }
    }
}
