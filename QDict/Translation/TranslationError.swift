import Foundation

enum TranslationError: Error, LocalizedError, Equatable {
    case network(message: String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, body: String?)
    case streamInterrupted(partial: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .network(let m):
            return "网络不可用：\(m)"
        case .unauthorized:
            return "API Key 无效或已过期"
        case .rateLimited:
            return "请求过于频繁，稍后再试"
        case .serverError(let s, _):
            return "服务异常 (HTTP \(s))"
        case .streamInterrupted:
            return "连接中断"
        case .cancelled:
            return "已取消"
        }
    }

    static func == (lhs: TranslationError, rhs: TranslationError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
             (.cancelled, .cancelled):
            return true
        case let (.network(a), .network(b)):
            return a == b
        case let (.rateLimited(a), .rateLimited(b)):
            return a == b
        case let (.serverError(s1, b1), .serverError(s2, b2)):
            return s1 == s2 && b1 == b2
        case let (.streamInterrupted(a), .streamInterrupted(b)):
            return a == b
        default:
            return false
        }
    }
}
