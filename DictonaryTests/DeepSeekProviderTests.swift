import XCTest
@testable import Dictonary

final class DeepSeekProviderTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRequestShapeIsOpenAICompatible() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { req in
            capturedRequest = req
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (resp, [Data("data: [DONE]\n\n".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        let stream = provider.translate(
            systemPrompt: "SYS",
            userText: "hello",
            apiKey: "sk-test",
            model: "deepseek-chat",
            endpoint: URL(string: "https://api.deepseek.com/v1/chat/completions")!
        )
        for try await _ in stream { }

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.bodyData)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "deepseek-chat")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[0]["role"], "system")
        XCTAssertEqual(messages?[0]["content"], "SYS")
        XCTAssertEqual(messages?[1]["role"], "user")
        XCTAssertEqual(messages?[1]["content"], "hello")
    }

    func testStreamYieldsDeltaContent() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunks = [
                "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
                "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n",
                "data: [DONE]\n\n"
            ].map { Data($0.utf8) }
            return (resp, chunks)
        }
        let provider = DeepSeekProvider(session: .mocked())
        var output = ""
        for try await piece in provider.translate(
            systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
            endpoint: URL(string: "https://example.com")!
        ) {
            output += piece
        }
        XCTAssertEqual(output, "Hello")
    }

    func testUnauthorizedMapsToTranslationError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, [Data("{\"error\":\"bad key\"}".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRateLimitedMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 429,
                httpVersion: nil, headerFields: ["Retry-After": "12"]
            )!
            return (resp, [Data("rate limited".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 12))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testServerErrorMaps() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (resp, [Data("oops".utf8)])
        }
        let provider = DeepSeekProvider(session: .mocked())
        do {
            for try await _ in provider.translate(
                systemPrompt: "x", userText: "y", apiKey: "k", model: "m",
                endpoint: URL(string: "https://example.com")!
            ) { }
            XCTFail("expected error")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .serverError(status: 503, body: "oops"))
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}

// Helper to read URLRequest body even when set via httpBodyStream.
extension URLRequest {
    var bodyData: Data? {
        if let d = httpBody { return d }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let bufSize = 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: bufSize)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
