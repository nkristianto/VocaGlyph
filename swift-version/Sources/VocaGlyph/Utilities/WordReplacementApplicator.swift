import Foundation

// MARK: - WordReplacementApplicator

/// Stateless utility that applies a list of word-replacement pairs to a string.
///
/// Replacements are applied using `NSRegularExpression` with `\b` word-boundary
/// anchors and the `.caseInsensitive` option. Each pair replaces ALL matching
/// occurrences in the current string in the order they appear in the list.
///
/// AC #5: whole-word, case-insensitive substitution.
/// AC #6: word-boundary anchors prevent partial-word matches (e.g., "can" → "may"
///        does NOT affect "cannot").
public enum WordReplacementApplicator {

    /// Applies replacement pairs to `text` and returns the substituted string.
    ///
    /// - Parameters:
    ///   - text: The source text (e.g., raw transcription).
    ///   - replacements: Ordered list of `(word, replacement)` pairs to apply.
    ///                   Only enabled pairs should be passed by the caller.
    /// - Returns: The text after all replacements have been applied in order.
    public static func apply(
        to text: String,
        replacements: [(word: String, replacement: String)]
    ) -> String {
        var current = text

        for pair in replacements {
            // Escape regex metacharacters in the source word to prevent injection.
            let escapedWord = NSRegularExpression.escapedPattern(for: pair.word)
            let pattern = "\\b\(escapedWord)\\b"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                // Malformed pattern — skip this pair rather than crash.
                Logger.shared.info("WordReplacementApplicator: skipping invalid pattern for word '\(pair.word)'")
                continue
            }

            let range = NSRange(current.startIndex..., in: current)
            current = regex.stringByReplacingMatches(in: current, range: range, withTemplate: pair.replacement)
        }

        return current
    }
}
