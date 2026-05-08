import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var historyStore: HistoryStore
    let onHotkeyChanged: () -> Void

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Hotkey")
                    Spacer()
                    HotkeyRecorderView(combo: $settings.hotkey, onChange: onHotkeyChanged)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                LabeledContent("History") {
                    Button("Clear History", role: .destructive) {
                        historyStore.clear()
                    }
                    .disabled(historyStore.entries.isEmpty)
                }
            }

            Section {
                HStack(spacing: 12) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QDict")
                            .font(.callout.weight(.semibold))
                        Text("Version \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 480, height: 360)
    }
}
