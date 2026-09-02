import Foundation

/// Fixed corrections applied to every transcript before it reaches the clipboard.
///
/// Speech models cannot guess a brand they have never been told about. "FRMWRK" comes
/// back as "Framework" every single time, and that is a repair, not a rewrite: the list
/// only holds mishearings that have already been corrected by hand at least once.
///
/// The list is shared with the second brain's transcription pipeline so a term corrected
/// in one place is corrected in both. It lives in that repo and is read at runtime; if it
/// is not there, dictation simply pastes what came back. A missing list must never hold
/// up a transcript.
///
/// Whole words only. `\bframework\b` leaves "frameworks" and "frameworkje" alone, which is
/// exactly right: the plural is the ordinary noun, the singular is almost always the company.
enum TermCorrections {
    /// Shared with `~/repos/second-brain/.claude/scripts/termen.py`. One list, two readers.
    private static let listURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("repos/second-brain/gereedschap/transcriptie-termen.json")

    private struct Rule: Decodable {
        let fout: String
        let goed: String
        let negeerHoofdletters: Bool?
        /// Exception for a fixed expression: "ideal" is iDEAL, except in "ideal customer
        /// profile". Without it that rule breaks more than it fixes.
        let nietGevolgdDoor: String?

        enum CodingKeys: String, CodingKey {
            case fout, goed
            case negeerHoofdletters = "negeer_hoofdletters"
            case nietGevolgdDoor = "niet_gevolgd_door"
        }
    }

    private struct List: Decodable {
        let regels: [Rule]
    }

    private struct Compiled {
        let regex: NSRegularExpression
        let replacement: String
    }

    private static var cache: [Compiled] = []
    private static var cachedAt: Date?

    /// Reload when the file's timestamp moved, so editing the list takes effect without
    /// rebuilding the app.
    private static func rules() -> [Compiled] {
        let stamp = try? listURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let stamp, stamp == cachedAt { return cache }

        guard let data = try? Data(contentsOf: listURL),
              let list = try? JSONDecoder().decode(List.self, from: data) else {
            cache = []
            cachedAt = stamp
            return cache
        }

        cache = list.regels.compactMap { rule in
            var pattern = "\\b" + NSRegularExpression.escapedPattern(for: rule.fout) + "\\b"
            if let na = rule.nietGevolgdDoor {
                pattern += "(?!\\s+" + NSRegularExpression.escapedPattern(for: na) + ")"
            }
            let options: NSRegularExpression.Options =
                (rule.negeerHoofdletters ?? false) ? [.caseInsensitive] : []
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return nil
            }
            return Compiled(regex: regex,
                            replacement: NSRegularExpression.escapedTemplate(for: rule.goed))
        }
        cachedAt = stamp
        return cache
    }

    /// The known mishearings, repaired. Returns the text unchanged when the list is absent.
    static func apply(_ text: String) -> String {
        var out = text
        for rule in rules() {
            out = rule.regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: rule.replacement
            )
        }
        return out
    }
}
