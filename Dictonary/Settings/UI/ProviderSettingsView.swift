import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var settings: Settings
    let translationService: TranslationService
    @State private var apiKeyInput: String = ""
    @State private var endpointInput: String = ""
    @State private var testStatus: String = ""
    @State private var testing = false

    var body: some View {
        Form {
            // NOTE: single-arg `.onChange` closure — works on macOS 13.
            // Two-arg form (`{ _, newValue in }`) is macOS 14+.
            Picker("Provider", selection: $settings.provider) {
                ForEach(ProviderKind.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .onChange(of: settings.provider) { newValue in
                settings.model = newValue.defaultModel
                apiKeyInput = settings.apiKey(for: newValue) ?? ""
                endpointInput = settings.endpoint?.absoluteString ?? ""
                testStatus = ""
            }

            HStack {
                SecureField("API Key", text: $apiKeyInput)
                Button("Save") {
                    do {
                        try settings.setAPIKey(apiKeyInput, for: settings.provider)
                        testStatus = "Saved"
                    } catch {
                        testStatus = "Save failed: \(error.localizedDescription)"
                    }
                }
                Button(testing ? "Testing…" : "Test") {
                    Task { await runTest() }
                }
                .disabled(testing || apiKeyInput.isEmpty)
            }

            TextField("Model", text: $settings.model)

            // Optional override; empty string means "use provider default".
            HStack {
                TextField("Endpoint (advanced, leave empty for default)", text: $endpointInput)
                Button("Apply") {
                    let trimmed = endpointInput.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        settings.endpoint = nil
                        testStatus = "Endpoint reset to default"
                    } else if let url = URL(string: trimmed), url.scheme != nil {
                        settings.endpoint = url
                        testStatus = "Endpoint updated"
                    } else {
                        testStatus = "Invalid URL"
                    }
                }
            }

            Text(testStatus)
                .font(.caption)
                .foregroundStyle(testStatus.starts(with: "OK") ? .green : .secondary)
        }
        .padding(20)
        .onAppear {
            apiKeyInput = settings.apiKey(for: settings.provider) ?? ""
            endpointInput = settings.endpoint?.absoluteString ?? ""
        }
    }

    private func runTest() async {
        testing = true; defer { testing = false }
        // Save first so TranslationService picks it up.
        do {
            try settings.setAPIKey(apiKeyInput, for: settings.provider)
        } catch {
            testStatus = "Save failed: \(error.localizedDescription)"
            return
        }
        do {
            var collected = ""
            for try await token in translationService.translate(systemPrompt: "Reply OK", userText: "ping") {
                collected += token
                if collected.count > 4 { break }
            }
            testStatus = "OK"
        } catch let e as TranslationError {
            testStatus = e.errorDescription ?? "Failed"
        } catch {
            testStatus = error.localizedDescription
        }
    }
}
