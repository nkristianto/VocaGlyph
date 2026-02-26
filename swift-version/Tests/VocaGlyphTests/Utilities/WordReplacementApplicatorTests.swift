import XCTest
@testable import VocaGlyph

// MARK: - WordReplacementApplicatorTests

final class WordReplacementApplicatorTests: XCTestCase {

    // MARK: - Basic Substitution (AC #5)

    func test_apply_basicReplacement_substitutesWholeWord() {
        let result = WordReplacementApplicator.apply(
            to: "I'm gonna do it",
            replacements: [(word: "gonna", replacement: "going to")]
        )
        XCTAssertEqual(result, "I'm going to do it")
    }

    func test_apply_caseInsensitive_lowercaseMatch() {
        let result = WordReplacementApplicator.apply(
            to: "Gonna do it",
            replacements: [(word: "gonna", replacement: "going to")]
        )
        XCTAssertEqual(result, "going to do it")
    }

    func test_apply_caseInsensitive_uppercaseMatch() {
        let result = WordReplacementApplicator.apply(
            to: "GONNA do it",
            replacements: [(word: "gonna", replacement: "going to")]
        )
        XCTAssertEqual(result, "going to do it")
    }

    func test_apply_multiplePairs_appliesInOrder() {
        let result = WordReplacementApplicator.apply(
            to: "I wanna gonna",
            replacements: [
                (word: "wanna", replacement: "want to"),
                (word: "gonna", replacement: "going to")
            ]
        )
        XCTAssertEqual(result, "I want to going to")
    }

    func test_apply_repeatedOccurrences_replacesAll() {
        let result = WordReplacementApplicator.apply(
            to: "gonna gonna gonna",
            replacements: [(word: "gonna", replacement: "going to")]
        )
        XCTAssertEqual(result, "going to going to going to")
    }

    // MARK: - Word-Boundary Matching (AC #6)

    func test_apply_partialWord_notAffected() {
        // "can" → "may": should NOT affect "cannot"
        let result = WordReplacementApplicator.apply(
            to: "I cannot do it",
            replacements: [(word: "can", replacement: "may")]
        )
        XCTAssertEqual(result, "I cannot do it")
    }

    func test_apply_partialWord_standaloneMatchesButEmbeddedDoesNot() {
        let result = WordReplacementApplicator.apply(
            to: "can cannot",
            replacements: [(word: "can", replacement: "may")]
        )
        // "can" standalone → replaced; "cannot" should remain
        XCTAssertEqual(result, "may cannot")
    }

    func test_apply_wordBoundary_punctuationAdjacent() {
        // Word immediately followed by punctuation should still match
        let result = WordReplacementApplicator.apply(
            to: "I'm gonna, right?",
            replacements: [(word: "gonna", replacement: "going to")]
        )
        XCTAssertEqual(result, "I'm going to, right?")
    }

    // MARK: - Edge Cases

    func test_apply_emptyReplacements_returnsOriginal() {
        let original = "Hello world"
        let result = WordReplacementApplicator.apply(to: original, replacements: [])
        XCTAssertEqual(result, original)
    }

    func test_apply_emptyText_returnsEmpty() {
        let result = WordReplacementApplicator.apply(
            to: "",
            replacements: [(word: "gonna", replacement: "going to")]
        )
        XCTAssertEqual(result, "")
    }

    func test_apply_noMatch_returnsOriginal() {
        let original = "Hello world"
        let result = WordReplacementApplicator.apply(
            to: original,
            replacements: [(word: "foo", replacement: "bar")]
        )
        XCTAssertEqual(result, original)
    }

    func test_apply_regexMetaCharactersInWord_handledSafely() {
        // Word with regex metacharacters (e.g., ".") should not crash or match wildly
        let result = WordReplacementApplicator.apply(
            to: "hello world",
            replacements: [(word: "h.llo", replacement: "hi")]  // "." should be literal
        )
        // "h.llo" as a literal should not match "hello" (different character at position 2)
        XCTAssertEqual(result, "hello world")
    }

    func test_apply_replacementChaining_notApplied() {
        // Replacements are applied sequentially to the evolving string.
        // "A" → "B", then "B" → "C": "A" may become "C" if chaining occurs.
        // Document this behavior so it's explicit.
        let result = WordReplacementApplicator.apply(
            to: "A",
            replacements: [
                (word: "A", replacement: "B"),
                (word: "B", replacement: "C")
            ]
        )
        // Sequential application: "A" → "B" (first pass), then "B" → "C" (second pass)
        XCTAssertEqual(result, "C")
    }
}
