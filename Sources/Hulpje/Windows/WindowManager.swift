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
        guard let current = frame(of: window) else { return false }

        if slot == .restore {
            guard let original = rememberedFrame(for: window) else { return false }
            forget(window)
            return setFrame(original, on: window)
        }

        remember(window, frame: current)
        leaveNativeFullScreen(window)

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
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success
        else {
            NSLog("[Hulpje] no focused window for %@", app.localizedName ?? "?")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
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
    @discardableResult
    private static func setFrame(_ rect: CGRect, on window: AXUIElement) -> Bool {
        var origin = rect.origin
        var size = rect.size

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        if result != .success {
            NSLog("[Hulpje] window resize refused, error %d", result.rawValue)
        }
        return result == .success
    }

    /// A window in native full screen ignores position and size. Ask it to leave
    /// first; apps that do not support the attribute simply refuse.
    private static func leaveNativeFullScreen(_ window: AXUIElement) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success,
              (value as? Bool) == true
        else { return }
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
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
}
