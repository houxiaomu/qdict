import Foundation
import Combine

final class Settings: ObservableObject {

    // Keys for UserDefaults
    private enum Key {
        static let provider     = "provider"
        static let model        = "model"
        static let endpoint     = "endpoint"
        static let hotkey       = "hotkey"
        static let launchAtLogin = "launchAtLogin"
        static let didOnboard   = "didOnboard"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainService

    @Published var provider: ProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: Key.provider) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    @Published var endpoint: URL? {
        didSet { defaults.set(endpoint?.absoluteString, forKey: Key.endpoint) }
    }

    @Published var hotkey: HotkeyCombo {
        didSet { try? saveHotkey(hotkey) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var didOnboard: Bool {
        didSet { defaults.set(didOnboard, forKey: Key.didOnboard) }
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainService = SystemKeychain()) {
        self.defaults = defaults
        self.keychain = keychain

        let providerRaw = defaults.string(forKey: Key.provider) ?? ProviderKind.deepseek.rawValue
        let providerKind = ProviderKind(rawValue: providerRaw) ?? .deepseek
        self.provider = providerKind
        self.model = defaults.string(forKey: Key.model) ?? providerKind.defaultModel
        if let s = defaults.string(forKey: Key.endpoint), let url = URL(string: s) {
            self.endpoint = url
        } else {
            self.endpoint = nil
        }
        if let data = defaults.data(forKey: Key.hotkey),
           let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            self.hotkey = combo
        } else {
            self.hotkey = .defaultCombo
        }
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.didOnboard = defaults.bool(forKey: Key.didOnboard)
    }

    // MARK: - API key helpers

    func apiKey(for kind: ProviderKind) -> String? {
        (try? keychain.read(account: kind.rawValue)) ?? nil
    }

    func setAPIKey(_ key: String, for kind: ProviderKind) throws {
        try keychain.write(key, account: kind.rawValue)
    }

    func deleteAPIKey(for kind: ProviderKind) throws {
        try keychain.delete(account: kind.rawValue)
    }

    /// The endpoint to actually use: user override if present, else provider default.
    func resolvedEndpoint(for kind: ProviderKind) -> URL {
        endpoint ?? kind.defaultEndpoint
    }

    private func saveHotkey(_ combo: HotkeyCombo) throws {
        let data = try JSONEncoder().encode(combo)
        defaults.set(data, forKey: Key.hotkey)
    }
}
