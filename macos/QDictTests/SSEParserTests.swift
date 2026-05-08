import XCTest
@testable import QDict

final class SSEParserTests: XCTestCase {

    func testParsesSingleDataLine() {
        var parser = SSEParser()
        let events = parser.feed("data: hello\n\n")
        XCTAssertEqual(events, [.message("hello")])
    }

    func testParsesMultipleDataLinesInOneEventConcatenatesWithNewline() {
        var parser = SSEParser()
        let events = parser.feed("data: line1\ndata: line2\n\n")
        XCTAssertEqual(events, [.message("line1\nline2")])
    }

    func testEmitsDoneOnDoneSentinel() {
        var parser = SSEParser()
        let events = parser.feed("data: [DONE]\n\n")
        XCTAssertEqual(events, [.done])
    }

    func testHandlesChunkedFeedingMidEvent() {
        var parser = SSEParser()
        var all: [SSEEvent] = []
        all += parser.feed("data: hel")
        all += parser.feed("lo\n")
        all += parser.feed("\n")
        XCTAssertEqual(all, [.message("hello")])
    }

    func testIgnoresCommentsAndUnknownFields() {
        var parser = SSEParser()
        let events = parser.feed(": keepalive\nfoo: bar\ndata: real\n\n")
        XCTAssertEqual(events, [.message("real")])
    }

    func testHandlesMultipleEventsInOneChunk() {
        var parser = SSEParser()
        let events = parser.feed("data: a\n\ndata: b\n\n")
        XCTAssertEqual(events, [.message("a"), .message("b")])
    }
}
