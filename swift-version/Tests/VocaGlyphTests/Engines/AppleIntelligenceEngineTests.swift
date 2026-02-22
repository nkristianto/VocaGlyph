import XCTest
@testable import voice_to_text

final class AppleIntelligenceEngineTests: XCTestCase {

    // MARK: - Legacy Stub Tests (always run, any OS)

    func testLegacyStubAlwaysThrowsUnsupportedOSVersion() async {
        let stub = AppleIntelligenceLegacyStub()

        do {
            _ = try await stub.refine(text: "Hello world", prompt: "Fix grammar")
            XCTFail("Legacy stub should always throw — it never succeeds")
        } catch let error as AppleIntelligenceError {
            XCTAssertEqual(error, .unsupportedOSVersion,
                "Legacy stub must throw .unsupportedOSVersion to allow orchestrator fallback")
        } catch {
            XCTFail("Legacy stub threw an unexpected error type: \(error)")
        }
    }

    func testLegacyStubUnsupportedOSVersionHasDescriptiveMessage() {
        let error = AppleIntelligenceError.unsupportedOSVersion
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("macOS 26"), "Error message should mention macOS 26 requirement")
        XCTAssertFalse(description.isEmpty, "Error description should not be empty")
    }

    // MARK: - Error Enum Tests

    func testErrorDescriptions() {
        XCTAssertNotNil(AppleIntelligenceError.unsupportedOSVersion.errorDescription)
        XCTAssertNotNil(AppleIntelligenceError.deviceNotEligible.errorDescription)
        XCTAssertNotNil(AppleIntelligenceError.appleIntelligenceNotEnabled.errorDescription)
        XCTAssertNotNil(AppleIntelligenceError.modelNotReady.errorDescription)
        XCTAssertNotNil(AppleIntelligenceError.inferenceFailed("test").errorDescription)
    }

    func testDeviceNotEligibleDescription() {
        let error = AppleIntelligenceError.deviceNotEligible
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Apple Silicon") || desc.contains("M1"),
            "deviceNotEligible should mention Apple Silicon requirement")
    }

    func testAppleIntelligenceNotEnabledDescription() {
        let error = AppleIntelligenceError.appleIntelligenceNotEnabled
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("System Settings"),
            "notEnabled error should guide user to System Settings")
    }

    // MARK: - macOS 26+ Engine Tests (will be skipped on earlier OS)

    @available(macOS 26.0, *)
    func testEngineThrowsWhenModelUnavailable() async throws {
        // On a real macOS 26 system where Apple Intelligence is not enabled or
        // device is not eligible, verify the engine throws a typed AppleIntelligenceError
        // rather than crashing or returning raw text.
        // NOTE: This test documents expected behavior; CI on macOS < 26 will skip this.
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Foundation Models requires macOS 26.0+")
        }

        let engine = AppleIntelligenceEngine()

        // If this machine has Apple Intelligence properly enabled, refine may succeed.
        // If not, it must throw a typed AppleIntelligenceError (not a generic error).
        do {
            let result = try await engine.refine(text: "hello world", prompt: "")
            // If it succeeds, the result must be a non-empty string
            XCTAssertFalse(result.isEmpty, "Successful refinement should return non-empty text")
        } catch let error as AppleIntelligenceError {
            // All failures must surface as typed AppleIntelligenceError cases
            let validErrors: [AppleIntelligenceError] = [
                .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
                .unsupportedOSVersion
            ]
            let isValidError = validErrors.contains(where: {
                // Use string comparison since inferenceFailed has associated value
                $0.errorDescription == error.errorDescription
                || error == .deviceNotEligible
                || error == .appleIntelligenceNotEnabled
                || error == .modelNotReady
                || error == .unsupportedOSVersion
            })
            XCTAssertTrue(isValidError, "Engine must throw a typed AppleIntelligenceError, got: \(error)")
        } catch {
            XCTFail("Engine must throw AppleIntelligenceError, not \(type(of: error)): \(error)")
        }
    }
}
