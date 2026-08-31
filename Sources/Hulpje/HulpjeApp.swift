import Cocoa

/// Hulpje is a menu bar app that collects the small macOS conveniences worth having:
/// dictation, window tiling, a tidier menu bar. Each of those is a `Feature`; this
/// delegate owns the status item and hands the menu around.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    private lazy var dictation = DictationFeature(refresh: { [weak self] in self?.buildMenu() })
    private lazy var windows = WindowFeature()
    private lazy var menuBar = MenuBarFeature()

    /// Order here is the order in the menu.
    private lazy var features: [Feature] = [dictation, windows, menuBar]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fires the system Accessibility prompt on first launch; no-op afterwards.
        Accessibility.request()
        setupStatusItem()
        features.forEach { $0.start() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(systemSymbolName: dictation.statusSymbol, accessibilityDescription: "Hulpje")?
            .withSymbolConfiguration(config)
    }

    private func buildMenu() {
        let menu = NSMenu()
        // Items carry their own enabled state; AppKit would otherwise recompute it.
        menu.autoenablesItems = false

        menu.addCaption(dictation.statusLine)

        if !Accessibility.isTrusted {
            menu.addItem(NSMenuItem.separator())
            menu.addItem("⚠ Grant Accessibility Access…", target: self, action: #selector(openAccessibilitySettings))
        }

        menu.addItem(NSMenuItem.separator())
        for feature in features {
            feature.addMenuItems(to: menu)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            "Launch at Login",
            target: self,
            action: #selector(toggleLaunchAtLogin),
            state: LaunchAtLoginHelper.isEnabled ? .on : .off
        )
        menu.addItem("Quit Hulpje", target: self, action: #selector(quitApp), keyEquivalent: "q", modifiers: [.command])

        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Rebuild so Accessibility state, the icon and the retry list reflect live changes.
        buildMenu()
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginHelper.toggle()
        buildMenu()
    }

    @objc private func quitApp() {
        features.forEach { $0.stop() }
        NSApplication.shared.terminate(nil)
    }
}

@main
enum HulpjeEntry {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
