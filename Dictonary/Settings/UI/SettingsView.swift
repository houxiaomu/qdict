import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let translationService: TranslationService
    let onHotkeyChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, onHotkeyChanged: onHotkeyChanged)
                .tabItem { Label("General", systemImage: "gear") }

            ProviderSettingsView(settings: settings, translationService: translationService)
                .tabItem { Label("Provider", systemImage: "cloud") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
    }
}
