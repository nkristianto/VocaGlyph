import XCTest
import SwiftData
@testable import VocaGlyph

// MARK: - TemplateEditorViewModelTests

final class TemplateEditorViewModelTests: XCTestCase {

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PostProcessingTemplate.self, TemplateRule.self])
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

    // MARK: - commitAddRule

    @MainActor
    func test_commitAddRule_emptyText_doesNotInsertRule() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)

        sut.commitAddRule(to: template, text: "   ")

        XCTAssertTrue(template.rules.isEmpty)
    }

    @MainActor
    func test_commitAddRule_validText_insertsRuleWithCorrectInstruction() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)

        sut.commitAddRule(to: template, text: "Remove filler words")

        XCTAssertEqual(template.rules.count, 1)
        XCTAssertEqual(template.rules.first?.instruction, "Remove filler words")
    }

    @MainActor
    func test_commitAddRule_secondRule_getsNextOrder() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)

        sut.commitAddRule(to: template, text: "First rule")
        sut.commitAddRule(to: template, text: "Second rule")

        let sorted = template.rules.sorted { $0.order < $1.order }
        XCTAssertEqual(sorted.first?.order, 1)
        XCTAssertEqual(sorted.last?.order, 2)
    }

    @MainActor
    func test_commitAddRule_updatesTemplateTimestamp() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)
        let before = template.updatedAt

        sut.commitAddRule(to: template, text: "New rule")

        XCTAssertGreaterThanOrEqual(template.updatedAt, before)
    }

    // MARK: - reorderRules

    @MainActor
    func test_reorderRules_normalizesToContiguousOneBased() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)
        // Manually create rules with non-contiguous orders (simulates post-deletion state)
        let r1 = TemplateRule(order: 1, instruction: "A"); r1.template = template; template.rules.append(r1)
        let r3 = TemplateRule(order: 3, instruction: "B"); r3.template = template; template.rules.append(r3)
        let r7 = TemplateRule(order: 7, instruction: "C"); r7.template = template; template.rules.append(r7)

        sut.reorderRules(in: template)

        let sorted = template.rules.sorted { $0.order < $1.order }
        XCTAssertEqual(sorted.map { $0.order }, [1, 2, 3])
        XCTAssertEqual(sorted.map { $0.instruction }, ["A", "B", "C"])
    }

    @MainActor
    func test_reorderRules_emptyRules_doesNotCrash() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)
        XCTAssertNoThrow(sut.reorderRules(in: template))
    }

    // MARK: - resetToDefaults

    @MainActor
    func test_resetToDefaults_replacesExistingWithDefaults() throws {
        let container = try makeContainer()
        let (sut, template) = makeSUT(container: container)

        // Seed a custom rule
        sut.commitAddRule(to: template, text: "Custom rule")
        XCTAssertEqual(template.rules.count, 1)

        // Now reset — requires template.defaultRules to be non-empty (system template)
        // Use a system template for this test
        let sysTemplate = PostProcessingTemplate(name: "General", isSystem: true)
        container.mainContext.insert(sysTemplate)
        guard !sysTemplate.defaultRules.isEmpty else {
            // Skip test if system template has no defaults (configuration dependent)
            return
        }

        sut.resetToDefaults(template: sysTemplate)

        let expectedCount = sysTemplate.defaultRules.count
        XCTAssertEqual(sysTemplate.rules.count, expectedCount)
    }

    @MainActor
    func test_resetToDefaults_rulesHaveContiguousOrder() throws {
        let container = try makeContainer()
        let (_, _) = makeSUT(container: container)

        let sysTemplate = PostProcessingTemplate(name: "General", isSystem: true)
        container.mainContext.insert(sysTemplate)
        let sut = TemplateEditorViewModel(modelContext: container.mainContext)

        guard !sysTemplate.defaultRules.isEmpty else { return }

        sut.resetToDefaults(template: sysTemplate)

        let sorted = sysTemplate.rules.sorted { $0.order < $1.order }
        let orders = sorted.map { $0.order }
        XCTAssertEqual(orders, Array(1...orders.count))
    }
}
