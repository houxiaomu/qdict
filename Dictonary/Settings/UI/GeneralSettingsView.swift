import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: Settings
    let onHotkeyChanged: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Hotkey") {
                    HotkeyRecorderView(combo: $settings.hotkey, onChange: onHotkeyChanged)
                }
            } footer: {
                Text("Press the hotkey anywhere to summon the translator window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
