import Foundation

/// Filename stamp: `whispermic_2026-08-24_09-30-12_nl.wav`.
/// Everything the store needs lives in the name, so there is no sidecar
/// metadata to keep in sync and a half-written state can't confuse it.
private let stampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private let namePrefix = "whispermic_"
private let doneMarker = ".done"

/// One audio file on disk. `isTranscribed` recordings are the ones that already
/// produced a transcript; they linger only until the next recording replaces them.
struct Recording {
    let url: URL
    let createdAt: Date
    let language: String
    let isTranscribed: Bool

    init?(url: URL) {
        guard url.pathExtension == "wav" else { return nil }
        var name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix(namePrefix) else { return nil }

        let done = name.hasSuffix(doneMarker)
        if done { name.removeLast(doneMarker.count) }

        let parts = name.split(separator: "_")
        guard parts.count == 4,
              let date = stampFormatter.date(from: "\(parts[1])_\(parts[2])")
        else { return nil }

        self.url = url
        self.createdAt = date
        self.language = String(parts[3])
        self.isTranscribed = done
    }

    /// 16 kHz mono 16-bit PCM is 32000 bytes/sec; the WAV header is 44 bytes.
    /// Cheaper than opening an AVAsset just to label a menu item.
    var duration: TimeInterval {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
        return max(0, (bytes - 44) / 32000)
    }

    /// e.g. "09:30 · 0:24 · nl"
    var menuLabel: String {
        let clock = DateFormatter.localizedString(from: createdAt, dateStyle: .none, timeStyle: .short)
        let secs = Int(duration.rounded())
        return String(format: "%@ · %d:%02d · %@", clock, secs / 60, secs % 60, language)
    }
}

/// Recordings are written here instead of /tmp and survive a failed transcription,
/// a crash, or a reboot. Nothing is deleted because an API call went wrong — a
/// dropped internet connection never costs you the audio.
enum RecordingStore {
    /// Failed recordings kept on disk before the oldest is dropped.
    static let maxPending = 10

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WhisperMic/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func newRecordingURL(language: String, at date: Date = Date()) -> URL {
        directory.appendingPathComponent("\(namePrefix)\(stampFormatter.string(from: date))_\(language).wav")
    }

    /// Every recording still on disk, newest first.
    static func all() -> [Recording] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(Recording.init(url:)).sorted { $0.createdAt > $1.createdAt }
    }

    /// Recordings that never produced a transcript — the retry queue.
    static func pending() -> [Recording] {
        all().filter { !$0.isTranscribed }
    }

    /// Marks a recording transcribed by renaming it. It stays around until the next
    /// recording arrives, so "Retranscribe Last" still works on a short or garbled result.
    static func markTranscribed(_ recording: Recording) {
        guard !recording.isTranscribed else { return }
        let target = directory.appendingPathComponent(
            "\(namePrefix)\(stampFormatter.string(from: recording.createdAt))_\(recording.language)\(doneMarker).wav"
        )
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: recording.url, to: target)
    }

    static func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
    }

    static func discardAll() {
        all().forEach(delete)
    }

    /// Keeps the newest transcribed recording and at most `maxPending` failed ones.
    static func prune() {
        let recordings = all()
        for extra in recordings.filter({ $0.isTranscribed }).dropFirst() { delete(extra) }
        for extra in recordings.filter({ !$0.isTranscribed }).dropFirst(maxPending) { delete(extra) }
    }

    /// Earlier builds recorded straight into /tmp and deleted on success; anything
    /// left there is a leftover from a crash and can never be recovered by name.
    static func cleanupLegacyTempFiles() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(namePrefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
