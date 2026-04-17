import Cocoa
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let hotkeyManager = HotkeyManager()
    private let toast = ToastOverlay()

    // Settings
    private var language = UserDefaults.standard.string(forKey: "language") ?? "auto"
    private var autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true

    /// The app that was active when the user started recording — paste target.
    private var previousApp: NSRunningApplication?
    private var isTranscribing = false

    private let ownBundleID = Bundle.main.bundleIdentifier

    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioRecorder.cleanupTempFiles()
        // Fire the system Accessibility prompt on first launch; no-op afterwards.
        PasteHelper.requestAccessibility()
        setupStatusItem()
        hotkeyManager.register { [weak self] in
            self?.toggleRecording()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon()
        buildMenu()
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = PasteHelper.isAccessibilityTrusted ? "mic" : "mic.slash"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WhisperMic") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusTitle = recorder.isRecording ? "Recording..." : "Ready"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        if !PasteHelper.isAccessibilityTrusted {
            menu.addItem(NSMenuItem.separator())
            let axItem = NSMenuItem(
                title: "⚠ Grant Accessibility Access…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            axItem.target = self
            menu.addItem(axItem)
        }

        menu.addItem(NSMenuItem.separator())

        let recordTitle = recorder.isRecording ? "Stop Recording" : "Start Recording"
        let recordItem = NSMenuItem(title: recordTitle, action: #selector(toggleRecordingAction), keyEquivalent: " ")
        recordItem.keyEquivalentModifierMask = [.control, .option, .command]
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(NSMenuItem.separator())

        // Language submenu
        let langItem = NSMenuItem(title: "Language: \(languageDisplayName(language))", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (code, name) in [("auto", "Auto-detect"), ("nl", "Nederlands"), ("en", "English"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("tr", "Türkçe")] {
            let item = NSMenuItem(title: name, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            if code == language { item.state = .on }
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // Auto-paste toggle
        let pasteItem = NSMenuItem(title: "Auto-Paste", action: #selector(toggleAutoPaste), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.state = autoPaste ? .on : .off
        menu.addItem(pasteItem)

        // Launch at Login toggle
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAtLoginHelper.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit WhisperMic", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        updateStatusItemIcon()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Rebuild so the Accessibility state and icon reflect live permission changes.
        buildMenu()
    }

    @objc private func toggleRecordingAction() {
        toggleRecording()
    }

    @objc private func openAccessibilitySettings() {
        PasteHelper.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// The frontmost non-WhisperMic app — the paste target.
    private func resolvePasteTarget() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front = front, front.bundleIdentifier != ownBundleID {
            return front
        }
        return previousApp
    }

    private func startRecording() {
        guard !isTranscribing else {
            toast.showError("Still transcribing...")
            return
        }

        guard KeychainHelper.getOpenAIKey() != nil else {
            toast.showError("No API key — set in Keychain")
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        if let front = front, front.bundleIdentifier != ownBundleID {
            previousApp = front
        }

        do {
            try recorder.startRecording()
        } catch {
            toast.showError("Mic error")
            return
        }

        toast.showRecording()
        buildMenu()
    }

    private func stopRecording() {
        guard let audioURL = recorder.stopRecording() else {
            toast.hide()
            buildMenu()
            return
        }

        toast.showTranscribing()
        isTranscribing = true
        buildMenu()

        Task {
            do {
                let transcript = try await TranscriptionService.transcribe(fileURL: audioURL, language: language)

                await MainActor.run {
                    isTranscribing = false
                    PasteHelper.copyToClipboard(transcript)

                    guard autoPaste else {
                        toast.showSuccess()
                        buildMenu()
                        return
                    }

                    guard PasteHelper.isAccessibilityTrusted else {
                        toast.showError("Grant Accessibility to enable paste")
                        buildMenu()
                        return
                    }

                    let target = resolvePasteTarget()
                    target?.activate()
                    // Give the activation time to land before posting Cmd+V.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                        PasteHelper.simulatePaste()
                        self?.toast.showSuccess()
                    }
                    buildMenu()
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    toast.showError("Transcription failed")
                    buildMenu()
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }
        }
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        language = code
        UserDefaults.standard.set(code, forKey: "language")
        buildMenu()
    }

    @objc private func toggleAutoPaste() {
        autoPaste.toggle()
        UserDefaults.standard.set(autoPaste, forKey: "autoPaste")
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginHelper.toggle()
        buildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func languageDisplayName(_ code: String) -> String {
        let map = ["auto": "Auto-detect", "nl": "Nederlands", "en": "English", "de": "Deutsch", "fr": "Français", "es": "Español", "tr": "Türkçe"]
        return map[code] ?? code
    }
}

@main
enum WhisperMicEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
