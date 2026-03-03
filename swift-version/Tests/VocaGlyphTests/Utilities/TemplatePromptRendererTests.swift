import XCTest
import SwiftData
@testable import VocaGlyph

// MARK: - TemplatePromptRendererTests

/// Tests for `TemplatePromptRenderer`, the stateless utility that converts
/// a `PostProcessingTemplate`'s free-text `promptText` into a structured system prompt.
@MainActor
final class TemplatePromptRendererTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([PostProcessingTemplate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    @MainActor
    private func makeTemplate(promptText: String, context: ModelContext) -> PostProcessingTemplate {
        let template = PostProcessingTemplate(name: "Test Template", promptText: promptText)
        context.insert(template)
        return template
    }

    // MARK: - render() — Core Output

    func testNonEmptyPromptTextRendersWithHeaderAndFooter() throws {
        let context = try makeContext()
        let template = makeTemplate(promptText: "Fix grammar.", context: context)

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertTrue(output.contains("transcription refinement assistant"), "Header should be present")
        XCTAssertTrue(output.contains("Return the corrected text only"), "Footer should be present")
        XCTAssertTrue(output.contains("Fix grammar."), "Prompt text should be included")
    }

    func testMultiLinePromptIsIncludedVerbatim() throws {
        let context = try makeContext()
        let prompt = "Fix grammar.\nRemove fillers.\nEnd with punctuation."
        let template = makeTemplate(promptText: prompt, context: context)

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertTrue(output.contains("Fix grammar."), "Line 1 should be present")
        XCTAssertTrue(output.contains("Remove fillers."), "Line 2 should be present")
        XCTAssertTrue(output.contains("End with punctuation."), "Line 3 should be present")
    }

    // MARK: - render() — Empty / Whitespace

    func testEmptyPromptTextReturnsEmptyString() throws {
        let context = try makeContext()
        let template = makeTemplate(promptText: "", context: context)

        XCTAssertEqual(TemplatePromptRenderer.render(template: template), "")
    }

    func testWhitespaceOnlyPromptReturnsEmptyString() throws {
        let context = try makeContext()
        let template = makeTemplate(promptText: "   \n\t  ", context: context)

        XCTAssertEqual(TemplatePromptRenderer.render(template: template), "")
    }

    // MARK: - promptCharacterCount()

    func testPromptCharacterCountMatchesPromptTextLength() throws {
        let context = try makeContext()
        let prompt = "Fix grammar and capitalization."
        let template = makeTemplate(promptText: prompt, context: context)

        XCTAssertEqual(TemplatePromptRenderer.promptCharacterCount(template: template), prompt.count)
    }

    // MARK: - isOverRecommendedLength()

    func testIsOverRecommendedLengthReturnsTrueWhenExceeded() throws {
        let context = try makeContext()
        let longPrompt = String(repeating: "A", count: TemplatePromptRenderer.maxRecommendedPromptCharacters + 1)
        let template = makeTemplate(promptText: longPrompt, context: context)

        XCTAssertTrue(TemplatePromptRenderer.isOverRecommendedLength(template: template))
    }

    func testIsOverRecommendedLengthReturnsFalseWhenWithinLimit() throws {
        let context = try makeContext()
        let shortPrompt = String(repeating: "A", count: TemplatePromptRenderer.maxRecommendedPromptCharacters)
        let template = makeTemplate(promptText: shortPrompt, context: context)

        XCTAssertFalse(TemplatePromptRenderer.isOverRecommendedLength(template: template))
    }
}
