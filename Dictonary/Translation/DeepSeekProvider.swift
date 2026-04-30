import Foundation

final class DeepSeekProvider: TranslationProvider {
    private let session: URLSession

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
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userText]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw TranslationError.network(message: "no HTTP response")
                    }
                    if http.statusCode == 401 {
                        throw TranslationError.unauthorized
                    } else if http.statusCode == 429 {
                        let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                        throw TranslationError.rateLimited(retryAfter: ra)
                    } else if !(200...299).contains(http.statusCode) {
                        let bodyStr = try await collect(bytes: bytes)
                        throw TranslationError.serverError(status: http.statusCode, body: bodyStr)
                    }

                    var parser = SSEParser()
                    var partial = ""

                    var dataChunk = Data()
                    for try await byte in bytes {
                        dataChunk.append(byte)
                        if dataChunk.count >= 256 {
                            try emit(&parser, &partial, &dataChunk, continuation)
                        }
                    }
                    try emit(&parser, &partial, &dataChunk, continuation)

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let urlErr as URLError {
                    continuation.finish(throwing: TranslationError.network(message: urlErr.localizedDescription))
                } catch let te as TranslationError {
                    continuation.finish(throwing: te)
                } catch {
                    continuation.finish(throwing: TranslationError.network(message: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func emit(
        _ parser: inout SSEParser,
        _ partial: inout String,
        _ chunk: inout Data,
        _ continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        guard !chunk.isEmpty else { return }
        guard let text = String(data: chunk, encoding: .utf8) else {
            chunk.removeAll(keepingCapacity: true)
            return
        }
        chunk.removeAll(keepingCapacity: true)
        for event in parser.feed(text) {
            switch event {
            case .done:
                continuation.finish()
                return
            case .message(let payload):
                if let token = parseDelta(payload) {
                    continuation.yield(token)
                    partial += token
                }
            }
        }
    }

    private func parseDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    private func collect(bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await b in bytes { data.append(b) }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
