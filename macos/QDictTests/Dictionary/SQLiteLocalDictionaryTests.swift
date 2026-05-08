import XCTest
@testable import QDict

final class SQLiteLocalDictionaryTests: XCTestCase {
    private func makeFixtureDB() throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(memory: ())
        try db.execute("""
            CREATE TABLE entries (
                word    TEXT NOT NULL PRIMARY KEY,
                display TEXT NOT NULL,
                pos     TEXT,
                gloss   TEXT NOT NULL,
                coca    INTEGER,
                collins INTEGER
            )
        """)
        try db.execute("""
            INSERT INTO entries (word, display, pos, gloss, coca, collins) VALUES
              ('epic',     'epic',     'adj.', '史诗的；宏大的',    150,  4),
              ('episode',  'episode',  'n.',   '一集；插曲',        300,  4),
              ('epitome',  'epitome',  'n.',   '典型；缩影',       4000,  3),
              ('epiphany', 'epiphany', 'n.',   '顿悟；主显节',     6000,  2),
              ('epidemic', 'epidemic', 'n.',   '流行病；传染病',   2200,  3),
              ('epinephrine','epinephrine','n.','肾上腺素',       12000,  1),
              ('apple',    'apple',    'n.',   '苹果',               80,  5),
              ('look up to','look up to', NULL,'尊敬',             8000,  NULL)
        """)
        return db
    }

    func testPrefixReturnsAscendingByCoca() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let words = dict.prefix("epi", limit: 6).map(\.word)
        XCTAssertEqual(words, ["epic", "episode", "epidemic", "epitome", "epiphany", "epinephrine"])
    }

    func testPrefixHonorsLimit() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        XCTAssertEqual(dict.prefix("epi", limit: 2).count, 2)
    }

    func testPrefixIsCaseInsensitive() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let upper = dict.prefix("EPI", limit: 6).map(\.word)
        let lower = dict.prefix("epi", limit: 6).map(\.word)
        XCTAssertEqual(upper, lower)
    }

    func testPrefixReturnsEmptyForUnknown() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        XCTAssertEqual(dict.prefix("xyz123", limit: 6), [])
    }

    func testPrefixSupportsPhraseEntries() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let words = dict.prefix("look u", limit: 6).map(\.word)
        XCTAssertEqual(words, ["look up to"])
    }

    func testPrefixTruncatesOverlongInput() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let huge = String(repeating: "z", count: 100)
        // Must not crash; result is empty because no word matches.
        XCTAssertEqual(dict.prefix(huge, limit: 6), [])
    }

    func testEntryFieldsArePopulated() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let e = dict.prefix("epip", limit: 1).first
        XCTAssertEqual(e?.word, "epiphany")
        XCTAssertEqual(e?.pos, "n.")
        XCTAssertEqual(e?.gloss, "顿悟；主显节")
        XCTAssertEqual(e?.cocaRank, 6000)
    }

    func testEntryWithNullPosReadsAsNil() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        let e = dict.prefix("look", limit: 1).first
        XCTAssertEqual(e?.word, "look up to")
        XCTAssertNil(e?.pos)
    }

    func testEmptyPrefixReturnsEmpty() throws {
        let dict = SQLiteLocalDictionary(db: try makeFixtureDB())
        XCTAssertEqual(dict.prefix("", limit: 6), [])
    }
}
