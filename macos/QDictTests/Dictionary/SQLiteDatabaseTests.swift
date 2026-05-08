import XCTest
@testable import QDict

final class SQLiteDatabaseTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let db = try SQLiteDatabase(memory: ())
        try db.execute("CREATE TABLE t (k TEXT PRIMARY KEY, v INTEGER)")
        try db.execute("INSERT INTO t (k, v) VALUES ('a', 1), ('b', 2)")

        let stmt = try db.prepare("SELECT k, v FROM t ORDER BY k")
        var rows: [(String, Int)] = []
        while try stmt.step() {
            rows.append((stmt.text(0) ?? "", stmt.int(1) ?? -1))
        }
        XCTAssertEqual(rows.map(\.0), ["a", "b"])
        XCTAssertEqual(rows.map(\.1), [1, 2])
    }

    func testBindString() throws {
        let db = try SQLiteDatabase(memory: ())
        try db.execute("CREATE TABLE t (k TEXT)")
        try db.execute("INSERT INTO t (k) VALUES ('apple'), ('apricot'), ('banana')")

        let stmt = try db.prepare("SELECT k FROM t WHERE k >= ? AND k < ? ORDER BY k")
        try stmt.bind(1, "ap")
        try stmt.bind(2, "aq")

        var found: [String] = []
        while try stmt.step() { found.append(stmt.text(0) ?? "") }
        XCTAssertEqual(found, ["apple", "apricot"])
    }

    func testOpenMissingFileThrows() {
        XCTAssertThrowsError(try SQLiteDatabase(path: "/nonexistent/qdict-test.sqlite", readOnly: true))
    }
}
