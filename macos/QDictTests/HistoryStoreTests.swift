import XCTest
@testable import QDict

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore(limit: Int = 50) -> HistoryStore {
        HistoryStore(fileURL: tempDir.appendingPathComponent("h.json"), limit: limit)
    }

    func testStartsEmpty() {
        let s = makeStore()
        XCTAssertEqual(s.entries.count, 0)
    }

    func testAppendOrdersMostRecentFirst() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        XCTAssertEqual(s.entries.map { $0.query }, ["b", "a"])
    }

    func testFIFOEvictsOldest() {
        let s = makeStore(limit: 2)
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        s.append(query: "c", result: "C", mode: .dictionary)
        XCTAssertEqual(s.entries.map { $0.query }, ["c", "b"])
    }

    func testConsecutiveDuplicateRefreshesTimestampNotCount() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        let firstTs = s.entries[0].timestamp
        Thread.sleep(forTimeInterval: 0.02)
        s.append(query: "a", result: "A2", mode: .dictionary)
        XCTAssertEqual(s.entries.count, 1)
        XCTAssertGreaterThan(s.entries[0].timestamp, firstTs)
        XCTAssertEqual(s.entries[0].result, "A2")
    }

    func testNonConsecutiveDuplicateIsAllowed() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        s.append(query: "a", result: "A", mode: .dictionary)
        XCTAssertEqual(s.entries.map { $0.query }, ["a", "b", "a"])
    }

    func testRemoveByID() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .dictionary)
        s.remove(id: s.entries[0].id)
        XCTAssertEqual(s.entries.map { $0.query }, ["a"])
    }

    func testClearEmptiesEntries() {
        let s = makeStore()
        s.append(query: "a", result: "A", mode: .dictionary)
        s.clear()
        XCTAssertEqual(s.entries.count, 0)
    }

    func testPersistsAcrossInstances() {
        let url = tempDir.appendingPathComponent("h.json")
        let s = HistoryStore(fileURL: url, limit: 50)
        s.append(query: "a", result: "A", mode: .dictionary)
        s.append(query: "b", result: "B", mode: .translation)
        s.flushForTesting()

        let s2 = HistoryStore(fileURL: url, limit: 50)
        XCTAssertEqual(s2.entries.map { $0.query }, ["b", "a"])
        XCTAssertEqual(s2.entries[0].mode, .translation)
    }

    func testCorruptedFileResetsToEmpty() throws {
        let url = tempDir.appendingPathComponent("h.json")
        try Data("{not valid json".utf8).write(to: url)
        let s = HistoryStore(fileURL: url, limit: 50)
        XCTAssertEqual(s.entries.count, 0)
        s.append(query: "a", result: "A", mode: .dictionary)
        XCTAssertEqual(s.entries.count, 1)
    }

    func testLimitChangeApplies() {
        let url = tempDir.appendingPathComponent("h.json")
        let s = HistoryStore(fileURL: url, limit: 50)
        for i in 0..<10 {
            s.append(query: "q\(i)", result: "r\(i)", mode: .dictionary)
        }
        s.setLimit(3)
        XCTAssertEqual(s.entries.count, 3)
        XCTAssertEqual(s.entries.map { $0.query }, ["q9", "q8", "q7"])
    }

    func testZeroLimitDisablesHistory() {
        let s = makeStore(limit: 0)
        s.append(query: "a", result: "A", mode: .dictionary)
        XCTAssertEqual(s.entries.count, 0)
    }
}
