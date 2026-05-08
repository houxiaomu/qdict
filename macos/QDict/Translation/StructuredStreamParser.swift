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
        // Note: in Swift "\r\n" is a single grapheme cluster, so
        // range(of: "\n") returns nil for CRLF input. Try CRLF first.
        while let nlRange = buffer.range(of: "\r\n") ?? buffer.range(of: "\n") {
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
        case "SENSE" where parts.count == 3:
            result.senses.append(Sense(pos: parts[1], primary: parts[2], definitions: []))
            currentSenseIndex = result.senses.count - 1
        case "DEF" where parts.count == 3:
            guard let n = Int(parts[1]) else { return }
            let def = Definition(n: n, text: parts[2])
            if let idx = currentSenseIndex {
                result.senses[idx].definitions.append(def)
            } else {
                result.flatDefinitions.append(def)
            }
        case "EX" where parts.count == 3:
            result.examples.append(Example(source: parts[1], translation: parts[2]))
        case "SYN" where parts.count == 2:
            result.synonyms = parts[1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        default:
            return
        }
    }
}
