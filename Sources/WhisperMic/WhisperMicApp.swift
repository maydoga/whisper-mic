import Cocoa
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Recording keeps running briefly after the hotkey. Transcription models drop
    /// trailing words when the audio ends mid-syllable, which reads as a missing
    /// last sentence.
    private static let tailPadding: TimeInterval = 0.4

    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let hotkeyManager = HotkeyManager()
    private let toast = ToastOverlay()

    // Settings
    private var language = UserDefaults.standard.string(forKey: "language") ?? "auto"
    private var autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
    private var model = UserDefaults.standard.string(forKey: "model")
        .flatMap(TranscriptionModel.init(rawValue:)) ?? .default

    /// The app that was active when the user started recording — paste target.
    private var previousApp: NSRunningApplication?
    private var isTranscribing = false
    /// True during the tail-padding window, so a second hotkey press is ignored.
    private var isStopping = false

    private let ownBundleID = Bundle.main.bundleIdentifier

    func applicationDidFinishLaunching(_ notification: Notification) {
        RecordingStore.cleanupLegacyTempFiles()
        RecordingStore.prune()
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

        let statusTitle = recorder.isRecording ? "Recording..." : (isTranscribing ? "Transcribing..." : "Ready")
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

        addRecordingsSection(to: menu)

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

        // Model submenu
        let modelItem = NSMenuItem(title: "Model: \(model.rawValue)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for candidate in TranscriptionModel.allCases {
            let item = NSMenuItem(title: candidate.displayName, action: #selector(setModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            if candidate == model { item.state = .on }
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

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

    /// Retry and re-run entries for the audio still on disk.
    private func addRecordingsSection(to menu: NSMenu) {
        let recordings = RecordingStore.all()
        guard !recordings.isEmpty else { return }
        let failed = recordings.filter { !$0.isTranscribed }

        menu.addItem(NSMenuItem.separator())

        if let latest = recordings.first {
            let title = latest.isTranscribed
                ? "Retranscribe Last (\(latest.menuLabel))"
                : "Retry Last Recording (\(latest.menuLabel))"
            let item = NSMenuItem(title: title, action: #selector(retryRecording(_:)), keyEquivalent: "r")
            item.keyEquivalentModifierMask = [.command]
            item.target = self
            item.representedObject = latest.url
            item.isEnabled = !isTranscribing && !recorder.isRecording
            menu.addItem(item)
        }

        if failed.count > 1 {
            let failedItem = NSMenuItem(title: "Failed Recordings (\(failed.count))", action: nil, keyEquivalent: "")
            let failedMenu = NSMenu()
            for recording in failed {
                let item = NSMenuItem(title: recording.menuLabel, action: #selector(retryRecording(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = recording.url
                item.isEnabled = !isTranscribing && !recorder.isRecording
                failedMenu.addItem(item)
            }
            failedItem.submenu = failedMenu
            menu.addItem(failedItem)
        }

        let revealItem = NSMenuItem(title: "Reveal Saved Audio in Finder", action: #selector(revealRecordings), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        let discardItem = NSMenuItem(title: "Discard Saved Audio", action: #selector(discardRecordings), keyEquivalent: "")
        discardItem.target = self
        menu.addItem(discardItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Rebuild so the Accessibility state, icon and retry list reflect live changes.
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
        guard !isStopping else { return }
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
            try recorder.startRecording(language: language)
        } catch {
            toast.showError("Mic error")
            return
        }

        toast.showRecording()
        buildMenu()
    }

    private func stopRecording() {
        isStopping = true
        toast.showTranscribing()
        buildMenu()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tailPadding) { [weak self] in
            guard let self = self else { return }
            self.isStopping = false
            guard let recording = self.recorder.stopRecording() else {
                self.toast.hide()
                self.buildMenu()
                return
            }
            self.transcribe(recording)
        }
    }

    /// Single path for a fresh recording and for a retry from the menu. The audio
    /// file is only marked done — and eventually removed — once a transcript arrives.
    private func transcribe(_ recording: Recording) {
        isTranscribing = true
        toast.showTranscribing()
        buildMenu()

        let selectedModel = model

        Task {
            do {
                let transcript = try await TranscriptionService.transcribe(
                    fileURL: recording.url,
                    language: recording.language,
                    model: selectedModel
                )

                await MainActor.run {
                    isTranscribing = false
                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        // Nothing came back — keep the audio so it can be retried.
                        toast.showError("Empty transcript: audio kept, ⌘R to retry")
                        buildMenu()
                        return
                    }
                    RecordingStore.markTranscribed(recording)
                    RecordingStore.prune()
                    deliver(transcript)
                    buildMenu()
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    let failure = error as? TranscriptionError
                    if failure?.isRetryable == false {
                        RecordingStore.delete(recording)
                        toast.showError(failure?.errorDescription ?? "Transcription failed")
                    } else {
                        RecordingStore.prune()
                        toast.showError("Failed: audio kept, ⌘R to retry")
                    }
                    buildMenu()
                }
            }
        }
    }

    /// Clipboard, then paste into whatever app was frontmost.
    private func deliver(_ transcript: String) {
        PasteHelper.copyToClipboard(transcript)

        guard autoPaste else {
            toast.showSuccess()
            return
        }

        guard PasteHelper.isAccessibilityTrusted else {
            toast.showError("Grant Accessibility to enable paste")
            return
        }

        let target = resolvePasteTarget()
        target?.activate()
        // Give the activation time to land before posting Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            PasteHelper.simulatePaste()
            self?.toast.showSuccess()
        }
    }

    @objc private func retryRecording(_ sender: NSMenuItem) {
        guard !isTranscribing, !recorder.isRecording,
              let url = sender.representedObject as? URL,
              let recording = Recording(url: url) else { return }
        // Retry pastes where you are now, not where you were when you recorded.
        previousApp = resolvePasteTarget()
        transcribe(recording)
    }

    @objc private func revealRecordings() {
        NSWorkspace.shared.activateFileViewerSelecting(RecordingStore.all().map(\.url))
    }

    @objc private func discardRecordings() {
        RecordingStore.discardAll()
        buildMenu()
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        language = code
        UserDefaults.standard.set(code, forKey: "language")
        buildMenu()
    }

    @objc private func setModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let selected = TranscriptionModel(rawValue: raw) else { return }
        model = selected
        UserDefaults.standard.set(raw, forKey: "model")
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
