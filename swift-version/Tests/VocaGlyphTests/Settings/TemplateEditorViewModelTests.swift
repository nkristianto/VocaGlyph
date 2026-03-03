import XCTest
import SwiftData
@testable import VocaGlyph

// MARK: - TemplateEditorViewModelTests

final class TemplateEditorViewModelTests: XCTestCase {

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PostProcessingTemplate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    @MainActor
    private func makeSUT(container: ModelContainer) -> (TemplateEditorViewModel, PostProcessingTemplate) {
        let template = PostProcessingTemplate(name: "Test Template", isSystem: false)
        container.mainContext.insert(template)
        let sut = TemplateEditorViewModel(modelContext: container.mainContext)
        return (sut, template)
    }

    // MARK: - resetToDefaults

    @MainActor
    func test_resetToDefaults_restoresDefaultPrompt() throws {
        let container = try makeContainer()
        let defaultPrompt = "Fix grammar.\nRemove fillers."
        let template = PostProcessingTemplate(
            name: "General",
            isSystem: true,
            promptText: "Custom edited prompt",
            defaultPrompt: defaultPrompt
        )
        container.mainContext.insert(template)
        let sut = TemplateEditorViewModel(modelContext: container.mainContext)

        sut.resetToDefaults(template: template)

        XCTAssertEqual(template.promptText, defaultPrompt, "promptText should be reset to defaultPrompt")
    }

    @MainActor
    func test_resetToDefaults_updatesTimestamp() throws {
        let container = try makeContainer()
        let template = PostProcessingTemplate(
            name: "General",
            isSystem: true,
            promptText: "Old",
            defaultPrompt: "Default"
        )
        container.mainContext.insert(template)
        let before = template.updatedAt
        let sut = TemplateEditorViewModel(modelContext: container.mainContext)

        sut.resetToDefaults(template: template)

        XCTAssertGreaterThanOrEqual(template.updatedAt, before)
    }

    @MainActor
    func test_resetToDefaults_emptyDefaultPrompt_setsEmptyPromptText() throws {
        let container = try makeContainer()
        let template = PostProcessingTemplate(
            name: "Custom",
            isSystem: false,
            promptText: "Something",
            defaultPrompt: ""
        )
        container.mainContext.insert(template)
        let sut = TemplateEditorViewModel(modelContext: container.mainContext)

        sut.resetToDefaults(template: template)

        XCTAssertEqual(template.promptText, "")
    }
}
