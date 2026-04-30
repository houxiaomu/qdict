import XCTest
@testable import Dictonary

final class HistoryEntryTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = HistoryEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            query: "hello",
            result: "你好",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            mode: .dictionary
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
