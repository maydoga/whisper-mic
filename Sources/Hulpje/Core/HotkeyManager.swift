import Carbon.HIToolbox
import Cocoa

/// System-wide shortcuts. One Carbon event handler dispatches to every registered
/// hotkey by id, so features can claim and release their own shortcuts freely.
///
/// Registration fails with `eventHotKeyExistsErr` when another running app already
/// owns the combination. That is not a crash but it is invisible, so failures are
/// remembered and surfaced in the menu.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    struct Registration {
        let id: UInt32
        let hotkey: Hotkey
        let ref: EventHotKeyRef?
        let action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// Hotkeys another app is already holding. Keyed by the label the caller gave.
    private(set) var conflicts: [String: Hotkey] = [:]

    private init() {}

    /// Claims `hotkey`. Returns a token for `unregister`, or nil when the shortcut
    /// is taken. `label` names the action in conflict reporting.
    @discardableResult
    func register(_ hotkey: Hotkey, label: String, action: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x48554C50), id: id) // "HULP"
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            conflicts[label] = hotkey
            NSLog("[Hulpje] hotkey %@ (%@) unavailable, status %d", hotkey.display, label, status)
            return nil
        }

        conflicts[label] = nil
        registrations[id] = Registration(id: id, hotkey: hotkey, ref: ref, action: action)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        if let ref = registration.ref { UnregisterEventHotKey(ref) }
    }

    func unregisterAll(_ ids: [UInt32]) {
        ids.forEach(unregister)
    }

    /// Forgets remembered conflicts for the given labels, so a retry starts clean.
    func clearConflicts(labels: [String]) {
        for label in labels { conflicts[label] = nil }
    }

    fileprivate func fire(id: UInt32) {
        registrations[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotkeyManager.shared.fire(id: id) }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }
}
