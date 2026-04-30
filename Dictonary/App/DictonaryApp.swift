import SwiftUI

@main
struct DictonaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The Preferences window is managed directly by AppDelegate (see
    // showPreferences). Leaving an empty Settings scene out keeps the binary
    // free of dead UI code paths.
    var body: some Scene {
        // SwiftUI requires at least one Scene. Use SwiftUI.Settings (qualified
        // because we have our own `Settings` type) with an empty view; the
        // real preferences window is opened by AppDelegate.showPreferences.
        SwiftUI.Settings { EmptyView() }
    }
}
