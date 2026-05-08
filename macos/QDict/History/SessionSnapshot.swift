import Foundation

/// State captured when the panel is softly hidden (click-outside / Cmd+Tab).
/// Used to restore content if the user re-summons the panel within
/// `freshnessWindow` seconds.
struct SessionSnapshot: Equatable {
    static let freshnessWindow: TimeInterval = 300 // 5 minutes

    let input: String
    let state: TranslatorViewModel.State
    let capturedAt: Date

    func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(capturedAt) <= Self.freshnessWindow
    }

    /// Returns `nil` if there is nothing meaningful to restore.
    /// Empty input + idle state = no snapshot worth keeping.
    static func makeIfWorthCapturing(
        input: String,
        state: TranslatorViewModel.State,
        now: Date = Date()
    ) -> SessionSnapshot? {
        let hasInput = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasResult: Bool = {
            switch state {
            case .idle: return false
            case .streaming, .done, .error: return true
            }
        }()
        guard hasInput || hasResult else { return nil }
        return SessionSnapshot(input: input, state: state, capturedAt: now)
    }
}
