import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var historyStore: HistoryStore
    let translationService: TranslationService
    let onHotkeyChanged: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, onHotkeyChanged: onHotkeyChanged)
                .tabItem { Label("General", systemImage: "gear") }

            ProviderSettingsView(settings: settings, translationService: translationService)
                .tabItem { Label("Provider", systemImage: "cloud") }

            HistorySettingsView(settings: settings, historyStore: historyStore)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 440)
    }
}
