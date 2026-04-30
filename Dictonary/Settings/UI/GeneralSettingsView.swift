import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: Settings
    let onHotkeyChanged: () -> Void

    var body: some View {
        Form {
            HStack {
                Text("Hotkey:")
                HotkeyRecorderView(combo: $settings.hotkey, onChange: onHotkeyChanged)
            }
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .padding(20)
    }
}
