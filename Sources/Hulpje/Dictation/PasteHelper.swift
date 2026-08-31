import AppKit
import Carbon.HIToolbox

enum PasteHelper {
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Post Cmd+V as a native CGEvent from the Hulpje process.
    /// `.cghidEventTap` is the lowest-level tap and requires Accessibility
    /// permission — without it the post succeeds but the keystroke is dropped.
    static func simulatePaste() {
        let trusted = Accessibility.isTrusted
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        NSLog("[Hulpje] paste attempt ax=%d frontmost=%@", trusted ? 1 : 0, frontBundle)

        guard trusted else {
            NSLog("[Hulpje] paste aborted — Accessibility permission missing")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
            let up   = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        else {
            NSLog("[Hulpje] paste failed — could not create CGEvent")
            return
        }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(5_000)
        up.post(tap: .cghidEventTap)
    }
}
