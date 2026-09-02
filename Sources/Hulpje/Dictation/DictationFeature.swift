import AppKit
import Carbon.HIToolbox

/// Hold the hotkey, speak, get the transcript pasted where the cursor was.
/// This is what the app started life as; it is now one feature among several.
@MainActor
final class DictationFeature: NSObject, Feature {
    let name = "Dictation"

    /// Recording keeps running briefly after the hotkey. Transcription models drop
    /// trailing words when the audio ends mid-syllable, which reads as a missing
    /// last sentence.
    private static let tailPadding: TimeInterval = 0.4
    private static let hotkey = Hotkey(kVK_Space, [.control, .option, .command])

    private let recorder = AudioRecorder()
    private let toast = ToastOverlay()
    private let refresh: () -> Void
    private var hotkeyID: UInt32?

    private var language = UserDefaults.standard.string(forKey: "language") ?? "auto"
    private var autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
    private var model = UserDefaults.standard.string(forKey: "model")
        .flatMap(TranscriptionModel.init(rawValue:)) ?? .default

    /// The app that was active when recording started — the paste target.
    private var previousApp: NSRunningApplication?
    private var isTranscribing = false
    /// True during the tail-padding window, so a second hotkey press is ignored.
    private var isStopping = false

    private let ownBundleID = Bundle.main.bundleIdentifier

    init(refresh: @escaping () -> Void) {
        self.refresh = refresh
        super.init()
    }

    var isEnabled: Bool {
        get { isEnabledByDefault }
        set { setEnabled(newValue) }
    }

    /// What the app's own status item should show.
    var statusSymbol: String {
        if recorder.isRecording { return "mic.fill" }
        return Accessibility.isTrusted ? "mic" : "mic.slash"
    }

    var statusLine: String {
        if recorder.isRecording { return "Recording…" }
        if isTranscribing { return "Transcribing…" }
        return "Ready"
    }

    func start() {
        RecordingStore.cleanupLegacyTempFiles()
        RecordingStore.prune()
        guard isEnabled, hotkeyID == nil else { return }
        hotkeyID = HotkeyManager.shared.register(Self.hotkey, label: "Dictation.record") { [weak self] in
            self?.toggleRecording()
        }
    }

    func stop() {
        if let hotkeyID { HotkeyManager.shared.unregister(hotkeyID) }
        hotkeyID = nil
    }

    // MARK: - Menu

    func addMenuItems(to menu: NSMenu) {
        let recordTitle = recorder.isRecording ? "Stop Recording" : "Start Recording"
        menu.addItem(
            "\(recordTitle)  \(Self.hotkey.display)",
            target: self,
            action: #selector(toggleRecordingAction)
        )

        addRecordingsSection(to: menu)

        let submenu = NSMenu()

        let langItem = NSMenuItem(title: "Language: \(Self.languageName(language))", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (code, label) in Self.languages {
            langMenu.addItem(
                label,
                target: self,
                action: #selector(setLanguage(_:)),
                state: code == language ? .on : .off,
                represented: code
            )
        }
        langItem.submenu = langMenu
        submenu.addItem(langItem)

        let modelItem = NSMenuItem(title: "Model: \(model.rawValue)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for candidate in TranscriptionModel.allCases {
            modelMenu.addItem(
                candidate.displayName,
                target: self,
                action: #selector(setModel(_:)),
                state: candidate == model ? .on : .off,
                represented: candidate.rawValue
            )
        }
        modelItem.submenu = modelMenu
        submenu.addItem(modelItem)

        submenu.addItem(
            "Auto-Paste",
            target: self,
            action: #selector(toggleAutoPaste),
            state: autoPaste ? .on : .off
        )

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem("Reveal Saved Audio in Finder", target: self, action: #selector(revealRecordings))
        submenu.addItem("Discard Saved Audio", target: self, action: #selector(discardRecordings))

        let item = NSMenuItem(title: "Dictation", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    /// Retry and re-run entries for the audio still on disk.
    private func addRecordingsSection(to menu: NSMenu) {
        let recordings = RecordingStore.all()
        guard !recordings.isEmpty else { return }
        let failed = recordings.filter { !$0.isTranscribed }
        let idle = !isTranscribing && !recorder.isRecording

        if let latest = recordings.first {
            let title = latest.isTranscribed
                ? "Retranscribe Last (\(latest.menuLabel))"
                : "Retry Last Recording (\(latest.menuLabel))"
            menu.addItem(
                title,
                target: self,
                action: #selector(retryRecording(_:)),
                keyEquivalent: "r",
                modifiers: [.command],
                enabled: idle,
                represented: latest.url
            )
        }

        if failed.count > 1 {
            let failedMenu = NSMenu()
            for recording in failed {
                failedMenu.addItem(
                    recording.menuLabel,
                    target: self,
                    action: #selector(retryRecording(_:)),
                    enabled: idle,
                    represented: recording.url
                )
            }
            let failedItem = NSMenuItem(title: "Failed Recordings (\(failed.count))", action: nil, keyEquivalent: "")
            failedItem.submenu = failedMenu
            menu.addItem(failedItem)
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        guard !isStopping else { return }
        if recorder.isRecording { stopRecording() } else { startRecording() }
    }

    /// The frontmost app that is not Hulpje — the paste target.
    private func resolvePasteTarget() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != ownBundleID { return front }
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

        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != ownBundleID {
            previousApp = front
        }

        do {
            try recorder.startRecording(language: language)
        } catch {
            toast.showError("Mic error")
            return
        }

        toast.showRecording()
        refresh()
    }

    private func stopRecording() {
        isStopping = true
        toast.showTranscribing()
        refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tailPadding) { [weak self] in
            guard let self else { return }
            self.isStopping = false
            guard let recording = self.recorder.stopRecording() else {
                self.toast.hide()
                self.refresh()
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
        refresh()

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
                        refresh()
                        return
                    }
                    RecordingStore.markTranscribed(recording)
                    RecordingStore.prune()
                    // Known mishearings repaired before it reaches the clipboard:
                    // "Framework" is FRMWRK, "Klavio" is Klaviyo. See TermCorrections.
                    deliver(TermCorrections.apply(transcript))
                    refresh()
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
                    refresh()
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
        guard Accessibility.isTrusted else {
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

    // MARK: - Actions

    @objc private func toggleRecordingAction() { toggleRecording() }

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
        refresh()
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        language = code
        UserDefaults.standard.set(code, forKey: "language")
        refresh()
    }

    @objc private func setModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let selected = TranscriptionModel(rawValue: raw) else { return }
        model = selected
        UserDefaults.standard.set(raw, forKey: "model")
        refresh()
    }

    @objc private func toggleAutoPaste() {
        autoPaste.toggle()
        UserDefaults.standard.set(autoPaste, forKey: "autoPaste")
        refresh()
    }

    // MARK: - Languages

    private static let languages: [(String, String)] = [
        ("auto", "Auto-detect"), ("nl", "Nederlands"), ("en", "English"),
        ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("tr", "Türkçe"),
    ]

    private static func languageName(_ code: String) -> String {
        languages.first { $0.0 == code }?.1 ?? code
    }
}
