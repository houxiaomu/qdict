import SwiftUI

struct WelcomeView: View {
    let openPreferences: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("👋 Welcome to Dictonary")
                .font(.title2)
            Text("Set your API Key to start translating.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Skip for now", action: skip)
                Button("Open Preferences") { openPreferences() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 360)
    }
}
