import Foundation

final class ClaudeProvider: TranslationProvider {
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
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 1024,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": [
                            ["role": "user", "content": userText]
                        ]
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    try await OpenAICompatibleProvider.checkResponse(response, bytes: bytes)

                    var parser = SSEParser()
                    var chunkData = Data()

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunkData.append(byte)
                        if chunkData.count >= 256 {
                            OpenAICompatibleProvider.flush(&parser, &chunkData, continuation, deltaParser: ClaudeProvider.parseClaudeDelta)
                        }
                    }
                    OpenAICompatibleProvider.flush(&parser, &chunkData, continuation, deltaParser: ClaudeProvider.parseClaudeDelta)
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

    private static func parseClaudeDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let type = obj["type"] as? String else { return nil }
        if type == "content_block_delta",
           let delta = obj["delta"] as? [String: Any],
           delta["type"] as? String == "text_delta",
           let text = delta["text"] as? String {
            return text
        }
        return nil
    }
}
