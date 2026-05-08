import Foundation

/// Hardcoded provider configuration. Single source of truth for which provider
/// to call and what credentials to use.
///
/// Keys live in `ProviderSecrets.swift`, which is gitignored so they don't
/// ride along with the public repo. Recreate that file after a fresh clone.
enum ProviderConfig {
    /// Currently-active provider. Change here to test other providers.
    static let active: ProviderKind = .deepseek

    static let apiKeys: [ProviderKind: String] = [
        .deepseek: ProviderSecrets.deepseek,
        .openai:   ProviderSecrets.openai,
        .claude:   ProviderSecrets.claude
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
