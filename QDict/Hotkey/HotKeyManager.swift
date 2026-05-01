import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's `RegisterEventHotKey`. The C event handler dereferences a raw pointer
/// to `self`, so this manager MUST outlive any registered combo. `AppContainer` holds it
/// for the full app lifetime; do not recreate it. `deinit` calls `unregister()` to cover
/// any future restructuring, but if registration ever moves to a non-singleton owner,
/// switch `passUnretained` to `passRetained` + matching `release` in `deinit`.
final class HotKeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handlerID: UInt32 = 0xDDDD0001

    /// Called on the main thread when the hotkey fires.
    var onPress: (() -> Void)?

    deinit { unregister() }

    /// Registers the given combo. Returns `true` on success, `false` if the system rejects it.
    @discardableResult
    func register(_ combo: HotkeyCombo) -> Bool {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(0x4458_4C54), id: handlerID) // "DXLT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref = ref else { return false }
        self.hotKeyRef = ref

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onPress?() }
                return noErr
            },
            1,
            &spec,
            userData,
            &eventHandler
        )
        if handlerStatus != noErr {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
