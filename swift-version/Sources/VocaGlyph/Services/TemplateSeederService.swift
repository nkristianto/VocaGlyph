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
/// | Raw — No Processing     | true     | no                |
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
        let descriptor = FetchDescriptor<PostProcessingTemplate>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else {
            Logger.shared.info("TemplateSeederService: Templates already exist (\(existingCount)). Skipping seed.")
            return
        }

        Logger.shared.info("TemplateSeederService: No templates found. Seeding defaults...")

        let generalCleanup = makeGeneralCleanup()
        let meetingNotes = makeMeetingNotes()
        let rawNoProcessing = makeRawNoProcessing()

        context.insert(generalCleanup)
        context.insert(meetingNotes)
        context.insert(rawNoProcessing)

        do {
            try context.save()
            Logger.shared.info("TemplateSeederService: Seeded 3 default templates.")

            // Activate "General Cleanup" by default
            UserDefaults.standard.set(generalCleanup.id.uuidString, forKey: activeTemplateKey)
            Logger.shared.info("TemplateSeederService: Set 'General Cleanup' as active template.")
        } catch {
            Logger.shared.error("TemplateSeederService: Failed to save seeded templates — \(error.localizedDescription)")
        }
    }

    // MARK: - Template Factories

    private static func makeGeneralCleanup() -> PostProcessingTemplate {
        let ruleTexts = [
            "Fix grammar and capitalization.",
            "Remove filler words: um, uh, you know, like, basically, literally, actually.",
            "End the text with proper punctuation.",
        ]
        let template = PostProcessingTemplate(
            name: "General Cleanup",
            templateDescription: "Fixes grammar, removes filler words, and adds punctuation.",
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

    private static func makeRawNoProcessing() -> PostProcessingTemplate {
        // No rules → TemplatePromptRenderer.render() returns "" → post-processing skipped
        let template = PostProcessingTemplate(
            name: "Raw — No Processing",
            templateDescription: "Passes transcription through unchanged. No AI refinement applied.",
            isSystem: true,
            defaultRules: []
        )
        return template
    }
}
