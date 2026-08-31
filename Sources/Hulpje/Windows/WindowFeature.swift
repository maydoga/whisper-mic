import AppKit
import Carbon.HIToolbox

/// Spectacle's shortcuts, kept identical so the muscle memory carries over.
/// Spectacle is unmaintained; this does the same three or four things it was used for.
@MainActor
final class WindowFeature: NSObject, Feature {
    let name = "Windows"

    private static let bindings: [(slot: WindowSlot, hotkey: Hotkey)] = [
        (.leftHalf, Hotkey(kVK_LeftArrow, [.command, .option])),
        (.rightHalf, Hotkey(kVK_RightArrow, [.command, .option])),
        (.topHalf, Hotkey(kVK_UpArrow, [.command, .option])),
        (.bottomHalf, Hotkey(kVK_DownArrow, [.command, .option])),
        (.maximize, Hotkey(kVK_ANSI_F, [.command, .option])),
        (.center, Hotkey(kVK_ANSI_C, [.command, .option])),
        (.restore, Hotkey(kVK_ANSI_Z, [.command, .option])),
    ]

    private var hotkeyIDs: [UInt32] = []

    var isEnabled: Bool {
        get { isEnabledByDefault }
        set { setEnabled(newValue) }
    }

    func start() {
        guard isEnabled, hotkeyIDs.isEmpty else { return }
        HotkeyManager.shared.clearConflicts(labels: Self.bindings.map { conflictLabel($0.slot) })
        for (slot, hotkey) in Self.bindings {
            let id = HotkeyManager.shared.register(hotkey, label: conflictLabel(slot)) {
                WindowManager.move(to: slot)
            }
            if let id { hotkeyIDs.append(id) }
        }
    }

    func stop() {
        HotkeyManager.shared.unregisterAll(hotkeyIDs)
        hotkeyIDs.removeAll()
        HotkeyManager.shared.clearConflicts(labels: Self.bindings.map { conflictLabel($0.slot) })
    }

    /// Re-claiming after another app released the shortcuts, without a restart.
    func retryHotkeys() {
        stop()
        start()
    }

    func addMenuItems(to menu: NSMenu) {
        let submenu = NSMenu()

        for (slot, hotkey) in Self.bindings {
            let taken = HotkeyManager.shared.conflicts[conflictLabel(slot)] != nil
            let suffix = isEnabled ? (taken ? "  (\(hotkey.display) in use)" : "  \(hotkey.display)") : ""
            submenu.addItem(
                slot.title + suffix,
                target: self,
                action: #selector(moveWindow(_:)),
                represented: slot.rawValue
            )
        }

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(
            "Shortcuts Active",
            target: self,
            action: #selector(toggleEnabled),
            state: isEnabled ? .on : .off
        )

        if isEnabled, !conflictingSlots.isEmpty {
            submenu.addItem(NSMenuItem.separator())
            submenu.addCaption("macOS refused \(conflictingSlots.count) shortcut(s)")
            submenu.addItem("Claim Shortcuts Again", target: self, action: #selector(retryHotkeysAction))
        }

        if isEnabled, let rival = runningRival {
            submenu.addItem(NSMenuItem.separator())
            submenu.addCaption("\(rival.name) is running and reacts too")
            submenu.addItem("Quit \(rival.name)", target: self, action: #selector(quitRival), represented: rival.bundleID)
        }

        let item = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    /// Carbon hands the same shortcut to every app that asks for it, so a second
    /// window manager does not show up as a registration failure — both simply fire.
    /// Naming the app that is also listening is more useful than a silent double move.
    private static let rivals: [(bundleID: String, name: String)] = [
        ("com.divisiblebyzero.Spectacle", "Spectacle"),
        ("com.knollsoft.Rectangle", "Rectangle"),
        ("com.crowdcafe.windowmagnet", "Magnet"),
    ]

    private var runningRival: (bundleID: String, name: String)? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.rivals.first { running.contains($0.bundleID) }
    }

    @objc private func quitRival(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleID }
            .forEach { $0.terminate() }
    }

    private var conflictingSlots: [WindowSlot] {
        Self.bindings.map(\.slot).filter { HotkeyManager.shared.conflicts[conflictLabel($0)] != nil }
    }

    private func conflictLabel(_ slot: WindowSlot) -> String { "\(name).\(slot.rawValue)" }

    @objc private func moveWindow(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let slot = WindowSlot(rawValue: raw) else { return }
        // The menu owns the focus while it is open; move once it has closed and the
        // previously frontmost window is focused again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            WindowManager.move(to: slot)
        }
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func retryHotkeysAction() {
        retryHotkeys()
    }
}
