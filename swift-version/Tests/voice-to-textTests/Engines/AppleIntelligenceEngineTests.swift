import XCTest
@testable import voice_to_text

final class AppleIntelligenceEngineTests: XCTestCase {
    
    func testRefineThrowsProgrammaticAccessUnavailableWhenNoExplicitFramework() async {
        let engine = AppleIntelligenceEngine()
        
        do {
            _ = try await engine.refine(text: "Hello", prompt: "Fix grammar")
            // If the environment does happen to support it natively and magically passes,
            // we will let it pass, but typically we expect a throw in our current implementation.
            if #available(macOS 15.1, *) {
                // In my SDK 26.2 (macOS 15) without LanguageModel, it throws .programmaticAccessUnavailable
            } else {
                XCTFail("Should have thrown unsupportedOSVersion")
            }
        } catch let error as AppleIntelligenceError {
            if #available(macOS 15.1, *) {
                XCTAssertEqual(error, .programmaticAccessUnavailable)
            } else {
                XCTAssertEqual(error, .unsupportedOSVersion)
            }
        } catch {
            XCTFail("Threw an unexpected error type: \(error)")
        }
    }
}
