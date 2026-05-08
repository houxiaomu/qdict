import SwiftUI
import AppKit

struct HotkeyRecorderView: View {
    @Binding var combo: HotkeyCombo
    let onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(combo.displayString)
                .frame(width: 120, alignment: .leading)
                .padding(6)
                .background(recording ? Color.accentColor.opacity(0.2) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.3)))
            Button(recording ? "Press keys…" : "Record") {
                if recording { stopRecording() } else { startRecording() }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = carbonMods(from: event.modifierFlags)
            let key = UInt32(event.keyCode)
            // Reject if no modifier — single keys are not safe as global hotkeys.
            if mods == 0 { return event }
            let newCombo = HotkeyCombo(keyCode: key, modifiers: mods)
            DispatchQueue.main.async {
                self.combo = newCombo
                self.stopRecording()
                self.onChange()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= 1 << 8 }
        if flags.contains(.shift)    { m |= 1 << 9 }
        if flags.contains(.option)   { m |= 1 << 11 }
        if flags.contains(.control)  { m |= 1 << 12 }
        return m
    }
}
