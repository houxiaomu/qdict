import Foundation

struct BuiltPrompt: Equatable {
    let mode: Mode
    let direction: Direction
    let systemPrompt: String
}

enum PromptBuilder {

    // Sentence-end punctuation in CJK + Latin scripts.
    private static let sentenceEndingChars: Set<Character> = [
        ".", "!", "?", "。", "！", "？"
    ]

    /// Decide whether the input is a "lookup" (single word / short phrase / idiom)
    /// or a "sentence to translate".
    static func classify(_ raw: String) -> Mode {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .translation }

        // 1. sentence-ending punctuation → always treat as a sentence.
        if trimmed.contains(where: { sentenceEndingChars.contains($0) }) {
            return .translation
        }

        let cjkCount = trimmed.unicodeScalars.filter { isCJK($0) }.count
        let totalScalars = trimmed.unicodeScalars.count

        if cjkCount > 0 {
            // Chinese path. Count CJK chars only; ignore spaces & non-CJK punctuation.
            return cjkCount <= 6 ? .dictionary : .translation
        }

        // English path. Collapse whitespace and split.
        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace })
        // Pure-digit / pure-symbol input: route to translation mode (LLM handles it).
        let hasLetter = collapsed.contains { word in
            word.contains(where: { $0.isLetter })
        }
        guard hasLetter else { return .translation }

        return collapsed.count <= 3 ? .dictionary : .translation
    }

    /// Decide which way the translation should go.
    /// `> 30%` CJK characters → Chinese-to-English; otherwise English-to-Chinese.
    static func detectDirection(_ raw: String) -> Direction {
        let scalars = raw.unicodeScalars
        guard !scalars.isEmpty else { return .enToZh }

        var cjk = 0
        var letterOrCJK = 0
        for s in scalars {
            if isCJK(s) {
                cjk += 1
                letterOrCJK += 1
            } else if let scalar = Unicode.Scalar(s.value), Character(scalar).isLetter {
                letterOrCJK += 1
            }
        }
        guard letterOrCJK > 0 else { return .enToZh }
        let ratio = Double(cjk) / Double(letterOrCJK)
        return ratio > 0.30 ? .zhToEn : .enToZh
    }

    /// Build the final system prompt by selecting the right template and filling `{{direction}}`.
    static func build(
        text: String,
        dictionaryTemplate: String,
        translationTemplate: String
    ) -> BuiltPrompt {
        let mode = classify(text)
        let direction = detectDirection(text)
        let template = (mode == .dictionary) ? dictionaryTemplate : translationTemplate
        let prompt = template.replacingOccurrences(of: "{{direction}}", with: direction.rawValue)
        return BuiltPrompt(mode: mode, direction: direction, systemPrompt: prompt)
    }

    // MARK: - Private

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,   // CJK Unified Ideographs
             0x3400...0x4DBF,   // Extension A
             0x20000...0x2A6DF, // Extension B
             0x3000...0x303F,   // CJK Symbols and Punctuation
             0xFF00...0xFFEF:   // Halfwidth/Fullwidth
            return true
        default:
            return false
        }
    }
}

extension PromptBuilder {
    /// Loads a template from the app bundle. Throws if the file is missing — that's a packaging bug.
    static func loadTemplate(named name: String, in bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: "txt") else {
            throw NSError(
                domain: "PromptBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing prompt template: \(name).txt"]
            )
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
