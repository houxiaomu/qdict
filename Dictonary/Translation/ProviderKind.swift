import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case openai
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai:   return "OpenAI"
        case .claude:   return "Claude"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .openai:   return "gpt-4o-mini"
        case .claude:   return "claude-haiku-4-5-20251001"
        }
    }

    var defaultEndpoint: URL {
        switch self {
        case .deepseek: return URL(string: "https://api.deepseek.com/v1/chat/completions")!
        case .openai:   return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .claude:   return URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }
}
