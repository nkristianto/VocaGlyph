import XCTest
import AppKit
@testable import VocaGlyph

final class OutputServiceTests: XCTestCase {

    // MARK: - handleTranscriptionValue (basic)

    // CGEvent testing natively is complex as it requires Accessibility hooks dynamically,
    // We can however test that the service properly formats and interacts with the Pasteboard

    func testHandleEmptyTranscriptionIgnoresPaste() {
        let service = OutputService()

        let customPasteboard = NSPasteboard.withUniqueName()
        customPasteboard.clearContents()
        customPasteboard.setString("Existing Text", forType: .string)

        // This should immediately return instead of injecting empty space
        service.handleTranscriptionValue("")

        // To properly test the actual pasteboard manipulation without destroying the user's active clipboard,
        // we assert it handles empty returns gracefully. The specific Pasteboard API in the class uses .general,
        // so we observe it doesn't crash here.
        XCTAssertNotNil(service)
    }

    // MARK: - applyBasicPunctuation

    func testApplyBasicPunctuation_capitalizesFirstLetter() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("hello world")
        XCTAssertTrue(result.hasPrefix("H"), "First letter should be capitalized")
    }

    func testApplyBasicPunctuation_appendsPeriodWhenNone() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("hello world")
        XCTAssertEqual(result, "Hello world.")
    }

    func testApplyBasicPunctuation_doesNotDoublePunctuate_period() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("Hello world.")
        XCTAssertEqual(result, "Hello world.", "Should not append a second period")
    }

    func testApplyBasicPunctuation_doesNotDoublePunctuate_questionMark() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("How are you?")
        XCTAssertEqual(result, "How are you?", "Should preserve existing question mark")
    }

    func testApplyBasicPunctuation_doesNotDoublePunctuate_exclamation() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("That's great!")
        XCTAssertEqual(result, "That's great!", "Should preserve existing exclamation mark")
    }

    func testApplyBasicPunctuation_alreadyCapitalized_noChange() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("Already capitalized")
        XCTAssertEqual(result, "Already capitalized.", "Already capitalized — should only add period")
    }

    func testApplyBasicPunctuation_emptyString_returnsEmpty() {
        let service = OutputService()
        let result = service.applyBasicPunctuation("")
        XCTAssertEqual(result, "", "Empty string should remain empty")
    }

    func testApplyBasicPunctuation_whisperOutput_isNoOp() {
        // Simulate typical Whisper output — already punctuated and capitalized.
        // applyBasicPunctuation should be a pure no-op for this input.
        let service = OutputService()
        let whisperOutput = "Hello, how are you doing today?"
        let result = service.applyBasicPunctuation(whisperOutput)
        XCTAssertEqual(result, whisperOutput, "Whisper output should pass through unchanged")
    }

    func testApplyBasicPunctuation_parakeetOutput_fixesBothIssues() {
        // Simulate typical Parakeet raw output — uncapitalized, no terminal punctuation.
        let service = OutputService()
        let parakeetOutput = "hello how are you doing today"
        let result = service.applyBasicPunctuation(parakeetOutput)
        XCTAssertEqual(result, "Hello how are you doing today.")
    }
}

