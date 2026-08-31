import Carbon.HIToolbox
import AppKit

/// A global shortcut, in Carbon terms because that is what `RegisterEventHotKey` speaks.
struct Hotkey: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        self.modifiers = carbon
    }

    /// e.g. "⌘⌥←" — for the menu, where the real key equivalent would steal the
    /// shortcut from the global hotkey while the menu is open.
    var display: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + Hotkey.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_Z: return "Z"
        default: return "key \(code)"
        }
    }
}
