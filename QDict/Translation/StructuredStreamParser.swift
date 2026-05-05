import Foundation

/// Incremental line-scanner for the dictionary prompt's prefix-line output.
///
/// Feed token chunks via `feed(_:)`; the parser splits on `\n`, identifies each
/// complete line by its prefix, and updates the cumulative `result`. Call
/// `flush()` once the stream ends to consume any trailing line without `\n`.
///
/// Pure value type. No locking, no main-actor assumption — callers serialize
/// access however they need.
struct StructuredStreamParser {
    static let separator = "|||"

    private(set) var result = DictionaryResult()
    private var buffer = ""
    private var currentSenseIndex: Int? = nil

    @discardableResult
    mutating func feed(_ chunk: String) -> DictionaryResult {
        buffer += chunk
        while let nlRange = buffer.range(of: "\n") {
            let line = String(buffer[..<nlRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<nlRange.upperBound)
            consume(line: line)
        }
        return result
    }

    @discardableResult
    mutating func flush() -> DictionaryResult {
        if !buffer.isEmpty {
            consume(line: buffer)
            buffer = ""
        }
        return result
    }

    private mutating func consume(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed.components(separatedBy: Self.separator)
        guard parts.count >= 2 else { return }
        let prefix = parts[0]
        switch prefix {
        case "WORD" where parts.count == 2:
            result.word = parts[1]
        case "IPA" where parts.count == 2:
            result.ipa = parts[1]
        case "TRANS" where parts.count == 2:
            result.primaryTranslation = parts[1]
        case "POS" where parts.count == 2:
            result.primaryPOS = parts[1]
        case "USAGE" where parts.count == 2:
            result.usage = parts[1]
        default:
            return
        }
    }
}
