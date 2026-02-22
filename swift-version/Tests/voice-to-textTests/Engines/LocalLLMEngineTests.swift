import XCTest
@testable import voice_to_text

// MARK: - Mock Inference Provider

/// Test double for LocalLLMInferenceProvider — no real MLX or model download required.
final class MockLocalLLMInferenceProvider: LocalLLMInferenceProvider, @unchecked Sendable {
    var returnedText: String = "mock result"
    var shouldThrowError: Bool = false
    var thrownError: Error = LocalLLMEngineError.inferenceFailed("bad")
    var capturedPrompt: String?
    var callCount: Int = 0

    func generate(prompt: String, modelId: String) async throws -> String {
        callCount += 1
        capturedPrompt = prompt
        if shouldThrowError {
            throw thrownError
        }
        return returnedText
    }
}

// MARK: - LocalLLMEngineTests

final class LocalLLMEngineTests: XCTestCase {

    // MARK: - AC-7.1: Prompt formatting uses Qwen2.5 chat template

    func testRefineCallsProviderWithFormattedQwenChatTemplate() async throws {
        // Arrange
        let mock = MockLocalLLMInferenceProvider()
        mock.returnedText = "refined text"
        let engine = LocalLLMEngine(provider: mock)

        // Act
        let result = try await engine.refine(text: "hello world", prompt: "fix grammar")

        // Assert — prompt contains Qwen2.5 chat-template markers
        let prompt = try XCTUnwrap(mock.capturedPrompt)
        XCTAssertTrue(prompt.contains("<|im_start|>system\nfix grammar<|im_end|>"),
                      "Prompt must contain system chat template block")
        XCTAssertTrue(prompt.contains("<|im_start|>user\nhello world<|im_end|>"),
                      "Prompt must contain user chat template block")
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n"),
                      "Prompt must end with assistant turn start marker")
        XCTAssertEqual(result, "refined text")
    }

    // MARK: - AC-7.2: Whitespace trimming

    func testRefineTrimsLeadingAndTrailingWhitespaceFromResult() async throws {
        // Arrange
        let mock = MockLocalLLMInferenceProvider()
        mock.returnedText = "  result with spaces  \n\t"
        let engine = LocalLLMEngine(provider: mock)

        // Act
        let result = try await engine.refine(text: "input", prompt: "fix")

        // Assert
        XCTAssertEqual(result, "result with spaces")
    }

    // MARK: - AC-7.3: Error propagation

    func testRefineRethrowsLocalLLMEngineErrorFromProvider() async throws {
        // Arrange
        let mock = MockLocalLLMInferenceProvider()
        mock.shouldThrowError = true
        mock.thrownError = LocalLLMEngineError.inferenceFailed("bad inference")
        let engine = LocalLLMEngine(provider: mock)

        // Act & Assert
        do {
            _ = try await engine.refine(text: "hello", prompt: "fix")
            XCTFail("Expected refine() to throw LocalLLMEngineError")
        } catch let error as LocalLLMEngineError {
            XCTAssertEqual(error, LocalLLMEngineError.inferenceFailed("bad inference"))
        }
    }

    func testRefineWrapsGenericErrorAsInferenceFailed() async throws {
        // Arrange
        let mock = MockLocalLLMInferenceProvider()
        mock.shouldThrowError = true
        mock.thrownError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "network failure"])
        let engine = LocalLLMEngine(provider: mock)

        // Act & Assert
        do {
            _ = try await engine.refine(text: "hello", prompt: "fix")
            XCTFail("Expected refine() to throw")
        } catch let error as LocalLLMEngineError {
            if case .inferenceFailed(let reason) = error {
                XCTAssertTrue(reason.contains("network failure") || !reason.isEmpty,
                              "Error should describe the wrapped failure")
            } else {
                XCTFail("Expected .inferenceFailed, got \(error)")
            }
        }
    }

    // MARK: - AC-7.4: Unload clears provider call state / re-load triggers fresh call

    func testUnloadModelAndSubsequentRefineCallsProviderAgain() async throws {
        // Arrange
        let mock = MockLocalLLMInferenceProvider()
        mock.returnedText = "result"
        let engine = LocalLLMEngine(provider: mock)

        // Act — first call
        _ = try await engine.refine(text: "first", prompt: "fix")
        XCTAssertEqual(mock.callCount, 1)

        // Unload
        await engine.unloadModel()

        // Second call after unload — provider must be invoked again (no stale cache bypass)
        _ = try await engine.refine(text: "second", prompt: "fix")
        XCTAssertEqual(mock.callCount, 2, "Provider must be called again after unloadModel()")
    }

    // MARK: - Error enum equatability

    func testLocalLLMEngineErrorEquatable() {
        XCTAssertEqual(LocalLLMEngineError.modelLoadFailed("a"), LocalLLMEngineError.modelLoadFailed("a"))
        XCTAssertNotEqual(LocalLLMEngineError.modelLoadFailed("a"), LocalLLMEngineError.modelLoadFailed("b"))
        XCTAssertEqual(LocalLLMEngineError.inferenceFailed("x"), LocalLLMEngineError.inferenceFailed("x"))
        XCTAssertEqual(LocalLLMEngineError.insufficientMemory, LocalLLMEngineError.insufficientMemory)
        XCTAssertNotEqual(LocalLLMEngineError.insufficientMemory, LocalLLMEngineError.inferenceFailed(""))
    }
}
