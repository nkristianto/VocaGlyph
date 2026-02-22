import XCTest
import AVFoundation
@testable import voice_to_text

final class NativeSpeechEngineTests: XCTestCase {
    
    // Test initialization and protocol conformance
    func testInitializationSucceedsWithoutCrashing() {
        if #available(macOS 15.0, *) {
            let engine = NativeSpeechEngine()
            XCTAssertNotNil(engine)
        } else {
            // Test should pass if not on required OS version
            XCTAssertTrue(true)
        }
    }
}
