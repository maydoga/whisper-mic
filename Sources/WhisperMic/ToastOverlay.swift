import Cocoa

/// A floating dark pill at the top-center of the screen.
/// Uses NSPanel + .nonactivatingPanel so it never steals focus.
final class ToastOverlay {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var dotView: NSView?
    private var spinnerView: NSProgressIndicator?
    private var timer: Timer?
    private var recordingStart: Date?
    private var hideTimer: Timer?

    private let panelHeight: CGFloat = 32
    private let panelMinWidth: CGFloat = 160
    private let cornerRadius: CGFloat = 16
    private let dotSize: CGFloat = 10

    // MARK: - Public API

    func showRecording() {
        recordingStart = Date()
        ensurePanel()
        setDot(color: .systemRed, spinning: false)
        label?.stringValue = "REC  00:00"
        positionPanel()
        panel?.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let start = self?.recordingStart else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let mins = elapsed / 60
            let secs = elapsed % 60
            self?.label?.stringValue = String(format: "REC  %02d:%02d", mins, secs)
        }
    }

    func showTranscribing() {
        timer?.invalidate()
        timer = nil
        recordingStart = nil
        ensurePanel()
        setDot(color: nil, spinning: true)
        label?.stringValue = "Transcribing..."
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func showSuccess() {
        timer?.invalidate()
        timer = nil
        ensurePanel()
        setDot(color: .systemGreen, spinning: false)
        label?.stringValue = "Pasted"
        positionPanel()
        panel?.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func showError(_ text: String) {
        timer?.invalidate()
        timer = nil
        ensurePanel()
        setDot(color: .systemRed, spinning: false)
        label?.stringValue = text
        positionPanel()
        panel?.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        hideTimer?.invalidate()
        hideTimer = nil
        recordingStart = nil
        panel?.orderOut(nil)
    }

    // MARK: - Panel

    private func ensurePanel() {
        if panel != nil { return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelMinWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces]
        p.hidesOnDeactivate = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true

        let content = NSView(frame: p.contentView!.bounds)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.92).cgColor
        content.layer?.cornerRadius = cornerRadius
        content.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(content)

        // Dot indicator
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        dot.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(dot)
        self.dotView = dot

        // Spinner (hidden by default)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        spinner.appearance = NSAppearance(named: .darkAqua)
        content.addSubview(spinner)
        self.spinnerView = spinner

        // Label — monospace
        let lbl = NSTextField(labelWithString: "")
        lbl.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        lbl.textColor = .white
        lbl.lineBreakMode = .byTruncatingTail
        lbl.maximumNumberOfLines = 1
        lbl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(lbl)
        self.label = lbl

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),

            spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            lbl.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            lbl.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        self.panel = p
    }

    private func setDot(color: NSColor?, spinning: Bool) {
        if spinning {
            dotView?.isHidden = true
            spinnerView?.isHidden = false
            spinnerView?.startAnimation(nil)
        } else {
            spinnerView?.stopAnimation(nil)
            spinnerView?.isHidden = true
            dotView?.isHidden = false
            dotView?.layer?.backgroundColor = (color ?? .clear).cgColor
        }
    }

    private func positionPanel() {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let panel = panel, let label = label, let screen = mouseScreen ?? NSScreen.main else { return }
        label.sizeToFit()
        let textWidth = min(label.fittingSize.width, 500)
        // 14 (left pad) + 10 (dot) + 10 (gap) + text + 14 (right pad, matches left pad to dot edge)
        let width = max(panelMinWidth, 14 + dotSize + 10 + textWidth + 14)

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - panelHeight - 12

        panel.setFrame(NSRect(x: x, y: y, width: width, height: panelHeight), display: true)
    }
}
