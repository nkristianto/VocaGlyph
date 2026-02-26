import XCTest
import SwiftData
@testable import VocaGlyph

// MARK: - WordReplacementViewModelTests

final class WordReplacementViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([WordReplacement.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    @MainActor
    private func makeSUT(container: ModelContainer) -> WordReplacementViewModel {
        WordReplacementViewModel(modelContext: container.mainContext)
    }

    // MARK: - addReplacement (AC #3)

    @MainActor
    func test_addReplacement_validInputs_insertsRecord() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "gonna", replacement: "going to")

        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.word, "gonna")
        XCTAssertEqual(items.first?.replacement, "going to")
    }

    @MainActor
    func test_addReplacement_emptyWord_doesNotInsert() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "   ", replacement: "going to")

        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertTrue(items.isEmpty)
    }

    @MainActor
    func test_addReplacement_emptyReplacement_doesNotInsert() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "gonna", replacement: "  ")

        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertTrue(items.isEmpty)
    }

    @MainActor
    func test_addReplacement_trimsWhitespace_beforeInserting() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "  gonna  ", replacement: "  going to  ")

        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertEqual(items.first?.word, "gonna")
        XCTAssertEqual(items.first?.replacement, "going to")
    }

    @MainActor
    func test_addReplacement_newRecord_isEnabledByDefault() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "gonna", replacement: "going to")

        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertTrue(items.first?.isEnabled ?? false)
    }

    // MARK: - deleteReplacement (AC #10)

    @MainActor
    func test_deleteReplacement_removesFromContext() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "gonna", replacement: "going to")
        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        guard let item = items.first else { XCTFail("Expected a record"); return }

        sut.deleteReplacement(item)

        let remaining = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - toggleEnabled (AC #9)

    @MainActor
    func test_toggleEnabled_true_becomesDisabled() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "gonna", replacement: "going to")
        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        guard let item = items.first else { XCTFail("Expected a record"); return }

        XCTAssertTrue(item.isEnabled) // Precondition
        sut.toggleEnabled(item)
        XCTAssertFalse(item.isEnabled)
    }

    @MainActor
    func test_toggleEnabled_false_becomesEnabled() throws {
        let container = try makeContainer()
        let sut = makeSUT(container: container)

        sut.addReplacement(word: "gonna", replacement: "going to")
        let items = try container.mainContext.fetch(FetchDescriptor<WordReplacement>())
        guard let item = items.first else { XCTFail("Expected a record"); return }

        sut.toggleEnabled(item)      // → false
        sut.toggleEnabled(item)      // → true
        XCTAssertTrue(item.isEnabled)
    }
}
