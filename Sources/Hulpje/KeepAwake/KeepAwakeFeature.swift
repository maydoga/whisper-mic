import AppKit
import IOKit.pwr_mgt

/// Amphetamine's one job, without the timers: while this is on, neither the Mac nor
/// the display goes to sleep. No duration. On stays on, across restarts, until it is
/// switched off in the menu.
///
/// Two power assertions do the work, the same ones `caffeinate -di` takes. The display
/// one also keeps the screen saver, and the lock that follows it, from starting.
///
/// Closing the lid still sleeps the Mac. That is a separate path in the power manager
/// which no assertion holds back; it takes root (`pmset disablesleep`).
@MainActor
final class KeepAwakeFeature: NSObject, Feature {
    let name = "KeepAwake"

    private static let assertionTypes = [
        "PreventUserIdleDisplaySleep",
        "PreventUserIdleSystemSleep",
    ]

    private var assertionIDs: [IOPMAssertionID] = []

    var isEnabled: Bool {
        get { isEnabledByDefault }
        set { setEnabled(newValue) }
    }

    func start() {
        guard isEnabled, assertionIDs.isEmpty else { return }
        for type in Self.assertionTypes {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Hulpje: Keep Awake" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionIDs.append(id)
            } else {
                NSLog("Hulpje: Keep Awake could not take \(type) (\(result))")
            }
        }
    }

    func stop() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    func addMenuItems(to menu: NSMenu) {
        menu.addItem(
            "Keep Awake",
            target: self,
            action: #selector(toggleEnabled),
            state: isEnabled ? .on : .off
        )

        if isEnabled, isAmphetamineRunning {
            menu.addItem("Quit Amphetamine", target: self, action: #selector(quitAmphetamine))
        }
    }

    // MARK: - Amphetamine

    private static let amphetamineBundleID = "com.if.Amphetamine"

    private var isAmphetamineRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.amphetamineBundleID).isEmpty
    }

    @objc private func quitAmphetamine() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.amphetamineBundleID)
            .forEach { $0.terminate() }
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }
}
