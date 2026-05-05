import XCTest
@testable import QDict

final class DictionaryLoaderTests: XCTestCase {
    /// Bundled DB should load and return some entries for the prefix "the".
    /// Use the QDict app bundle explicitly: in unit-test runs, ``Bundle.main``
    /// is the test runner, not the host app, so default lookup would fail.
    /// Skips when the resource has not yet been generated (e.g. before the
    /// ECDICT CSV is processed in dev environments).
    func testLoadBundledReturnsRealDictionary() throws {
        let appBundle = Bundle(for: TranslatorWindowController.self)
        guard appBundle.url(forResource: "ecdict", withExtension: "sqlite") != nil else {
            throw XCTSkip("bundled dictionary not yet generated; run scripts/build-dictionary.py")
        }
        let dict = DictionaryLoader.loadBundled(bundle: appBundle)
        let hits = dict.prefix("the", limit: 3)
        XCTAssertFalse(hits.isEmpty, "Bundled dictionary should have entries for 'the'")
    }

    /// Missing resource → fallback. The unit-test bundle does not contain
    /// ``ecdict.sqlite``, so this exercises the fallback branch.
    func testLoadFallsBackWhenResourceMissing() {
        let testBundle = Bundle(for: DictionaryLoaderTests.self)
        let dict = DictionaryLoader.loadBundled(bundle: testBundle)
        XCTAssertTrue(dict is EmptyLocalDictionary)
        XCTAssertEqual(dict.prefix("the", limit: 3), [])
    }
}
