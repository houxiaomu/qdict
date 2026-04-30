import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Dictonary").font(.title2)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}
