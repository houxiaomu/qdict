import XCTest
@testable import Dictonary

final class ClaudeProviderTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    func testRequestUsesMessagesAPIShape() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, [Data("data: {\"type\":\"message_stop\"}\n\n".utf8)])
        }
        let p = ClaudeProvider(session: .mocked())
        for try await _ in p.translate(
            systemPrompt: "SYS", userText: "Hi",
            apiKey: "sk-ant", model: "claude-haiku-4-5-20251001",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!
        ) { }

        let req = try XCTUnwrap(captured)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try XCTUnwrap(req.bodyData)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(json?["system"] as? String, "SYS")
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "Hi")
    }

    func testStreamsTextDeltas() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunks = [
                "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}\n\n",
                "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n"
            ].map { Data($0.utf8) }
            return (resp, chunks)
        }
        let p = ClaudeProvider(session: .mocked())
        var out = ""
        for try await t in p.translate(
            systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
            endpoint: URL(string: "https://example.com")!
        ) {
            out += t
        }
        XCTAssertEqual(out, "Hello")
    }

    func testUnauthorizedMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, [])
        }
        let p = ClaudeProvider(session: .mocked())
        do {
            for try await _ in p.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let e as TranslationError {
            XCTAssertEqual(e, .unauthorized)
        } catch { XCTFail("unexpected: \(error)") }
    }
}
