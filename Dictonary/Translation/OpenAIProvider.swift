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
                    try Self.checkResponse(response, bytes: bytes)

                    var parser = SSEParser()
                    var dataChunk = Data()

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        dataChunk.append(byte)
                        if dataChunk.count >= 256 {
                            Self.flush(&parser, &dataChunk, continuation, deltaParser: Self.parseOpenAIDelta)
                        }
                    }
                    Self.flush(&parser, &dataChunk, continuation, deltaParser: Self.parseOpenAIDelta)
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

    static func checkResponse(_ response: URLResponse, bytes: URLSession.AsyncBytes) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network(message: "no HTTP response")
        }
        if http.statusCode == 401 { throw TranslationError.unauthorized }
        if http.statusCode == 429 {
            let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw TranslationError.rateLimited(retryAfter: ra)
        }
        if !(200...299).contains(http.statusCode) {
            // Sync-collect body since this is the failure path.
            let body = try awaitableCollect(bytes: bytes)
            throw TranslationError.serverError(status: http.statusCode, body: body)
        }
    }

    static func flush(
        _ parser: inout SSEParser,
        _ chunk: inout Data,
        _ continuation: AsyncThrowingStream<String, Error>.Continuation,
        deltaParser: (String) -> String?
    ) {
        guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else {
            chunk.removeAll(keepingCapacity: true); return
        }
        chunk.removeAll(keepingCapacity: true)
        for event in parser.feed(text) {
            switch event {
            case .done:
                continuation.finish(); return
            case .message(let payload):
                if let token = deltaParser(payload) {
                    continuation.yield(token)
                }
            }
        }
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

    private static func awaitableCollect(bytes: URLSession.AsyncBytes) throws -> String {
        // Synchronously drain remaining bytes by spinning a child task.
        let semaphore = DispatchSemaphore(value: 0)
        var collected = Data()
        var capturedError: Error?
        let task = Task {
            defer { semaphore.signal() }
            do {
                for try await b in bytes { collected.append(b) }
            } catch { capturedError = error }
        }
        semaphore.wait()
        _ = task
        if let e = capturedError { throw e }
        return String(data: collected, encoding: .utf8) ?? ""
    }
}

/// OpenAI itself.
final class OpenAIProvider: OpenAICompatibleProvider {}
