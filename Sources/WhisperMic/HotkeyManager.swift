import Carbon.HIToolbox
import Cocoa

// Global callback for Carbon hot key events
private var globalHotkeyCallback: (() -> Void)?

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var callback: (() -> Void)?

    func register(callback: @escaping () -> Void) {
        self.callback = callback
        globalHotkeyCallback = callback
        registerCarbonHotKey()
    }

    private func registerCarbonHotKey() {
        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            globalHotkeyCallback?()
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        // Register ⌃+⌥+⌘+Space
        var hotKeyID = EventHotKeyID(signature: OSType(0x574D4943), id: 1) // "WMIC"
        let modifiers: UInt32 = UInt32(cmdKey | optionKey | controlKey)

        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            NSLog("WhisperMic: Hotkey ⌃+⌥+⌘+Space registered successfully")
        } else {
            NSLog("WhisperMic: Failed to register hotkey, status: \(status)")
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}
