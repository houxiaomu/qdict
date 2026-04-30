import XCTest
@testable import Dictonary

final class SettingsTests: XCTestCase {
    fileprivate func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsWhenEmpty() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        XCTAssertEqual(s.provider, .deepseek)
        XCTAssertEqual(s.model, "deepseek-chat")
        XCTAssertEqual(s.hotkey, .defaultCombo)
        XCTAssertFalse(s.didOnboard)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertNil(s.endpoint)
    }

    func testProviderChangePersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults, keychain: InMemoryKeychain())
        s.provider = .openai
        let s2 = Settings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(s2.provider, .openai)
    }

    func testHotkeyChangePersists() throws {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults, keychain: InMemoryKeychain())
        let custom = HotkeyCombo(keyCode: 36, modifiers: 1 << 8)
        s.hotkey = custom
        let s2 = Settings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(s2.hotkey, custom)
    }

    func testAPIKeyRoundTrip() throws {
        let kc = InMemoryKeychain()
        let s = Settings(defaults: makeDefaults(), keychain: kc)
        try s.setAPIKey("sk-foo", for: .deepseek)
        XCTAssertEqual(s.apiKey(for: .deepseek), "sk-foo")
        XCTAssertNil(s.apiKey(for: .openai))
    }

    func testResolvedEndpointFallsBackToProviderDefault() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        XCTAssertEqual(s.resolvedEndpoint(for: .deepseek), ProviderKind.deepseek.defaultEndpoint)
    }

    func testResolvedEndpointHonorsOverride() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        let override = URL(string: "https://example.com/v1")!
        s.endpoint = override
        XCTAssertEqual(s.resolvedEndpoint(for: .deepseek), override)
    }
}

extension SettingsTests {
    func testHistoryLimitDefault() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        XCTAssertEqual(s.historyLimit, 50)
    }

    func testHistoryLimitPersists() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults, keychain: InMemoryKeychain())
        s.historyLimit = 25
        let s2 = Settings(defaults: defaults, keychain: InMemoryKeychain())
        XCTAssertEqual(s2.historyLimit, 25)
    }

    func testHistoryLimitClampsToZeroMin() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        s.historyLimit = -5
        XCTAssertEqual(s.historyLimit, 0)
    }

    func testHistoryLimitClampsToMax() {
        let s = Settings(defaults: makeDefaults(), keychain: InMemoryKeychain())
        s.historyLimit = 9999
        XCTAssertEqual(s.historyLimit, 500)
    }
}
