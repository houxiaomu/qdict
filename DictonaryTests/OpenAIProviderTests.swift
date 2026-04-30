import XCTest
@testable import Dictonary

final class OpenAIProviderTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    func testStreamsContent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunks = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n",
                "data: [DONE]\n\n"
            ].map { Data($0.utf8) }
            return (resp, chunks)
        }
        let provider = OpenAIProvider(session: .mocked())
        var out = ""
        for try await t in provider.translate(
            systemPrompt: "s", userText: "u", apiKey: "k", model: "gpt-4o-mini",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!
        ) {
            out += t
        }
        XCTAssertEqual(out, "Hi")
    }

    func testUnauthorizedMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, [])
        }
        let provider = OpenAIProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "s", userText: "u", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let e as TranslationError {
            XCTAssertEqual(e, .unauthorized)
        } catch { XCTFail("unexpected: \(error)") }
    }
}
