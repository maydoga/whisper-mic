import AppKit

/// One capability of Hulpje. A feature owns its hotkeys and its slice of the status
/// menu; the app only switches it on and off. Adding something new to Hulpje means
/// writing one of these and appending it to `AppDelegate.features`.
@MainActor
protocol Feature: AnyObject {
    /// Human-readable, also the UserDefaults namespace for this feature.
    var name: String { get }

    /// Features can be switched off individually — useful while the app they replace
    /// is still installed and holding the same hotkeys.
    var isEnabled: Bool { get set }

    /// Claim hotkeys, install observers, show extra status items.
    func start()

    /// Release everything `start()` claimed.
    func stop()

    /// Append this feature's items to the status menu. Called on every menu open,
    /// so it may read live state.
    func addMenuItems(to menu: NSMenu)
}

extension Feature {
    var enabledKey: String { "feature.\(name).enabled" }

    /// Defaults to on. A feature that should stay dormant until asked for
    /// overrides `isEnabled` with its own key.
    var isEnabledByDefault: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled { start() } else { stop() }
    }
}

/// Menu helper: an item wired to a target/action in one line.
extension NSMenu {
    @discardableResult
    func addItem(
        _ title: String,
        target: AnyObject?,
        action: Selector?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        state: NSControl.StateValue = .off,
        enabled: Bool = true,
        represented: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        item.state = state
        item.isEnabled = enabled
        item.representedObject = represented
        addItem(item)
        return item
    }

    /// A disabled caption line. Section headers and status readouts.
    func addCaption(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}
