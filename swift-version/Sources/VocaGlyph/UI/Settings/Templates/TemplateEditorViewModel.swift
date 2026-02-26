import SwiftUI
import SwiftData

/// ViewModel encapsulating all `ModelContext`-mutating operations for `TemplateEditorCard`.
/// By injecting `ModelContext` this class can be unit-tested with an in-memory container.
@MainActor
final class TemplateEditorViewModel {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Add Rule

    /// Appends a new rule to the template with automatic order assignment.
    /// Does nothing if `text` is empty after trimming.
    func commitAddRule(to template: PostProcessingTemplate, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (template.rules.map { $0.order }.max() ?? 0) + 1
        let rule = TemplateRule(order: nextOrder, instruction: trimmed)
        rule.template = template
        template.rules.append(rule)
        modelContext.insert(rule)
        template.updatedAt = Date()
    }

    // MARK: - Reorder

    /// Normalises rule `.order` values to be 1-based and contiguous after a deletion.
    func reorderRules(in template: PostProcessingTemplate) {
        let sorted = template.rules.sorted { $0.order < $1.order }
        for (idx, rule) in sorted.enumerated() {
            rule.order = idx + 1
        }
    }

    // MARK: - Reset to Defaults

    /// Deletes all current rules and reseeds from `template.defaultRules`.
    func resetToDefaults(template: PostProcessingTemplate) {
        for rule in template.rules { modelContext.delete(rule) }
        template.rules.removeAll()
        for (index, text) in template.defaultRules.enumerated() {
            let rule = TemplateRule(order: index + 1, instruction: text)
            rule.template = template
            template.rules.append(rule)
            modelContext.insert(rule)
        }
        template.updatedAt = Date()
        Logger.shared.info("TemplateEditorViewModel: Reset '\(template.name)' to default rules.")
    }
}
