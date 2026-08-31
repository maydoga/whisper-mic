import AppKit
import ApplicationServices

/// Almost everything Hulpje does needs Accessibility: posting keystrokes, moving
/// other apps' windows, watching the mouse. One place to ask for it and to check it.
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Fires the system prompt on the first call per TCC identity; later calls just
    /// report the current trust state.
    @discardableResult
    static func request() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: kCFBooleanTrue!] as CFDictionary)
    }

    static func openSettings() {
        request()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
