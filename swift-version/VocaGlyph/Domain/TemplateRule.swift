import Foundation
import SwiftData

// MARK: - TemplateRule

/// A single post-processing instruction belonging to a `PostProcessingTemplate`.
///
/// Rules are rendered in ascending `order` and only included when `isEnabled == true`.
/// Disabling a rule (rather than deleting it) lets users temporarily suppress a rule
/// without losing its text.
@Model
public final class TemplateRule {

    // MARK: - Stored Properties

    @Attribute(.unique) public var id: UUID

    /// 1-based position within the parent template's rule list.
    /// Rendering sorts by this field ascending; gaps are fine.
    public var order: Int

    /// The plain-text instruction the AI must follow.
    /// Example: "Remove filler words: um, uh, you know, like."
    public var instruction: String

    /// When `false`, this rule is excluded from the rendered prompt.
    public var isEnabled: Bool

    /// Back-reference to the owning template.
    public var template: PostProcessingTemplate?

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        order: Int,
        instruction: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.order = order
        self.instruction = instruction
        self.isEnabled = isEnabled
        self.template = nil
    }
}
