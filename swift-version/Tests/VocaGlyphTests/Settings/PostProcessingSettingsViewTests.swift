import XCTest
import SwiftData
@testable import VocaGlyph

// MARK: - PostProcessingSettingsViewTests
// Tests the commitNewTemplate() logic extracted from PostProcessingSettingsView.
// We test the business-logic directly by reproducing the exact same produce in
// an in-memory container — no SwiftUI hosting required.

final class PostProcessingSettingsViewTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PostProcessingTemplate.self, TemplateRule.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Mimics PostProcessingSettingsView.commitNewTemplate(name:) without SwiftUI.
    @MainActor
    private func commitNewTemplate(name: String, context: ModelContext,
                                    activeTemplateKey: String = TemplateSeederService.activeTemplateKey) -> PostProcessingTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = PostProcessingTemplate(name: trimmed.isEmpty ? "Untitled" : trimmed, isSystem: false)
        context.insert(template)
        UserDefaults.standard.set(template.id.uuidString, forKey: activeTemplateKey)
        return template
    }

    // MARK: - Name Trimming

    @MainActor
    func test_commitNewTemplate_emptyName_fallsBackToUntitled() throws {
        let container = try makeContainer()
        let template = commitNewTemplate(name: "", context: container.mainContext)
        XCTAssertEqual(template.name, "Untitled")
    }

    @MainActor
    func test_commitNewTemplate_whitespaceOnlyName_fallsBackToUntitled() throws {
        let container = try makeContainer()
        let template = commitNewTemplate(name: "   \n   ", context: container.mainContext)
        XCTAssertEqual(template.name, "Untitled")
    }

    @MainActor
    func test_commitNewTemplate_validName_usesProvidedName() throws {
        let container = try makeContainer()
        let template = commitNewTemplate(name: "Customer Emails", context: container.mainContext)
        XCTAssertEqual(template.name, "Customer Emails")
    }

    @MainActor
    func test_commitNewTemplate_leadingTrailingSpaces_trimmed() throws {
        let container = try makeContainer()
        let template = commitNewTemplate(name: "  Technical Docs  ", context: container.mainContext)
        XCTAssertEqual(template.name, "Technical Docs")
    }

    // MARK: - Template Properties

    @MainActor
    func test_commitNewTemplate_newTemplate_isNotSystem() throws {
        let container = try makeContainer()
        let template = commitNewTemplate(name: "My Template", context: container.mainContext)
        XCTAssertFalse(template.isSystem)
    }

    @MainActor
    func test_commitNewTemplate_setsActiveTemplateInUserDefaults() throws {
        let container = try makeContainer()
        let testKey = "test_active_template_\(UUID().uuidString)"
        let template = commitNewTemplate(name: "My Template", context: container.mainContext, activeTemplateKey: testKey)
        let stored = UserDefaults.standard.string(forKey: testKey)
        XCTAssertEqual(stored, template.id.uuidString)
        UserDefaults.standard.removeObject(forKey: testKey) // cleanup
    }

    @MainActor
    func test_commitNewTemplate_insertsTemplateIntoContext() throws {
        let container = try makeContainer()
        let template = commitNewTemplate(name: "My Template", context: container.mainContext)
        // Verify we can fetch it back
        let descriptor = FetchDescriptor<PostProcessingTemplate>(
            predicate: #Predicate { $0.name == "My Template" }
        )
        let results = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(results.first?.id, template.id)
    }
}
