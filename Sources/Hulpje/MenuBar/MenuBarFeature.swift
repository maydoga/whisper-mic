import AppKit

/// Collapses the third-party icons in the menu bar, the way Ice, Dozer and Bartender do.
///
/// The mechanism is a status item trick, no private API: two items are added, a wide
/// `separator` and a `toggle` chevron to its right. Collapsing sets the separator's
/// width to something absurd, which pushes every status item to its left out of the
/// visible strip. Expanding shrinks it back. Only items sitting left of the separator
/// are affected, so the ordering is arranged once by ⌘-dragging the icons.
///
/// Apple's own items (Control Center, Wi-Fi, battery, clock) live in a region third
/// party apps cannot reach, and stay put.
@MainActor
final class MenuBarFeature: NSObject, Feature {
    let name = "MenuBar"

    /// Wider than any menu bar; the system clamps it to the space actually available.
    private static let collapsedWidth: CGFloat = 10_000
    private static let expandedWidth: CGFloat = 12

    private var separator: NSStatusItem?
    private var toggle: NSStatusItem?
    private var mouseMonitors: [Any] = []
    private var collapseTimer: Timer?

    private var isCollapsed = false

    /// Off until asked for: running this next to Ice means two apps fighting over the
    /// same strip of menu bar.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { setEnabled(newValue) }
    }

    /// Collapse by itself after a quiet moment, and reveal on hover. Without this the
    /// chevron has to be clicked every time.
    var autoHide: Bool {
        get { UserDefaults.standard.object(forKey: "feature.MenuBar.autoHide") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.MenuBar.autoHide")
            if newValue { installMouseMonitors(); scheduleCollapse() }
            else { removeMouseMonitors(); collapseTimer?.invalidate() }
        }
    }

    var autoHideDelay: TimeInterval {
        get { UserDefaults.standard.object(forKey: "feature.MenuBar.delay") as? Double ?? 8 }
        set { UserDefaults.standard.set(newValue, forKey: "feature.MenuBar.delay") }
    }

    func start() {
        guard isEnabled, separator == nil else { return }

        seedPositionsOnFirstRun()

        // Creation order is placement order: each new item lands to the left of the
        // previous one, so the toggle must exist before the separator that hides things.
        let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = "hulpje.menubar.toggle"
        toggle.button?.target = self
        toggle.button?.action = #selector(toggleCollapsed)
        self.toggle = toggle

        let separator = NSStatusBar.system.statusItem(withLength: Self.expandedWidth)
        separator.autosaveName = "hulpje.menubar.separator"
        separator.button?.image = Self.dividerImage()
        separator.button?.target = self
        separator.button?.action = #selector(expand)
        self.separator = separator

        isCollapsed = false
        updateIcons()

        if autoHide {
            installMouseMonitors()
            scheduleCollapse()
        }
    }

    func stop() {
        collapseTimer?.invalidate()
        removeMouseMonitors()
        [separator, toggle].compactMap { $0 }.forEach(NSStatusBar.system.removeStatusItem)
        separator = nil
        toggle = nil
        isCollapsed = false
    }

    func addMenuItems(to menu: NSMenu) {
        let submenu = NSMenu()

        submenu.addItem(
            "Hide Icons",
            target: self,
            action: #selector(toggleEnabled),
            state: isEnabled ? .on : .off
        )

        if isEnabled {
            submenu.addItem(
                isCollapsed ? "Show Icons Now" : "Hide Icons Now",
                target: self,
                action: #selector(toggleCollapsed)
            )
            submenu.addItem(NSMenuItem.separator())
            submenu.addItem(
                "Hide Automatically",
                target: self,
                action: #selector(toggleAutoHide),
                state: autoHide ? .on : .off
            )
            if autoHide {
                let delays = NSMenu()
                for seconds in [3.0, 5.0, 8.0, 15.0, 30.0] {
                    delays.addItem(
                        "\(Int(seconds)) seconds",
                        target: self,
                        action: #selector(setDelay(_:)),
                        state: seconds == autoHideDelay ? .on : .off,
                        represented: seconds
                    )
                }
                let delayItem = NSMenuItem(title: "Hide After", action: nil, keyEquivalent: "")
                delayItem.submenu = delays
                submenu.addItem(delayItem)
            }
            submenu.addItem(NSMenuItem.separator())
            submenu.addCaption("⌘-drag icons left of the divider to hide them")
        }

        let item = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    // MARK: - Collapsing

    private func setCollapsed(_ collapsed: Bool) {
        guard let separator, isCollapsed != collapsed else { return }
        isCollapsed = collapsed
        separator.length = collapsed ? Self.collapsedWidth : Self.expandedWidth
        separator.button?.image = collapsed ? nil : Self.dividerImage()
        updateIcons()
        if !collapsed { scheduleCollapse() }
    }

    private func updateIcons() {
        let symbol = isCollapsed ? "chevron.right" : "chevron.left"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        toggle?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Menu bar icons")?
            .withSymbolConfiguration(config)
    }

    private func scheduleCollapse() {
        collapseTimer?.invalidate()
        guard isEnabled, autoHide, !isCollapsed else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPointerInMenuBar() else { return }
                self.setCollapsed(true)
            }
        }
    }

    // MARK: - Hover

    /// A global monitor needs Accessibility, which Hulpje already holds for pasting
    /// and for moving windows. The local monitor covers the moments the app is active.
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        })
        if let global { mouseMonitors.append(global) }

        let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            Task { @MainActor in self?.pointerMoved() }
            return event
        })
        if let local { mouseMonitors.append(local) }
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
    }

    private func pointerMoved() {
        guard isEnabled, autoHide else { return }
        if isPointerInMenuBar() {
            setCollapsed(false)
        } else if !isCollapsed {
            scheduleCollapse()
        }
    }

    /// The menu bar is the strip between the top of the screen and the top of its
    /// visible frame. Computed per screen, because only one of them may have a dock.
    private func isPointerInMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return point.y >= screen.frame.maxY - menuBarHeight
    }

    // MARK: - Actions

    @objc private func toggleCollapsed() {
        setCollapsed(!isCollapsed)
    }

    @objc private func expand() {
        setCollapsed(false)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func toggleAutoHide() {
        autoHide.toggle()
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        autoHideDelay = seconds
        scheduleCollapse()
    }

    /// Without this the divider lands at the far left of the status area on first run,
    /// with nothing to its left to hide, and the feature looks broken until the user
    /// discovers ⌘-dragging. AppKit reads the placement of an autosaved status item from
    /// this key in the app's own defaults; the value is an offset in points from the
    /// right edge of the third-party area, so 0 is as far right as we can ask for.
    /// Seeded once — after that the user's own dragging owns the positions.
    private func seedPositionsOnFirstRun() {
        let defaults = UserDefaults.standard
        let toggleKey = "NSStatusItem Preferred Position hulpje.menubar.toggle"
        let separatorKey = "NSStatusItem Preferred Position hulpje.menubar.separator"
        guard defaults.object(forKey: toggleKey) == nil, defaults.object(forKey: separatorKey) == nil else { return }
        defaults.set(0, forKey: toggleKey)
        defaults.set(Self.expandedWidth + 4, forKey: separatorKey)
    }

    /// A thin vertical rule, drawn as a template so it follows light and dark menu bars.
    private static func dividerImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 3, height: 13), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 1, y: 0, width: 1, height: rect.height),
                xRadius: 0.5,
                yRadius: 0.5
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
