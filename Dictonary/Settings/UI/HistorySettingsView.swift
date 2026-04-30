import SwiftUI

struct HistorySettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var historyStore: HistoryStore

    var body: some View {
        Form {
            Section {
                Stepper(
                    value: $settings.historyLimit,
                    in: 0...500,
                    step: 10
                ) {
                    LabeledContent("Keep last") {
                        Text("\(settings.historyLimit) entries")
                    }
                }
            } footer: {
                Text("Set to 0 to disable history. Range: 0–500.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Stored entries", value: "\(historyStore.entries.count)")
            }

            Section {
                Button("Clear History", role: .destructive) {
                    historyStore.clear()
                }
                .disabled(historyStore.entries.isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
