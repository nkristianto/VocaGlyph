import SwiftUI
import SwiftData

/// ViewModel encapsulating `ModelContext`-mutating operations for `TemplateEditorCard`.
@MainActor
final class TemplateEditorViewModel {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Reset to Defaults

    /// Resets `promptText` back to `defaultPrompt` for system templates.
    func resetToDefaults(template: PostProcessingTemplate) {
        template.promptText = template.defaultPrompt
        template.updatedAt = Date()
        Logger.shared.info("TemplateEditorViewModel: Reset '\(template.name)' to default prompt.")
    }
}
