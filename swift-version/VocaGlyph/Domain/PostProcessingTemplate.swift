import Foundation
import SwiftData

// MARK: - PostProcessingTemplate

/// A named, ordered collection of post-processing rules stored in SwiftData.
///
/// Templates replace the single free-text `UserDefaults` prompt with a structured
/// set of discrete instructions that are rendered into a numbered system prompt at
/// call-time, significantly reducing hallucination from local LLMs.
///
/// System templates (`isSystem == true`) are seeded on first launch and cannot be
/// deleted. Their original rules are stored in `defaultRules` to allow a reset.
@Model
public final class PostProcessingTemplate {

    // MARK: - Stored Properties

    @Attribute(.unique) public var id: UUID
    public var name: String
    public var templateDescription: String

    /// `true` for built-in templates seeded by `TemplateSeederService`.
    /// System templates cannot be deleted from the UI.
    public var isSystem: Bool

    /// Snapshot of the original rule texts used to support "Reset to Default".
    /// Only populated for system templates; empty for user-created templates.
    public var defaultRules: [String]

    /// Ordered rules. Use `.sorted(by: { $0.order < $1.order })` before rendering.
    @Relationship(deleteRule: .cascade, inverse: \TemplateRule.template)
    public var rules: [TemplateRule]

    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        name: String,
        templateDescription: String = "",
        isSystem: Bool = false,
        defaultRules: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.templateDescription = templateDescription
        self.isSystem = isSystem
        self.defaultRules = defaultRules
        self.rules = []
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
