import XCTest
import SwiftData
@testable import VocaGlyph

// MARK: - TemplatePromptRendererTests

/// Tests for `TemplatePromptRenderer`, the stateless utility that converts
/// a `PostProcessingTemplate` into a structured, numbered system prompt.
@MainActor
final class TemplatePromptRendererTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an in-memory SwiftData container for testing.
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([PostProcessingTemplate.self, TemplateRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    /// Creates a template with the given rule instructions (all enabled by default).
    @MainActor
    private func makeTemplate(
        rules: [(order: Int, instruction: String, isEnabled: Bool)] = [],
        context: ModelContext
    ) -> PostProcessingTemplate {
        let template = PostProcessingTemplate(name: "Test Template")
        context.insert(template)
        for rule in rules {
            let r = TemplateRule(order: rule.order, instruction: rule.instruction, isEnabled: rule.isEnabled)
            r.template = template
            template.rules.append(r)
            context.insert(r)
        }
        return template
    }

    // MARK: - render() — Core Output

    func testThreeEnabledRulesProduceNumberedOutput() throws {
        let context = try makeContext()
        let template = makeTemplate(
            rules: [
                (1, "Fix grammar and capitalization.", true),
                (2, "Remove filler words: um, uh.", true),
                (3, "End with proper punctuation.", true),
            ],
            context: context
        )

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertTrue(output.contains("1. Fix grammar and capitalization."), "Rule 1 should appear as '1.'")
        XCTAssertTrue(output.contains("2. Remove filler words: um, uh."), "Rule 2 should appear as '2.'")
        XCTAssertTrue(output.contains("3. End with proper punctuation."), "Rule 3 should appear as '3.'")
    }

    func testRenderedOutputContainsHeaderAndFooter() throws {
        let context = try makeContext()
        let template = makeTemplate(
            rules: [(1, "Fix grammar.", true)],
            context: context
        )

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertTrue(output.contains("transcription refinement assistant"), "Header should be present")
        XCTAssertTrue(output.contains("Return the corrected text only"), "Footer should be present")
    }

    // MARK: - render() — Disabled Rules Excluded

    func testDisabledRulesAreExcluded() throws {
        let context = try makeContext()
        let template = makeTemplate(
            rules: [
                (1, "Fix grammar.", true),
                (2, "Remove filler words.", false),  // disabled
                (3, "End with punctuation.", true),
            ],
            context: context
        )

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertTrue(output.contains("Fix grammar."), "Enabled rule 1 should be included")
        XCTAssertFalse(output.contains("Remove filler words."), "Disabled rule 2 should be excluded")
        XCTAssertTrue(output.contains("End with punctuation."), "Enabled rule 3 should be included")
    }

    func testOnlyDisabledRulesReturnsEmptyString() throws {
        let context = try makeContext()
        let template = makeTemplate(
            rules: [
                (1, "Fix grammar.", false),
                (2, "Remove filler words.", false),
            ],
            context: context
        )

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertEqual(output, "", "All disabled rules should produce empty string")
    }

    // MARK: - render() — No Rules

    func testEmptyTemplateReturnsEmptyString() throws {
        let context = try makeContext()
        let template = makeTemplate(rules: [], context: context)

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertEqual(output, "", "Template with no rules should produce empty string")
    }

    // MARK: - render() — Ordering

    func testRulesRenderedInOrderFieldAscending() throws {
        let context = try makeContext()
        // Insert in reverse order — renderer must sort by `order`
        let template = makeTemplate(
            rules: [
                (3, "Rule C", true),
                (1, "Rule A", true),
                (2, "Rule B", true),
            ],
            context: context
        )

        let output = TemplatePromptRenderer.render(template: template)

        let indexA = output.range(of: "Rule A")!.lowerBound
        let indexB = output.range(of: "Rule B")!.lowerBound
        let indexC = output.range(of: "Rule C")!.lowerBound

        XCTAssertTrue(indexA < indexB, "Rule A (order 1) should appear before Rule B (order 2)")
        XCTAssertTrue(indexB < indexC, "Rule B (order 2) should appear before Rule C (order 3)")
    }

    func testRulesRenumberedSequentiallyByPosition() throws {
        let context = try makeContext()
        // Even with gaps in `order` (1, 3, 5), the rendered numbers should be 1, 2, 3
        let template = makeTemplate(
            rules: [
                (1, "First rule.", true),
                (3, "Third rule.", true),
                (5, "Fifth rule.", true),
            ],
            context: context
        )

        let output = TemplatePromptRenderer.render(template: template)

        XCTAssertTrue(output.contains("1. First rule."), "First position should render as '1.'")
        XCTAssertTrue(output.contains("2. Third rule."), "Second position should render as '2.'")
        XCTAssertTrue(output.contains("3. Fifth rule."), "Third position should render as '3.'")
    }

    // MARK: - totalRuleCharacters()

    func testTotalRuleCharactersCountsOnlyEnabledRules() throws {
        let context = try makeContext()
        let template = makeTemplate(
            rules: [
                (1, "AAAA", true),   // 4 chars — enabled
                (2, "BBBB", false),  // 4 chars — disabled, should not count
                (3, "CCCC", true),   // 4 chars — enabled
            ],
            context: context
        )

        let total = TemplatePromptRenderer.totalRuleCharacters(template: template)

        XCTAssertEqual(total, 8, "Only enabled rules (4+4=8) should be counted")
    }

    // MARK: - isOverRecommendedLength()

    func testIsOverRecommendedLengthReturnsTrueWhenExceeded() throws {
        let context = try makeContext()
        // Create rule that exceeds maxRecommendedRuleCharacters
        let longInstruction = String(repeating: "A", count: TemplatePromptRenderer.maxRecommendedRuleCharacters + 1)
        let template = makeTemplate(
            rules: [(1, longInstruction, true)],
            context: context
        )

        XCTAssertTrue(
            TemplatePromptRenderer.isOverRecommendedLength(template: template),
            "Template exceeding 800 chars should be flagged as over recommended length"
        )
    }

    func testIsOverRecommendedLengthReturnsFalseWhenWithinLimit() throws {
        let context = try makeContext()
        let shortInstruction = String(repeating: "A", count: TemplatePromptRenderer.maxRecommendedRuleCharacters)
        let template = makeTemplate(
            rules: [(1, shortInstruction, true)],
            context: context
        )

        XCTAssertFalse(
            TemplatePromptRenderer.isOverRecommendedLength(template: template),
            "Template at exactly maxRecommendedRuleCharacters should NOT be flagged"
        )
    }

    func testIsOverRecommendedLengthIgnoresDisabledRules() throws {
        let context = try makeContext()
        // Long disabled rule — should not trigger the warning
        let longInstruction = String(repeating: "A", count: TemplatePromptRenderer.maxRecommendedRuleCharacters + 100)
        let template = makeTemplate(
            rules: [(1, longInstruction, false)],
            context: context
        )

        XCTAssertFalse(
            TemplatePromptRenderer.isOverRecommendedLength(template: template),
            "Disabled rules should not count toward the length limit"
        )
    }
}
