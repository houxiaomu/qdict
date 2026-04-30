import Foundation

enum SSEEvent: Equatable {
    case message(String)
    case done
}

struct SSEParser {
    private var buffer = ""

    /// Feeds a chunk of bytes (decoded as UTF-8) into the parser.
    /// Returns any complete events extracted so far.
    mutating func feed(_ chunk: String) -> [SSEEvent] {
        buffer += chunk
        var events: [SSEEvent] = []
        // SSE separates events by a blank line ("\n\n").
        while let range = buffer.range(of: "\n\n") {
            let raw = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let event = parseEvent(raw) {
                events.append(event)
            }
        }
        return events
    }

    private func parseEvent(_ raw: String) -> SSEEvent? {
        var dataLines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix(":") { continue } // comment
            guard let colon = s.firstIndex(of: ":") else { continue }
            let field = s[s.startIndex..<colon]
            var value = s[s.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
            if field == "data" {
                dataLines.append(String(value))
            }
        }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        if payload == "[DONE]" { return .done }
        return .message(payload)
    }
}
