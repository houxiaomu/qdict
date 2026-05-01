import Foundation
import Combine

final class Settings: ObservableObject {

    // Keys for UserDefaults
    private enum Key {
        static let hotkey       = "hotkey"
        static let launchAtLogin = "launchAtLogin"
        static let historyLimit = "historyLimit"
    }

    private let defaults: UserDefaults

    @Published var hotkey: HotkeyCombo {
        didSet { try? saveHotkey(hotkey) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var historyLimit: Int {
        didSet {
            let clamped = max(0, min(500, historyLimit))
            if clamped != historyLimit {
                historyLimit = clamped
            } else {
                defaults.set(clamped, forKey: Key.historyLimit)
            }
        }
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
        let raw = defaults.object(forKey: Key.historyLimit) as? Int
        self.historyLimit = max(0, min(500, raw ?? 50))
    }

    private func saveHotkey(_ combo: HotkeyCombo) throws {
        let data = try JSONEncoder().encode(combo)
        defaults.set(data, forKey: Key.hotkey)
    }
}
