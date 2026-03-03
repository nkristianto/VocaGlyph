import Foundation

// MARK: - TemplatePromptRenderer

/// Stateless utility that renders a `PostProcessingTemplate` into a structured
/// system prompt suitable for any post-processing engine.
///
/// ### Anti-hallucination length guard
/// When `promptText` exceeds `maxRecommendedPromptCharacters` (800 chars),
/// the model is more likely to hallucinate. Callers should surface a warning
/// to the user via `isOverRecommendedLength(template:)`.
public enum TemplatePromptRenderer {

    // MARK: - Constants

    /// Maximum recommended character count for a template's prompt text.
    /// Exceeding this limit may increase hallucination risk in local LLMs.
    public static let maxRecommendedPromptCharacters = 800

    // MARK: - Render

    /// Renders a template's `promptText` into a structured system prompt.
    ///
    /// Returns an empty string when `promptText` is empty or whitespace-only,
    /// which signals to the caller that post-processing should be skipped.
    ///
    /// - Parameter template: The template to render.
    /// - Returns: A structured system prompt, or an empty string when the
    ///   template has no prompt text.
    public static func render(template: PostProcessingTemplate) -> String {
        let trimmed = template.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        return """
        You are a transcription refinement assistant. Apply ONLY the following rules. \
        Do not add, summarize, translate, or interpret the text. \
        Return ONLY the corrected transcription — nothing else.

        Rules:
        \(trimmed)

        Return the corrected text only, with no preamble, label, or explanation.
        """
    }

    // MARK: - Length Guard

    /// Returns the character count of the template's prompt text.
    ///
    /// - Parameter template: The template to measure.
    /// - Returns: Character count of `promptText`.
    public static func promptCharacterCount(template: PostProcessingTemplate) -> Int {
        template.promptText.count
    }

    /// Returns `true` when the prompt text length exceeds the recommended
    /// maximum, indicating an increased hallucination risk for local LLMs.
    ///
    /// - Parameter template: The template to check.
    /// - Returns: `true` if `promptText.count > maxRecommendedPromptCharacters`.
    public static func isOverRecommendedLength(template: PostProcessingTemplate) -> Bool {
        promptCharacterCount(template: template) > maxRecommendedPromptCharacters
    }
}
