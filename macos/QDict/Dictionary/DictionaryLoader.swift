import Foundation

/// Resolves the bundled SQLite file and produces a ``LocalDictionary``.
/// Any failure (missing file, open error) silently degrades to
/// ``EmptyLocalDictionary`` so the rest of the app keeps working.
enum DictionaryLoader {
    static let resourceName = "ecdict"
    static let resourceExtension = "sqlite"

    static func loadBundled(bundle: Bundle = .main) -> LocalDictionary {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            NSLog("[QDict] dictionary resource missing — suggestions disabled")
            return EmptyLocalDictionary()
        }
        do {
            let db = try SQLiteDatabase(path: url.path, readOnly: true)
            return SQLiteLocalDictionary(db: db)
        } catch {
            NSLog("[QDict] dictionary open failed: \(error) — suggestions disabled")
            return EmptyLocalDictionary()
        }
    }
}
