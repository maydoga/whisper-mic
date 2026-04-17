import ServiceManagement
import Foundation

enum LaunchAtLoginHelper {
    /// Whether launch at login is currently enabled
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: "launchAtLogin")
    }

    /// Toggle launch at login on/off
    static func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    /// Register as a login item
    static func enable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "launchAtLogin")
            } catch {
                print("Failed to enable launch at login: \(error)")
            }
        } else {
            UserDefaults.standard.set(true, forKey: "launchAtLogin")
        }
    }

    /// Unregister as a login item
    static func disable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                UserDefaults.standard.set(false, forKey: "launchAtLogin")
            } catch {
                print("Failed to disable launch at login: \(error)")
            }
        } else {
            UserDefaults.standard.set(false, forKey: "launchAtLogin")
        }
    }
}
