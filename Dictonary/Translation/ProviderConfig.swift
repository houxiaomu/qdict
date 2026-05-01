import Foundation

/// Hardcoded provider configuration. Single source of truth for which provider
/// to call and what credentials to use.
///
/// This replaces user-configurable provider settings while keeping the
/// multi-provider routing skeleton in place. Future plan: swap these constants
/// for a server-side router.
enum ProviderConfig {
    /// Currently-active provider. Change here to test other providers.
    static let active: ProviderKind = .deepseek

    /// API keys per provider. Empty string means "not configured yet".
    /// Filled in locally; this repo is not published.
    static let apiKeys: [ProviderKind: String] = [
        .deepseek: "",
        .openai:   "",
        .claude:   ""
    ]

    static func apiKey(for kind: ProviderKind) -> String {
        apiKeys[kind] ?? ""
    }

    static func model(for kind: ProviderKind) -> String {
        kind.defaultModel
    }

    static func endpoint(for kind: ProviderKind) -> URL {
        kind.defaultEndpoint
    }
}
