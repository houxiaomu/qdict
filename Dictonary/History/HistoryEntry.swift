import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let query: String
    let result: String
    let timestamp: Date
    let mode: Mode

    init(id: UUID = UUID(), query: String, result: String, timestamp: Date = Date(), mode: Mode) {
        self.id = id
        self.query = query
        self.result = result
        self.timestamp = timestamp
        self.mode = mode
    }
}

extension Mode: Codable {}
