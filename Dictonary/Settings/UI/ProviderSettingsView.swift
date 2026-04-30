import SwiftUI

struct ProviderSettingsView: View {

    enum TestStatus: Equatable {
        case idle
        case info(String)     // neutral message ("Saved", "Endpoint reset…")
        case success(String)  // ✓ green
        case failure(String)  // ⚠ red
    }

    @ObservedObject var settings: Settings
    let translationService: TranslationService

    @State private var apiKeyInput: String = ""
    @State private var endpointInput: String = ""
    @State private var status: TestStatus = .idle
    @State private var testing = false

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(ProviderKind.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .onChange(of: settings.provider) { newValue in
                    settings.model = newValue.defaultModel
                    apiKeyInput = settings.apiKey(for: newValue) ?? ""
                    endpointInput = settings.endpoint?.absoluteString ?? ""
                    status = .idle
                }

                TextField("Model", text: $settings.model)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                LabeledContent("API Key") {
                    HStack(spacing: 8) {
                        SecureField("sk-…", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button("Save", action: saveKey)
                            .disabled(apiKeyInput.isEmpty)
                        Button(testing ? "Testing…" : "Test") {
                            Task { await runTest() }
                        }
                        .disabled(testing || apiKeyInput.isEmpty)
                    }
                }

                if status != .idle {
                    statusRow
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Stored securely in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Endpoint") {
                    HStack(spacing: 8) {
                        TextField("Default", text: $endpointInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button("Apply", action: applyEndpoint)
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Leave empty to use the provider's default endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear {
            apiKeyInput = settings.apiKey(for: settings.provider) ?? ""
            endpointInput = settings.endpoint?.absoluteString ?? ""
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.tint)
            Text(status.message)
                .font(.callout)
                .foregroundStyle(status.tint)
            Spacer()
        }
    }

    // MARK: - Actions

    private func saveKey() {
        do {
            try settings.setAPIKey(apiKeyInput, for: settings.provider)
            status = .info("Saved")
        } catch {
            status = .failure("Save failed: \(error.localizedDescription)")
        }
    }

    private func applyEndpoint() {
        let trimmed = endpointInput.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            settings.endpoint = nil
            status = .info("Endpoint reset to default.")
        } else if let url = URL(string: trimmed), url.scheme != nil {
            settings.endpoint = url
            status = .info("Endpoint updated.")
        } else {
            status = .failure("Invalid URL.")
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        // Save first so TranslationService picks it up.
        do {
            try settings.setAPIKey(apiKeyInput, for: settings.provider)
        } catch {
            status = .failure("Save failed: \(error.localizedDescription)")
            return
        }
        do {
            var collected = ""
            for try await token in translationService.translate(systemPrompt: "Reply OK", userText: "ping") {
                collected += token
                if collected.count > 4 { break }
            }
            status = .success("Connection OK")
        } catch let e as TranslationError {
            status = .failure(e.errorDescription ?? "Failed")
        } catch {
            status = .failure(error.localizedDescription)
        }
    }
}

private extension ProviderSettingsView.TestStatus {
    var message: String {
        switch self {
        case .idle:                 return ""
        case .info(let s),
             .success(let s),
             .failure(let s):       return s
        }
    }

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle"
        case .idle:    return ""
        }
    }

    var tint: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .info:    return .secondary
        case .idle:    return .clear
        }
    }
}
