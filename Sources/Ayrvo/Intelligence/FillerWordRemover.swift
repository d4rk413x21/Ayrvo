import Foundation

/// Strips verbal disfluencies ("uh", "um", "er", "hmm", …) from transcript text.
/// Pure `String → String` so it's unit-testable and safe to run anywhere in the
/// pipeline.
///
/// A filler is removed only when it stands alone as a word (not a substring of
/// "album"/"mummy"). After removal we collapse the duplicate punctuation a
/// parenthetical filler leaves behind ("I, um, was" → "I, , was" → "I, was"),
/// strip a leading comma a sentence-starting filler leaves ("um, I" → ", I" →
/// "I"), and trim trailing whitespace.
enum FillerWordRemover {
    /// English + common PT-BR fillers. Kept lowercase; matched case-insensitively.
    private static let defaultFillers: [String] = [
        "uh", "umm", "um", "er", "err", "ah", "ahh",
        "hmm", "mmm", "mm",
        "é", "eh", "tipo", "né", "aham", "ehe"
    ]

    /// Build a regex that matches a standalone filler token plus any trailing
    /// whitespace. A "standalone token" means preceded by start-of-string or a
    /// non-letter, and followed by end-of-string or a non-letter. \b is
    /// ASCII-only in ICU, so we use explicit `[^\\p{L}]` boundaries (with
    /// fixed-length lookbehind, which NSRegularExpression supports).
    private static func makeRegex(for fillers: [String]) -> NSRegularExpression {
        let escaped = fillers
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .sorted { $0.count > $1.count }  // match longer fillers first
        let alt = escaped.joined(separator: "|")
        let pattern = "(?i)(?:^|(?<=[^\\p{L}]))(?:\(alt))(?=$|[^\\p{L}])\\s*"
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    /// Remove filler words from `text`. Collapses duplicate punctuation and
    /// whitespace left behind; strips a leading punctuation mark left by a
    /// sentence-starting filler.
    static func clean(_ text: String, fillers: [String] = defaultFillers) -> String {
        guard !fillers.isEmpty, !text.isEmpty else { return text }
        let regex = makeRegex(for: fillers)
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "")
        // Collapse "I, , was" → "I, was" (and same for ;, .) — the duplicate a
        // parenthetical filler leaves behind.
        var result = stripped.replacingOccurrences(
            of: "([,;.])\\s*\\1",
            with: "$1",
            options: .regularExpression)
        // Strip a leading punctuation mark left by a sentence-starting filler.
        result = result.replacingOccurrences(
            of: "^[,;.]\\s*",
            with: "",
            options: .regularExpression)
        // Collapse runs of spaces (newlines preserved).
        result = result.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }
}
