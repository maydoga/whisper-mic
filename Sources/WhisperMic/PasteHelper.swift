import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteHelper {
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility if we're not trusted yet.
    /// The prompt only appears on the first call per TCC identity; later calls
    /// just return the current trust state.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: kCFBooleanTrue!] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Post Cmd+V as a native CGEvent from the WhisperMic process.
    /// `.cghidEventTap` is the lowest-level tap and requires Accessibility
    /// permission — without it the post succeeds but the keystroke is dropped.
    static func simulatePaste() {
        let trusted = AXIsProcessTrusted()
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        NSLog("[WhisperMic] paste attempt ax=%d frontmost=%@", trusted ? 1 : 0, frontBundle)

        guard trusted else {
            NSLog("[WhisperMic] paste aborted — Accessibility permission missing")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
            let up   = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        else {
            NSLog("[WhisperMic] paste failed — could not create CGEvent")
            return
        }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(5_000)
        up.post(tap: .cghidEventTap)
    }
}
