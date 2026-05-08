import Foundation
import Combine

final class Settings: ObservableObject {

    // Keys for UserDefaults
    private enum Key {
        static let hotkey       = "hotkey"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    @Published var hotkey: HotkeyCombo {
        didSet { try? saveHotkey(hotkey) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.hotkey),
           let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            self.hotkey = combo
        } else {
            self.hotkey = .defaultCombo
        }
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }

    private func saveHotkey(_ combo: HotkeyCombo) throws {
        let data = try JSONEncoder().encode(combo)
        defaults.set(data, forKey: Key.hotkey)
    }
}
