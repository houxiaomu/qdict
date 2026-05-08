import Foundation
import SQLite3

/// Errors thrown by ``SQLiteDatabase`` and ``SQLiteStatement``.
enum SQLiteError: Error, CustomStringConvertible {
    case open(code: Int32, message: String)
    case prepare(code: Int32, message: String, sql: String)
    case bind(code: Int32, message: String)
    case step(code: Int32, message: String)

    var description: String {
        switch self {
        case let .open(c, m):     return "SQLite open failed (\(c)): \(m)"
        case let .prepare(c, m, sql): return "SQLite prepare failed (\(c)) for [\(sql)]: \(m)"
        case let .bind(c, m):     return "SQLite bind failed (\(c)): \(m)"
        case let .step(c, m):     return "SQLite step failed (\(c)): \(m)"
        }
    }
}

/// Thin wrapper over the system ``sqlite3`` C API. Supports the small surface
/// our dictionary needs: open (file or memory), execute, prepare, bind, step.
final class SQLiteDatabase {
    fileprivate let db: OpaquePointer

    /// Open a database file. Pass ``readOnly: true`` for bundled resources.
    init(path: String, readOnly: Bool) throws {
        var handle: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw SQLiteError.open(code: rc, message: msg)
        }
        self.db = handle
    }

    /// Open an in-memory database (used by tests).
    init(memory: Void) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            ":memory:", &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        )
        guard rc == SQLITE_OK, let handle else {
            throw SQLiteError.open(code: rc, message: "in-memory open failed")
        }
        self.db = handle
    }

    deinit { sqlite3_close(db) }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        guard rc == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.prepare(code: rc, message: msg, sql: sql)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepare(code: rc, message: msg, sql: sql)
        }
        return SQLiteStatement(stmt: stmt, db: db)
    }
}

/// A prepared statement; finalizes automatically on deinit.
final class SQLiteStatement {
    private let stmt: OpaquePointer
    private let db: OpaquePointer

    fileprivate init(stmt: OpaquePointer, db: OpaquePointer) {
        self.stmt = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(stmt) }

    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    func bind(_ index: Int32, _ text: String) throws {
        let rc = sqlite3_bind_text(stmt, index, text, -1, Self.SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw SQLiteError.bind(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    func bind(_ index: Int32, _ value: Int) throws {
        let rc = sqlite3_bind_int64(stmt, index, sqlite3_int64(value))
        guard rc == SQLITE_OK else {
            throw SQLiteError.bind(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Step the statement. Returns true if a row is available; false at end.
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteError.step(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    func text(_ column: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cstr)
    }

    func int(_ column: Int32) -> Int? {
        let type = sqlite3_column_type(stmt, column)
        guard type != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, column))
    }
}
