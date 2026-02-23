import XCTest
@testable import VocaGlyph

// MARK: - Sanitize Tests (Level 1: Chatty Preambles)

final class PostProcessingOutputSanitizerTests: XCTestCase {

    // MARK: - sanitize(_:): Clean text passes through unchanged

    func testCleanTextPassesThrough() {
        let input = "Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testEmptyStringPassesThrough() {
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(""), "")
    }

    func testWhitespaceOnlyIsTrimmmed() {
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize("   \n  "), "")
    }

    // MARK: - sanitize(_:): Plain text preambles

    func testStripHereIsTheRevisedText() {
        let input = "Here is the revised text: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripHereIsTheRevisedVersion() {
        let input = "Here is the revised version: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripHereIsTheText() {
        let input = "Here is the text: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripRevisedTextColon() {
        let input = "Revised text: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripRevisedColon() {
        let input = "Revised: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripResultColon() {
        let input = "Result: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripSureHereIsTheRevisedText() {
        let input = "Sure, here is the revised text: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    // MARK: - sanitize(_:): [OUTPUT] framing tag

    func testStripOutputTag() {
        // Model used [OUTPUT] as a response envelope — stray tag should be stripped
        let input = "[OUTPUT]Sure, I'd be happy to help you modify the file."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Sure, I'd be happy to help you modify the file.")
    }

    func testStripOutputTagWithClosingTag() {
        let input = "[OUTPUT]Hello world.[/OUTPUT]"
        // After stripping [output] prefix, remaining is "Hello world.[/OUTPUT]" → sanitizer strips the opening tag
        // The content-within-tags path in stripEchoedFraming handles the full [OUTPUT]...[/OUTPUT] case
        XCTAssertFalse(PostProcessingOutputSanitizer.sanitize(input).isEmpty)
    }

    // MARK: - sanitize(_:): Markdown bold preambles

    func testStripMarkdownBoldRevisedText() {
        let input = "**Revised Text:** Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripMarkdownBoldRevised() {
        let input = "**Revised:** Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripMarkdownBoldHereIsTheRevisedText() {
        let input = "**Here is the revised text:** Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripMarkdownBoldSureHereIsTheRevisedText() {
        // Matches the real sample the user shared: "**Sure, here is the revised text:**"
        let input = "**Sure, here is the revised text:**\nHello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    // MARK: - sanitize(_:): Multiline preamble followed by content

    func testStripPreambleWithNewlineBeforeContent() {
        let input = "Here is the revised text:\nHello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    // MARK: - sanitize(_:): Case-insensitive matching

    func testCaseInsensitiveStrip() {
        let input = "HERE IS THE REVISED TEXT: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testMixedCaseStrip() {
        let input = "Here Is The Revised Text: Hello world."
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    // MARK: - sanitize(_:): Surrounding quotes

    func testStripSurroundingDoubleQuotes() {
        let input = "\"Hello world.\""
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Hello world.")
    }

    func testStripSurroundingQuotesAfterPreamble() {
        // User sample 2: "Here is the revised text: \"Having a use button...\""
        let input = "Here is the revised text: \"Having a use button for the user.\""
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "Having a use button for the user.")
    }

    // MARK: - sanitize(_:): Preamble-only input

    func testOnlyPreambleWithColonReturnsEmpty() {
        let input = "Here is the revised text:"
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "")
    }

    func testOnlyMarkdownPreambleReturnsEmpty() {
        let input = "**Revised Text:**"
        XCTAssertEqual(PostProcessingOutputSanitizer.sanitize(input), "")
    }

    // MARK: - validate(_:against:): Valid output passes through

    func testValidOutputReturnsValid() {
        let result = PostProcessingOutputSanitizer.validate("Hello world.", against: "Hello world")
        XCTAssertEqual(result, .valid("Hello world."))
    }

    // MARK: - validate(_:against:): Level 2 — Refusal detection

    func testSorryICantRefusal() {
        let result = PostProcessingOutputSanitizer.validate(
            "Sorry, I can't assist with that request.",
            against: "Hey what time is it"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testSorryICannotRefusal() {
        let result = PostProcessingOutputSanitizer.validate(
            "Sorry, I cannot assist with that.",
            against: "Some input text"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testSorryButICantRefusal() {
        let result = PostProcessingOutputSanitizer.validate(
            "Sorry, but I can't assist with that.",
            against: "Some input text"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testICannotAssistRefusal() {
        let result = PostProcessingOutputSanitizer.validate(
            "I cannot assist with that type of request.",
            against: "Some input"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testImUnableToRefusal() {
        let result = PostProcessingOutputSanitizer.validate(
            "I'm unable to process that request.",
            against: "Some input"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    // MARK: - validate(_:against:): Compliance responses (model answered the request as a question)

    func testSureIdBeHappyComplianceResponse() {
        // Real sample: user said "Can you open the file and help me modify this"
        // and Apple Intelligence answered it instead of grammar-fixing it
        let result = PostProcessingOutputSanitizer.validate(
            "Sure, I'd be happy to help you modify the file. What would you like to change or add?",
            against: "Can you open the file and help me modify this"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testIdBeHappyToHelpComplianceResponse() {
        let result = PostProcessingOutputSanitizer.validate(
            "I'd be happy to help you with that!",
            against: "Can you summarize this for me"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testOfCourseComplianceResponse() {
        let result = PostProcessingOutputSanitizer.validate(
            "Of course! I'd be happy to help you with that.",
            against: "Can you fix this"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    func testGreatLetsComplianceResponse() {
        let result = PostProcessingOutputSanitizer.validate(
            "Great, let's get started on modifying the file.",
            against: "Help me edit this draft"
        )
        XCTAssertEqual(result, .fallback(reason: .refusal))
    }

    // MARK: - validate(_:against:): Level 3 — Hallucination / length explosion

    func testHallucinationDetectedWhenOutputIsThreePlusTimesLonger() {
        let shortInput = "Hey check this out" // 18 chars
        // 18 * 3 + 200 = 254 chars threshold — create output > 254 chars
        let hallucinatedOutput = String(repeating: "The model invented this. ", count: 15) // 375 chars
        let result = PostProcessingOutputSanitizer.validate(hallucinatedOutput, against: shortInput)
        XCTAssertEqual(result, .fallback(reason: .hallucination))
    }

    func testNormalLengthOutputPassesValidation() {
        let input = "Fix the grammar of this sentence please make it better"
        let refinedOutput = "Please fix the grammar of this sentence and make it better."
        let result = PostProcessingOutputSanitizer.validate(refinedOutput, against: input)
        XCTAssertEqual(result, .valid(refinedOutput))
    }

    func testSlightlyLongerOutputIsAllowed() {
        // A punctuation/grammar fix can make text somewhat longer — that's fine
        let input = "i went to the store and bought milk eggs and bread"
        let refined = "I went to the store and bought milk, eggs, and bread."
        let result = PostProcessingOutputSanitizer.validate(refined, against: input)
        XCTAssertEqual(result, .valid(refined))
    }

    // MARK: - validate(_:against:): Empty edge cases

    func testEmptyOutputWithEmptyInputIsValid() {
        let result = PostProcessingOutputSanitizer.validate("", against: "")
        XCTAssertEqual(result, .valid(""))
    }
}
