import Foundation
import Combine

/// Persists translation history as JSON. Most-recent entry first.
/// Thread-safety: file I/O is serialized via the dedicated queue.
/// `entries` is mutated on the main actor and observed via `@Published`.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private var limit: Int
    private let io = DispatchQueue(label: "app.dictonary.history.io")

    init(fileURL: URL, limit: Int) {
        self.fileURL = fileURL
        self.limit = max(0, limit)
        self.entries = Self.loadFromDisk(fileURL: fileURL)
        if entries.count > self.limit {
            entries = Array(entries.prefix(self.limit))
            persist()
        }
    }

    static func defaultURL() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Dictonary", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func append(query: String, result: String, mode: Mode) {
        guard limit > 0 else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        if let first = entries.first, first.query == q {
            entries[0] = HistoryEntry(
                id: first.id,
                query: q,
                result: result,
                timestamp: Date(),
                mode: mode
            )
            persist()
            return
        }

        let entry = HistoryEntry(query: q, result: result, mode: mode)
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        persist()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func setLimit(_ newLimit: Int) {
        limit = max(0, newLimit)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        persist()
    }

    // MARK: - Disk I/O

    private static func loadFromDisk(fileURL: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let parsed = try? decoder.decode([HistoryEntry].self, from: data) {
            return parsed
        }
        let backup = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return []
    }

    private func persist() {
        let snapshot = entries
        let url = fileURL
        io.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }
}

#if DEBUG
extension HistoryStore {
    /// Block until the most recent persist write reaches disk. Test-only.
    func flushForTesting() {
        io.sync { }
    }
}
#endif
