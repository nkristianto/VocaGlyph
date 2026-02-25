import Foundation

// MARK: - TemplatePromptRenderer

/// Stateless utility that renders a `PostProcessingTemplate` into a structured
/// system prompt suitable for any post-processing engine.
///
/// ### Why a numbered list?
/// Local small models (Qwen 0.6B–7B) respond far more reliably to a numbered
/// instruction list than to prose paragraphs. The header + footer "sandwich"
/// constrains the model's output scope, suppressing chatty preambles and
/// compliance responses that `PostProcessingOutputSanitizer` catches defensively.
///
/// ### Anti-hallucination length guard
/// When the combined character count of all enabled rules exceeds
/// `maxRecommendedRuleCharacters` (800), the model is more likely to hallucinate.
/// Callers should surface a warning to the user via `isOverRecommendedLength(template:)`.
public enum TemplatePromptRenderer {

    // MARK: - Constants

    /// Maximum recommended combined character count for all enabled rules.
    /// Exceeding this limit may increase hallucination risk in local LLMs.
    public static let maxRecommendedRuleCharacters = 800

    // MARK: - Render

    /// Renders a template's enabled rules into a structured system prompt.
    ///
    /// Rules are sorted by `order` (ascending) and filtered to `isEnabled == true`.
    /// If no rules are enabled the method returns an empty string, which signals
    /// to the caller that post-processing should be skipped entirely.
    ///
    /// - Parameter template: The template to render.
    /// - Returns: A numbered-list system prompt, or an empty string when the
    ///   template has no enabled rules.
    public static func render(template: PostProcessingTemplate) -> String {
        let enabledRules = template.rules
            .filter { $0.isEnabled && !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.order < $1.order }

        guard !enabledRules.isEmpty else { return "" }

        let numberedList = enabledRules
            .enumerated()
            .map { index, rule in "\(index + 1). \(rule.instruction.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")

        return """
        You are a transcription refinement assistant. Apply ONLY the following rules. \
        Do not add, summarize, translate, or interpret the text. \
        Return ONLY the corrected transcription — nothing else.

        Rules:
        \(numberedList)

        Return the corrected text only, with no preamble, label, or explanation.
        """
    }

    // MARK: - Length Guard

    /// Returns the combined character count of all enabled rule instructions.
    ///
    /// - Parameter template: The template to measure.
    /// - Returns: Total character count of all enabled, non-empty rule instructions.
    public static func totalRuleCharacters(template: PostProcessingTemplate) -> Int {
        template.rules
            .filter { $0.isEnabled }
            .reduce(0) { $0 + $1.instruction.count }
    }

    /// Returns `true` when the combined enabled-rule length exceeds the recommended
    /// maximum, indicating an increased hallucination risk for local LLMs.
    ///
    /// - Parameter template: The template to check.
    /// - Returns: `true` if total rule characters > `maxRecommendedRuleCharacters`.
    public static func isOverRecommendedLength(template: PostProcessingTemplate) -> Bool {
        totalRuleCharacters(template: template) > maxRecommendedRuleCharacters
    }
}
