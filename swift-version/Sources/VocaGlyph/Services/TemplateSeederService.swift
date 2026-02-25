import Foundation
import SwiftData

// MARK: - TemplateSeederService

/// Seeds the three default system `PostProcessingTemplate` records into SwiftData
/// on first launch. This is a no-op if any template already exists in the store.
///
/// **Seeded Templates**
///
/// | Name                    | isSystem | Active by default |
/// |-------------------------|----------|-------------------|
/// | General Cleanup         | true     | ✅ yes             |
/// | Meeting Notes           | true     | no                |
///
/// Call `seedDefaultTemplatesIfNeeded(context:)` once from `AppDelegate`
/// inside `initializeCoreServices()`, after the `ModelContainer` is ready.
public enum TemplateSeederService {

    // MARK: - UserDefaults Key

    /// Key used to persist the UUID of the currently active template.
    public static let activeTemplateKey = "activePostProcessingTemplateId"

    // MARK: - Seed

    /// Seeds default templates if none exist.
    ///
    /// - Parameter context: The `ModelContext` to use for insertion.
    public static func seedDefaultTemplatesIfNeeded(context: ModelContext) {
        // Always clean up the "Raw — No Processing" template if it exists from a
        // previous install — it is no longer offered as an option.
        removeRawTemplateIfPresent(context: context)

        let descriptor = FetchDescriptor<PostProcessingTemplate>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else {
            Logger.shared.info("TemplateSeederService: Templates already exist (\(existingCount)). Skipping seed.")
            return
        }

        Logger.shared.info("TemplateSeederService: No templates found. Seeding defaults...")

        let generalCleanup = makeGeneralCleanup()
        let meetingNotes = makeMeetingNotes()

        context.insert(generalCleanup)
        context.insert(meetingNotes)

        do {
            try context.save()
            Logger.shared.info("TemplateSeederService: Seeded 2 default templates.")

            // Activate "General Cleanup" by default
            UserDefaults.standard.set(generalCleanup.id.uuidString, forKey: activeTemplateKey)
            Logger.shared.info("TemplateSeederService: Set 'General Cleanup' as active template.")
        } catch {
            Logger.shared.error("TemplateSeederService: Failed to save seeded templates — \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    /// Deletes the "Raw — No Processing" system template from the store if present.
    /// Called on every launch so existing users are migrated automatically.
    private static func removeRawTemplateIfPresent(context: ModelContext) {
        let rawName = "Raw — No Processing"
        let descriptor = FetchDescriptor<PostProcessingTemplate>(
            predicate: #Predicate { $0.name == rawName }
        )
        guard let matches = try? context.fetch(descriptor), !matches.isEmpty else { return }
        for template in matches {
            // If this was the active template, clear the active key so the app
            // doesn't reference a deleted ID.
            if let activeId = UserDefaults.standard.string(forKey: activeTemplateKey),
               activeId == template.id.uuidString {
                UserDefaults.standard.removeObject(forKey: activeTemplateKey)
                Logger.shared.info("TemplateSeederService: Cleared active template key (was pointing to Raw template).")
            }
            context.delete(template)
        }
        try? context.save()
        Logger.shared.info("TemplateSeederService: Removed \(matches.count) 'Raw — No Processing' template(s).")
    }

    private static func makeGeneralCleanup() -> PostProcessingTemplate {
        let ruleTexts = [
            "Remove filler words: uh, um, like, you know, I mean, I guess, so, actually, basically, literally.",
            "Fix capitalization and punctuation.",
            "Self-corrections: keep only the corrected wording and drop the original attempt.",
            "Keep all sentences and meaning. Never answer questions or add any information.",
            "Output only the cleaned text.",
        ]
        let template = PostProcessingTemplate(
            name: "General Cleanup",
            templateDescription: "Removes fillers, fixes capitalization and punctuation, and preserves all meaning.",
            isSystem: true,
            defaultRules: ruleTexts
        )
        for (index, text) in ruleTexts.enumerated() {
            let rule = TemplateRule(order: index + 1, instruction: text)
            rule.template = template
            template.rules.append(rule)
        }
        return template
    }

    private static func makeMeetingNotes() -> PostProcessingTemplate {
        let ruleTexts = [
            "Formalize the tone — convert casual language to professional language.",
            "Capitalize proper nouns, names, and acronyms.",
            "Fix grammar and punctuation.",
            "Remove filler words: um, uh, you know, like.",
        ]
        let template = PostProcessingTemplate(
            name: "Meeting Notes",
            templateDescription: "Formalizes tone and capitalizes proper nouns for meeting transcriptions.",
            isSystem: true,
            defaultRules: ruleTexts
        )
        for (index, text) in ruleTexts.enumerated() {
            let rule = TemplateRule(order: index + 1, instruction: text)
            rule.template = template
            template.rules.append(rule)
        }
        return template
    }
}
