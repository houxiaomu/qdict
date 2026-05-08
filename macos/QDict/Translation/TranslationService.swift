import Foundation

final class TranslationService {
    private let providers: [ProviderKind: TranslationProvider]

    init(providers: [ProviderKind: TranslationProvider]? = nil) {
        self.providers = providers ?? [
            .deepseek: DeepSeekProvider(),
            .openai:   OpenAIProvider(),
            .claude:   ClaudeProvider()
        ]
    }

    /// Translates `userText` using `ProviderConfig.active`.
    /// Yields tokens as they stream. May throw `TranslationError`.
    func translate(systemPrompt: String, userText: String) -> AsyncThrowingStream<String, Error> {
        let kind = ProviderConfig.active
        guard let provider = providers[kind] else {
            return AsyncThrowingStream { c in
                c.finish(throwing: TranslationError.network(message: "provider missing"))
            }
        }
        return provider.translate(
            systemPrompt: systemPrompt,
            userText: userText,
            apiKey: ProviderConfig.apiKey(for: kind),
            model: ProviderConfig.model(for: kind),
            endpoint: ProviderConfig.endpoint(for: kind)
        )
    }
}
