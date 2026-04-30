import Foundation

final class TranslationService {
    private let settings: Settings
    private let providers: [ProviderKind: TranslationProvider]

    init(settings: Settings, providers: [ProviderKind: TranslationProvider]? = nil) {
        self.settings = settings
        self.providers = providers ?? [
            .deepseek: DeepSeekProvider(),
            .openai:   OpenAIProvider(),
            .claude:   ClaudeProvider()
        ]
    }

    /// Translates `userText` using the active provider in `Settings`.
    /// Yields tokens as they stream. May throw `TranslationError`.
    func translate(systemPrompt: String, userText: String) -> AsyncThrowingStream<String, Error> {
        let kind = settings.provider
        guard let provider = providers[kind] else {
            return AsyncThrowingStream { c in c.finish(throwing: TranslationError.network(message: "provider missing")) }
        }
        guard let key = settings.apiKey(for: kind), !key.isEmpty else {
            return AsyncThrowingStream { c in c.finish(throwing: TranslationError.missingAPIKey) }
        }
        return provider.translate(
            systemPrompt: systemPrompt,
            userText: userText,
            apiKey: key,
            model: settings.model,
            endpoint: settings.resolvedEndpoint(for: kind)
        )
    }
}
