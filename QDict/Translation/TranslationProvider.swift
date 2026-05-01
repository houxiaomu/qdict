import Foundation

protocol TranslationProvider {
    /// Streams the model's response token-by-token.
    /// Throws `TranslationError` (mapped from underlying transport errors).
    func translate(
        systemPrompt: String,
        userText: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) -> AsyncThrowingStream<String, Error>
}
