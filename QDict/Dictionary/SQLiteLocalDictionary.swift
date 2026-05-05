import Foundation

/// LocalDictionary backed by a read-only SQLite file (or in-memory DB in tests).
///
/// Query strategy: range scan on the lowercased ``word`` primary key, e.g.
/// ``WHERE word >= 'epi' AND word < 'epj'``. Cheaper than ``LIKE`` and walks
/// the index directly.
final class SQLiteLocalDictionary: LocalDictionary {
    private static let maxPrefixBytes = 32

    private let db: SQLiteDatabase

    init(db: SQLiteDatabase) { self.db = db }

    func prefix(_ s: String, limit: Int) -> [DictionaryEntry] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let lower = String(trimmed.lowercased().prefix(Self.maxPrefixBytes))
        guard let upperBound = nextStringBound(after: lower) else { return [] }

        let sql = """
            SELECT display, pos, gloss, coca
              FROM entries
             WHERE word >= ? AND word < ?
             ORDER BY (CASE WHEN coca IS NULL THEN 999999 ELSE coca END) ASC,
                      word ASC
             LIMIT ?
        """

        do {
            let stmt = try db.prepare(sql)
            try stmt.bind(1, lower)
            try stmt.bind(2, upperBound)
            try stmt.bind(3, limit)

            var out: [DictionaryEntry] = []
            while try stmt.step() {
                let display = stmt.text(0) ?? ""
                let pos = stmt.text(1)
                let gloss = stmt.text(2) ?? ""
                let coca = stmt.int(3) ?? .max
                out.append(DictionaryEntry(
                    word: display, pos: pos, gloss: gloss, cocaRank: coca
                ))
            }
            return out
        } catch {
            return []
        }
    }

    /// Compute the exclusive upper bound for a prefix scan: increment the last
    /// scalar by one. Returns nil if the input is empty.
    private func nextStringBound(after s: String) -> String? {
        guard !s.isEmpty else { return nil }
        var scalars = Array(s.unicodeScalars)
        guard let last = scalars.popLast() else { return nil }
        let next = Unicode.Scalar(last.value + 1) ?? last
        scalars.append(next)
        return String(String.UnicodeScalarView(scalars))
    }
}
