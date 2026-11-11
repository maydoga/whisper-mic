import AppKit
import ApplicationServices

/// Where a window should end up. `restore` puts it back where it was before the
/// first time Hulpje moved it.
enum WindowSlot: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, restore

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        }
    }
}

/// Moves the focused window of the frontmost app through the Accessibility API.
///
/// Two coordinate systems meet here. Cocoa (`NSScreen`) puts the origin at the
/// bottom-left of the primary display with y growing upwards; the Accessibility API
/// puts it at the top-left with y growing downwards. `flip` converts either way.
enum WindowManager {
    /// Frames captured the first time a window was moved, so `restore` has something
    /// to go back to. Bounded, because windows close and we never hear about it.
    private static var originalFrames: [(element: AXUIElement, frame: CGRect)] = []
    private static let maxRemembered = 24

    @discardableResult
    static func move(to slot: WindowSlot) -> Bool {
        guard Accessibility.isTrusted else {
            NSLog("[Hulpje] window move aborted, no Accessibility permission")
            return false
        }
        guard let window = focusedWindow() else { return false }
        NSLog("[Hulpje] window %@ for %@", slot.rawValue, appName(of: window))

        if slot == .restore {
            guard let original = rememberedFrame(for: window) else { return false }
            forget(window)
            guard isNativeFullScreen(window) else { return setFrame(original, on: window) }
            leaveNativeFullScreen(window)
            afterFullScreenExit(of: window) { setFrame(original, on: window) }
            return true
        }

        // A window in native full screen covers the whole display and ignores every
        // position and size we set. Its frame is also worthless as a restore point.
        // So: ask it to leave, wait for the animation, and only then read the frame
        // and place the window.
        if isNativeFullScreen(window) {
            leaveNativeFullScreen(window)
            afterFullScreenExit(of: window) {
                guard let current = frame(of: window) else { return }
                remember(window, frame: current)
                place(window, in: slot, from: current)
            }
            return true
        }

        guard let current = frame(of: window) else {
            NSLog("[Hulpje] window frame unreadable for %@", appName(of: window))
            return false
        }
        remember(window, frame: current)
        return place(window, in: slot, from: current)
    }

    @discardableResult
    private static func place(_ window: AXUIElement, in slot: WindowSlot, from current: CGRect) -> Bool {
        let cocoaCurrent = flip(current)
        let area = screen(containing: cocoaCurrent).visibleFrame
        let target = frame(for: slot, in: area, current: cocoaCurrent)
        return setFrame(flip(target), on: window)
    }

    // MARK: - Geometry

