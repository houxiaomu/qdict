import AppKit

struct HotkeyCombo: Equatable, Codable {
    /// Virtual key code (e.g. kVK_Space = 49).
    let keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, shiftKey, controlKey).
    let modifiers: UInt32

    static let defaultCombo = HotkeyCombo(keyCode: 49 /* space */, modifiers: 1 << 11 /* optionKey */)

    /// Human-readable label like "⌥Space".
    var displayString: String {
        var s = ""
        if modifiers & (1 << 12) != 0 { s += "⌃" } // controlKey
        if modifiers & (1 << 11) != 0 { s += "⌥" } // optionKey
        if modifiers & (1 << 9)  != 0 { s += "⇧" } // shiftKey
        if modifiers & (1 << 8)  != 0 { s += "⌘" } // cmdKey
        s += keyName(forKeyCode: keyCode)
        return s
    }

    private func keyName(forKeyCode code: UInt32) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        // Letters a-z are 0..0x32 ish; we expose only the names users can record.
        default:
            // For letters, map via UCKeyTranslate at recording time; fallback to raw code.
            return "Key\(code)"
        }
    }
}
