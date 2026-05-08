import AppKit

extension NSEvent.ModifierFlags {
    /// The four "real" user-pressed modifier bits relevant to shortcut
    /// matching. macOS additionally sets ``.function`` on every arrow-key
    /// keyDown and ``.numericPad`` on some keyboards; ``.capsLock`` and
    /// ``.help`` are sticky/special. Stripping all of those before comparing
    /// against ``.command``, ``.empty``, etc. avoids silent shortcut misses.
    ///
    /// **Background:** in 1.0.2 we shipped a key router that did
    /// ``mods.subtracting(.numericPad)`` and then compared against ``.empty``
    /// for plain ↑/↓. macOS routinely tags arrow-key events with
    /// ``.function`` (= ``1 << 23``); the comparison silently failed and
    /// arrow keys never moved selection inside the suggestion dropdown.
    /// Whitelisting beats blacklisting here.
    static let userPressedSubset: NSEvent.ModifierFlags = [
        .shift, .control, .option, .command,
    ]

    /// Returns only the modifier bits that represent keys the user
    /// physically pressed (shift / control / option / command). All other
    /// flags — including ``.function``, ``.numericPad``, ``.capsLock``,
    /// ``.help`` — are stripped.
    var userPressedOnly: NSEvent.ModifierFlags {
        intersection(.userPressedSubset)
    }
}