    private static func frame(for slot: WindowSlot, in area: CGRect, current: CGRect) -> CGRect {
        switch slot {
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .rightHalf:
            return CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .topHalf:
            return CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        case .bottomHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .maximize:
            return area
        case .center:
            let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
            return CGRect(
                x: area.midX - size.width / 2,
                y: area.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .restore:
            return current
        }
    }

    /// The display the window mostly lives on, by its centre point. Falls back to
    /// the screen with the keyboard focus when the window sits nowhere sensible.
    private static func screen(containing rect: CGRect) -> NSScreen {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(centre) }) { return hit }
        if let overlapping = NSScreen.screens.max(by: { a, b in
            a.frame.intersection(rect).area < b.frame.intersection(rect).area
        }), overlapping.frame.intersects(rect) {
            return overlapping
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Converts between Cocoa and Accessibility coordinates. The transform is its
    /// own inverse, so one function covers both directions.
    private static func flip(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Accessibility plumbing

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Focused first, then main, then the front-most of all its windows. Finder
        // answers "focused window" with its desktop, one window spanning every
        // display, even while a normal Finder window has the focus. Moving that does
        // nothing, so anything that is not an ordinary window is passed over.
        var candidates: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, attribute as CFString, &value)
            if result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                candidates.append(value as! AXUIElement)
            }
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement] {
            candidates.append(contentsOf: list)
        }

        if let window = candidates.first(where: isOrdinaryWindow) { return window }
        NSLog("[Hulpje] no focused window for %@ (%d candidates, none ordinary)",
              app.localizedName ?? "?", candidates.count)
        return nil
    }

    /// A window someone would tile: a standard window, or failing a subrole, one that
    /// fits on a single display. Finder's desktop is neither.
    private static func isOrdinaryWindow(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        if (subrole as? String) == (kAXStandardWindowSubrole as String) { return true }

        guard let rect = frame(of: window) else { return false }
        let cocoa = flip(rect)
        let fitsOneScreen = NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(cocoa) }
        if !fitsOneScreen || subrole == nil {
            NSLog("[Hulpje] skipped window %@ subrole %@", NSStringFromRect(rect), (subrole as? String) ?? "none")
            return false
        }
        return true
    }

    private static func appName(of window: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Position, then size, then position again: apps that clamp the size while the
    /// window still sits on the old screen end up in the wrong place otherwise.
    ///
    /// An app with `AXEnhancedUserInterface` switched on (set by assistive tools that
    /// watch other apps) animates every change and drops the ones that arrive while
    /// it is still moving, so it is switched off for the move and restored after.
    /// The frame is read back: an app that answers "success" and then ignores the
    /// size gets one more attempt, size first, and the outcome lands in the log.
    @discardableResult
    private static func setFrame(_ rect: CGRect, on window: AXUIElement) -> Bool {
        var origin = rect.origin
        var size = rect.size

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let axApp = AXUIElementCreateApplication(pid)
        let enhanced = enhancedUserInterface(of: axApp)
        if enhanced { setEnhancedUserInterface(false, on: axApp) }
        defer { if enhanced { setEnhancedUserInterface(true, on: axApp) } }

        let before = frame(of: window)
        let positioned = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        var after = frame(of: window)
        if let landed = after, !landed.isClose(to: rect) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            after = frame(of: window)
        }

        NSLog(
            "[Hulpje] window %@ from %@ to %@ landed %@ (position %d, size %d, enhancedUI %d)",
            appName(of: window),
            before.map { NSStringFromRect($0) } ?? "?",
            NSStringFromRect(rect),
            after.map { NSStringFromRect($0) } ?? "?",
            positioned.rawValue, result.rawValue, enhanced ? 1 : 0
        )
        if result != .success {
            NSLog("[Hulpje] window resize refused, error %d", result.rawValue)
        }
        return result == .success
    }

    private static func enhancedUserInterface(of app: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    private static func setEnhancedUserInterface(_ on: Bool, on app: AXUIElement) {
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private static func isNativeFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    /// A window in native full screen ignores position and size. Ask it to leave
    /// first; apps that do not support the attribute simply refuse.
    private static func leaveNativeFullScreen(_ window: AXUIElement) {
        guard isNativeFullScreen(window) else { return }
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
    }

    /// Leaving full screen is animated and takes the better part of a second. The
    /// attribute flips immediately, the window keeps moving after, so we poll until
    /// it reports out and then let the animation settle. Bounded: an app that never
    /// leaves gets one last attempt rather than an endless timer.
    private static func afterFullScreenExit(
        of window: AXUIElement,
        attempt: Int = 0,
        then body: @escaping () -> Void
    ) {
        let maxAttempts = 30      // 30 x 0.05s = 1.5s
        let settle: TimeInterval = 0.12

        guard isNativeFullScreen(window), attempt < maxAttempts else {
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { body() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            afterFullScreenExit(of: window, attempt: attempt + 1, then: body)
        }
    }

    // MARK: - Restore bookkeeping

    private static func remember(_ window: AXUIElement, frame: CGRect) {
        guard rememberedFrame(for: window) == nil else { return }
        originalFrames.append((window, frame))
        if originalFrames.count > maxRemembered { originalFrames.removeFirst() }
    }

    private static func rememberedFrame(for window: AXUIElement) -> CGRect? {
        originalFrames.first { CFEqual($0.element, window) }?.frame
    }

    private static func forget(_ window: AXUIElement) {
        originalFrames.removeAll { CFEqual($0.element, window) }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }

    /// Within a couple of points: apps round to their own grid.
    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
