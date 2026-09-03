import Foundation

/// The proper nouns the transcription model may expect to hear.
///
/// A speech model cannot guess a brand it has never been told about: "FRMWRK" comes back
/// as "Framework" every single time. `gpt-transcribe` takes a `keywords[]` field for
/// exactly this — literal terms you expect in the audio — and the model then decides for
/// itself what it heard.
///
/// This is deliberately not the mechanical term correction that was reverted in e47b0a0.
/// That one rewrote the transcript after the fact, silently changing what was said. A
/// keyword is the opposite: a hint given before the model listens, which never puts a word
/// on the page that the model did not hear. Measured on a 55-minute recording with all 81
/// terms: not one term appeared in the text that was not spoken.
///
/// The list is shared with the second brain's transcription pipeline, so a term added in
/// one place helps both. It is read at runtime and reloaded when the file's timestamp
/// moves, so adding a term needs no rebuild. If the file is missing or broken, dictation
/// simply runs without keywords — a list must never hold up a transcript.
enum TranscriptionKeywords {
    /// Shared with `~/repos/second-brain/.claude/scripts/diarize-transcribe.py`.
    private static let listURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("repos/second-brain/gereedschap/transcriptie-termen.json")

    private struct Rule: Decodable { let goed: String }
    private struct List: Decodable { let regels: [Rule] }

    private static var cache: [String] = []
    private static var cachedAt: Date?

    static func all() -> [String] {
        let stamp = try? listURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let stamp, stamp == cachedAt { return cache }

        guard let data = try? Data(contentsOf: listURL),
              let list = try? JSONDecoder().decode(List.self, from: data) else {
            cache = []
            cachedAt = stamp
            return cache
        }

        // Unique, sorted, and free of the characters the API rejects in a keyword.
        var seen = Set<String>()
        cache = list.regels
            .map(\.goed)
            .filter { term in
                !term.isEmpty
                    && !term.contains(where: { $0 == "<" || $0 == ">" || $0.isNewline })
                    && seen.insert(term).inserted
            }
            .sorted()
        cachedAt = stamp
        return cache
    }
}
