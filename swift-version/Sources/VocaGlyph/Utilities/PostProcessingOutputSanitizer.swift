import Foundation

// MARK: - PostProcessingOutputSanitizer

/// Defensive post-processing output sanitizer for all AI engine results.
///
/// AI post-processing engines produce three categories of bad output:
///
/// **Level 1 – Chatty preambles**: The model wraps the revised text in a conversational label.
/// ```
/// "Here is the revised text: Hello world."
/// "**Revised Text:** Hello world."
/// ```
///
/// **Level 2 – Refusals**: The model treats the transcribed speech as a user request and refuses.
/// ```
/// "Sorry, I can't assist with that request."
/// ```
///
/// **Level 3 – Hallucinations**: The model generates entirely new content instead of refining input.
/// (Detected by length explosion: output is 3× longer than the original input.)
///
/// This sanitizer is **stateless**, **nonisolated**, and has zero external dependencies.
/// It is safe to call from any actor context, including inside `actor` engine types.
public enum PostProcessingOutputSanitizer {

    // MARK: - Validation Result

    /// Result of output validation.
    public enum ValidationResult: Equatable {
        /// Output appears valid — use the cleaned string.
        case valid(String)
        /// Output failed a safety check — caller should fall back to the raw input.
        case fallback(reason: FallbackReason)

        public enum FallbackReason: String, Equatable {
            case refusal       // Model refused the request
            case hallucination // Output is dramatically longer than input
        }
    }

    // MARK: - Sanitize (Level 1)

    /// Strips chatty preambles and markdown headers from the start of an AI response.
    ///
    /// Returns the trimmed, cleaned string. If the preamble was the entire response,
    /// returns an empty string (the caller's `validate` step will then fall back to raw input).
    ///
    /// **Examples**:
    /// - `"Here is the revised text: Hello."` → `"Hello."`
    /// - `"**Revised Text:** Hello."` → `"Hello."`
    /// - `"**Sure, here is the revised text:**\nHello."` → `"Hello."`
    public static func sanitize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        // Ordered list of prefix patterns to strip (case-insensitive, most-specific first).
        // Each pattern, when found at the start, is removed and the remainder is returned.
        let prefixPatterns: [String] = [
            // Response framing tags the model may use as output wrappers
            "[output]",
            // Markdown-bold variants
            "**sure, here is the revised text:**",
            "**here is the revised text:**",
            "**here is the revised version:**",
            "**here is the text:**",
            "**revised text:**",
            "**revised:**",
            "**result:**",
            // Plain text variants
            "sure, here is the revised text:",
            "here is the revised text:",
            "here is the revised version:",
            "here is the text:",
            "revised text:",
            "revised:",
            "result:",
        ]

        let lower = result.lowercased()
        for pattern in prefixPatterns {
            if lower.hasPrefix(pattern) {
                result = String(result.dropFirst(pattern.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break // Only remove one preamble — stop after first match
            }
        }

        // Strip surrounding quotes if the entire remaining content is quoted.
        // e.g., `"Hello world."` → `Hello world.`
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 2 {
            let inner = String(result.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty {
                result = inner
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Validate (Levels 2 & 3)

    /// Validates sanitized output against the original input for refusals and hallucinations.
    ///
    /// - Parameters:
    ///   - output: The sanitized output from `sanitize(_:)`.
    ///   - input: The original raw transcription that was sent for refinement.
    /// - Returns: `.valid(output)` if the output looks legitimate, or `.fallback(reason:)` if
    ///   the output should be discarded and the raw input used instead.
    public static func validate(_ output: String, against input: String) -> ValidationResult {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Level 2: Refusal AND compliance-response detection.
        // The model sometimes treats transcribed speech as a user request and either refuses it
        // ("Sorry, I can't...") or helpfully answers it ("Sure, I'd be happy to...").
        // Both cases mean the model did NOT actually refine the transcription — discard the output.
        let refusalAndCompliancePrefixes: [String] = [
            // Negative / refusal
            "sorry, i can't",
            "sorry, i cannot",
            "sorry, but i can't",
            "sorry, but i cannot",
            "i'm sorry, i can't",
            "i'm sorry, i cannot",
            "i can't assist",
            "i cannot assist",
            "i'm unable to",
            "i am unable to",
            "i'm not able to",
            "i am not able to",
            // Positive / compliance (model answered the transcription as a question)
            "sure, i'd be happy to",
            "sure, i would be happy to",
            "of course! i'd be happy to",
            "of course, i'd be happy to",
            "absolutely! i'd be happy to",
            "absolutely, i'd be happy to",
            "great, let's",
            "great! let's",
            "i'd be happy to help",
            "i would be happy to help",
            "i'll help you",
            "i will help you",
            "certainly! i'd be",
            "certainly, i'd be",
        ]
        let lowerTrimmed = trimmed.lowercased()
        for prefix in refusalAndCompliancePrefixes {
            if lowerTrimmed.hasPrefix(prefix) {
                return .fallback(reason: .refusal)
            }
        }

        // Level 3: Length explosion / hallucination detection.
        // If the model's output is more than 3× the length of the input plus a 200-char buffer,
        // the model has likely fabricated new content. Fall back to the raw transcription.
        let inputLength = input.count
        let outputLength = trimmed.count
        let lengthThreshold = max(inputLength * 3 + 200, 300)
        if outputLength > lengthThreshold {
            return .fallback(reason: .hallucination)
        }

        // Output passes all checks — use it.
        return .valid(trimmed)
    }
}
