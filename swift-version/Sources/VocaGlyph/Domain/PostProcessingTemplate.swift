import Foundation
import SwiftData

// MARK: - PostProcessingTemplate

/// A named, free-text post-processing prompt stored in SwiftData.
///
/// Each template holds a single `promptText` that is passed directly to the
/// post-processing engine. This replaces the previous per-rule `TemplateRule`
/// model, which has been removed entirely.
///
/// System templates (`isSystem == true`) are seeded on first launch and cannot be
/// deleted. The original prompt is stored in `defaultPrompt` to allow a reset.
@Model
public final class PostProcessingTemplate {

    // MARK: - Stored Properties

    @Attribute(.unique) public var id: UUID
    public var name: String
    public var templateDescription: String

    /// `true` for built-in templates seeded by `TemplateSeederService`.
    /// System templates cannot be deleted from the UI.
    public var isSystem: Bool

    /// The free-text prompt sent to the post-processing engine.
    /// Empty string means the template is inactive (no post-processing applied).
    public var promptText: String

    /// Snapshot of the original prompt used to support "Reset to Default".
    /// Only populated for system templates; empty for user-created templates.
    public var defaultPrompt: String

    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        name: String,
        templateDescription: String = "",
        isSystem: Bool = false,
        promptText: String = "",
        defaultPrompt: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.templateDescription = templateDescription
        self.isSystem = isSystem
        self.promptText = promptText
        self.defaultPrompt = defaultPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
