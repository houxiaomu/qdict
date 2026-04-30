import Foundation

/// Reusable streaming impl for any provider using OpenAI's chat-completions wire format.
/// Used by both DeepSeek and OpenAI directly.
class OpenAICompatibleProvider: TranslationProvider {
    fileprivate let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        systemPrompt: String,
        userText: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userText]
                        ]
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    try await Self.checkResponse(response, bytes: bytes)

                    var parser = SSEParser()
                    var buf = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buf.append(byte)
                        if Self.drain(&buf, &parser, continuation, deltaParser: Self.parseOpenAIDelta) {
                            return
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let te as TranslationError {
                    continuation.finish(throwing: te)
                } catch let urlErr as URLError {
                    continuation.finish(throwing: TranslationError.network(message: urlErr.localizedDescription))
                } catch {
                    continuation.finish(throwing: TranslationError.network(message: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func checkResponse(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network(message: "no HTTP response")
        }
        if http.statusCode == 401 { throw TranslationError.unauthorized }
        if http.statusCode == 429 {
            let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw TranslationError.rateLimited(retryAfter: ra)
        }
        if !(200...299).contains(http.statusCode) {
            var collected = Data()
            for try await b in bytes { collected.append(b) }
            let body = String(data: collected, encoding: .utf8) ?? ""
            throw TranslationError.serverError(status: http.statusCode, body: body)
        }
    }

    /// Pull as many complete SSE events as possible out of `buf`, feed them to `parser`,
    /// and yield deltas through `continuation`. Returns `true` once a `[DONE]` sentinel
    /// is seen so the caller can exit the read loop.
    ///
    /// We split on the byte pattern `\n\n` (and `\r\n\r\n`) instead of decoding the raw
    /// buffer as UTF-8: `\n` is single-byte, so the boundary is always safe, even if a
    /// multi-byte character (e.g. a Chinese ideograph) straddles a network packet.
    static func drain(
        _ buf: inout Data,
        _ parser: inout SSEParser,
        _ continuation: AsyncThrowingStream<String, Error>.Continuation,
        deltaParser: (String) -> String?
    ) -> Bool {
        let lf2: [UInt8] = [0x0A, 0x0A]
        let crlf2: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]

        while let range = buf.range(of: Data(lf2)) ?? buf.range(of: Data(crlf2)) {
            let eventBytes = buf.subdata(in: 0..<range.upperBound)
            buf.removeSubrange(0..<range.upperBound)
            guard let text = String(data: eventBytes, encoding: .utf8) else { continue }
            for event in parser.feed(text) {
                switch event {
                case .done:
                    continuation.finish()
                    return true
                case .message(let payload):
                    if let token = deltaParser(payload) {
                        continuation.yield(token)
                    }
                }
            }
        }
        return false
    }

    static func parseOpenAIDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

}

/// OpenAI itself.
final class OpenAIProvider: OpenAICompatibleProvider {}
