import XCTest
@testable import QDict

final class SessionSnapshotTests: XCTestCase {
    func testFreshWithinFiveMinutes() {
        let now = Date()
        let snap = SessionSnapshot(
            input: "hi",
            state: .done("你好"),
            capturedAt: now.addingTimeInterval(-60)
        )
        XCTAssertTrue(snap.isFresh(now: now))
    }

    func testStaleAfterFiveMinutes() {
        let now = Date()
        let snap = SessionSnapshot(
            input: "hi",
            state: .done("你好"),
            capturedAt: now.addingTimeInterval(-301)
        )
        XCTAssertFalse(snap.isFresh(now: now))
    }

    func testFreshAtBoundary() {
        let now = Date()
        // exactly 300s should still count as fresh (use <= when checking).
        let snap = SessionSnapshot(
            input: "hi",
            state: .idle,
            capturedAt: now.addingTimeInterval(-300)
        )
        XCTAssertTrue(snap.isFresh(now: now))
    }

    func testIdleEmptyInputIsNotWorthCapturing() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "", state: .idle)
        XCTAssertNil(snap)
    }

    func testIdleWithInputIsCapturable() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "hi", state: .idle)
        XCTAssertNotNil(snap)
    }

    func testDoneIsCapturable() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "hi", state: .done("你好"))
        XCTAssertNotNil(snap)
    }

    func testStreamingIsCapturable() {
        let snap = SessionSnapshot.makeIfWorthCapturing(input: "hi", state: .streaming("你"))
        XCTAssertNotNil(snap)
    }
}
