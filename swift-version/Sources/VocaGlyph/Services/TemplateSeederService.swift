import Foundation
import SwiftData

// MARK: - TemplateSeederService

/// Seeds the four default system `PostProcessingTemplate` records into SwiftData
/// on first launch. This is a no-op if any template already exists in the store.
///
/// **Seeded Templates**
///
/// | Name                    | isSystem | Active by default |
/// |-------------------------|----------|-------------------|
/// | General Cleanup         | true     | ✅ yes             |
/// | Meeting Notes           | true     | no                |
/// | Email                   | true     | no                |
/// | Rewrite                 | true     | no                |
///
/// Call `seedDefaultTemplatesIfNeeded(context:)` once from `AppDelegate`
/// inside `initializeCoreServices()`, after the `ModelContainer` is ready.
/// Then call `migrateSystemTemplatesIfNeeded(context:)` immediately after
/// to ensure Email and Rewrite are present on existing installations.
public enum TemplateSeederService {

    // MARK: - UserDefaults Key

    /// Key used to persist the UUID of the currently active template.
    public static let activeTemplateKey = "activePostProcessingTemplateId"

    // MARK: - Seed

    /// Seeds default templates if none exist (fresh install only).
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
        let email = makeEmail()
        let rewrite = makeRewrite()

        context.insert(generalCleanup)
        context.insert(meetingNotes)
        context.insert(email)
        context.insert(rewrite)

        do {
            try context.save()
            Logger.shared.info("TemplateSeederService: Seeded 4 default templates.")

            // Activate "General Cleanup" by default
            UserDefaults.standard.set(generalCleanup.id.uuidString, forKey: activeTemplateKey)
            Logger.shared.info("TemplateSeederService: Set 'General Cleanup' as active template.")
        } catch {
            Logger.shared.error("TemplateSeederService: Failed to save seeded templates — \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    /// Ensures Email and Rewrite system templates exist on existing installations.
    ///
    /// Safe to call on every launch — it is fully **idempotent**.
    /// Only inserts templates that are missing; never modifies existing ones.
    ///
    /// - Parameter context: The `ModelContext` to use for reads and writes.
    public static func migrateSystemTemplatesIfNeeded(context: ModelContext) {
        var didChange = false

        if fetchTemplate(named: "Email", context: context) == nil {
            Logger.shared.info("TemplateSeederService: Inserting missing 'Email' template.")
            context.insert(makeEmail())
            didChange = true
        }

        if fetchTemplate(named: "Rewrite", context: context) == nil {
            Logger.shared.info("TemplateSeederService: Inserting missing 'Rewrite' template.")
            context.insert(makeRewrite())
            didChange = true
        }

        if didChange {
            do {
                try context.save()
                Logger.shared.info("TemplateSeederService: Migration complete.")
            } catch {
                Logger.shared.error("TemplateSeederService: Migration save failed — \(error.localizedDescription)")
            }
        } else {
            Logger.shared.info("TemplateSeederService: No migration needed, all templates present.")
        }
    }

    // MARK: - Private: Remove Legacy Template

    /// Deletes the "Raw — No Processing" system template from the store if present.
    private static func removeRawTemplateIfPresent(context: ModelContext) {
        let rawName = "Raw — No Processing"
        let descriptor = FetchDescriptor<PostProcessingTemplate>(
            predicate: #Predicate { $0.name == rawName }
        )
        guard let matches = try? context.fetch(descriptor), !matches.isEmpty else { return }
        for template in matches {
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

    // MARK: - Private: Fetch Helper

    private static func fetchTemplate(named name: String, context: ModelContext) -> PostProcessingTemplate? {
        let descriptor = FetchDescriptor<PostProcessingTemplate>(
            predicate: #Predicate { $0.name == name }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Private: Template Factories

    private static func makeGeneralCleanup() -> PostProcessingTemplate {
        let prompt = """
            - Remove filler words: uh, um, like, you know, I mean, I guess, so, actually, basically, literally.
            - Fix capitalization and punctuation.
            - Self-corrections: keep only the corrected wording and drop the original attempt.
            - Keep all sentences and meaning. Never answer questions or add any information.
            - Output only the cleaned text.
            """
        return PostProcessingTemplate(
            name: "General Cleanup",
            templateDescription: "Removes fillers, fixes capitalization and punctuation, and preserves all meaning.",
            isSystem: true,
            promptText: prompt,
            defaultPrompt: prompt
        )
    }

    private static func makeMeetingNotes() -> PostProcessingTemplate {
        let prompt = """
            - Formalize the tone — convert casual language to professional language.
            - Capitalize proper nouns, names, and acronyms.
            - Fix grammar and punctuation.
            - Remove filler words: um, uh, you know, like.
            """
        return PostProcessingTemplate(
            name: "Meeting Notes",
            templateDescription: "Formalizes tone and capitalizes proper nouns for meeting transcriptions.",
            isSystem: true,
            promptText: prompt,
            defaultPrompt: prompt
        )
    }

    private static func makeEmail() -> PostProcessingTemplate {
        let prompt = """
            - Rewrite the transcript as a complete email: include a greeting (Hi), body paragraphs (2–4 sentences each), and closing (Thanks).
            - Use clear, friendly language unless the transcript is clearly professional — in that case, match that tone.
            - Fix grammar and spelling; remove fillers; keep all facts, names, dates, and action items.
            - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
            - Do not invent new content. Don't add any information not in the transcript.
            """
        return PostProcessingTemplate(
            name: "Email",
            templateDescription: "Formats transcription as a complete email with greeting, body paragraphs, and closing.",
            isSystem: true,
            promptText: prompt,
            defaultPrompt: prompt
        )
    }

    private static func makeRewrite() -> PostProcessingTemplate {
        let prompt = """
            - Rewrite the transcript with enhanced clarity, improved sentence structure, and better flow while preserving meaning and tone.
            - Fix grammar and spelling errors; remove fillers and stutters; collapse repetitions.
            - Format lists as proper bullet points or numbered lists. Write numbers as numerals (e.g., 'five' → '5').
            - Organize into well-structured paragraphs of 2–4 sentences.
            - Preserve all names, numbers, dates, and key information exactly.
            - Output only the rewritten text. Don't add any information not in the transcript.
            """
        return PostProcessingTemplate(
            name: "Rewrite",
            templateDescription: "Rewrites transcription with enhanced clarity, improved sentence structure, and better flow while preserving meaning.",
            isSystem: true,
            promptText: prompt,
            defaultPrompt: prompt
        )
    }
}
