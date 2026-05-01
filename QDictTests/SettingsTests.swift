import XCTest
@testable import QDict

final class SettingsTests: XCTestCase {
    fileprivate func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsWhenEmpty() {
        let s = Settings(defaults: makeDefaults())
        XCTAssertEqual(s.hotkey, .defaultCombo)
        XCTAssertFalse(s.launchAtLogin)
    }

    func testHotkeyChangePersists() throws {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults)
        let custom = HotkeyCombo(keyCode: 36, modifiers: 1 << 8)
        s.hotkey = custom
        let s2 = Settings(defaults: defaults)
        XCTAssertEqual(s2.hotkey, custom)
    }

    func testLaunchAtLoginPersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults)
        s.launchAtLogin = true
        let s2 = Settings(defaults: defaults)
        XCTAssertTrue(s2.launchAtLogin)
    }
}
