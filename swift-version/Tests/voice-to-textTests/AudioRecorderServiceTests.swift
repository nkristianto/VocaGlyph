import XCTest
import AVFoundation
@testable import voice_to_text

final class AudioRecorderServiceTests: XCTestCase {
    
    // Testing AVFoundation services completely from unit tests natively can be tricky as hardware hooks require actual device APIs.
    // However we can test the object's lifespan and buffer flush behavior
    
    func testInitializationSucceedsWithoutCrashing() {
        let service = AudioRecorderService()
        XCTAssertNotNil(service)
    }
    
    func testStopRecordingReturnsEmptyArrayWhenNoAudioSent() {
        let service = AudioRecorderService()
        // Without explicitly calling start() to tap the real mic, stop should cleanly return the empty backing array.
        let output = service.stopRecording()
        XCTAssertTrue(output.isEmpty)
    }
}
