import XCTest
import AVFoundation
@testable import voice_to_text

class MockTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    var shouldThrowError = false
    var returnedText = "Mocked Transcription"
    var didCallTranscribe = false
    
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        didCallTranscribe = true
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: nil)
        }
        return returnedText
    }
}

final class EngineRouterTests: XCTestCase {
    
    func testEngineRouterForwardsTranscribe() async throws {
        let mockEngine = MockTranscriptionEngine()
        let router = EngineRouter(engine: mockEngine)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        let result = try await router.transcribe(audioBuffer: buffer)
        
        XCTAssertTrue(mockEngine.didCallTranscribe)
        XCTAssertEqual(result, "Mocked Transcription")
    }
    
    func testEngineRouterThrowsWhenEngineThrows() async {
        let mockEngine = MockTranscriptionEngine()
        mockEngine.shouldThrowError = true
        let router = EngineRouter(engine: mockEngine)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        do {
            _ = try await router.transcribe(audioBuffer: buffer)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertNotNil(error)
        }
        XCTAssertTrue(mockEngine.didCallTranscribe)
    }
    
    func testEngineRouterCanHotSwapEngines() async throws {
        let mockEngine1 = MockTranscriptionEngine()
        mockEngine1.returnedText = "Engine 1"
        
        let mockEngine2 = MockTranscriptionEngine()
        mockEngine2.returnedText = "Engine 2"
        
        let router = EngineRouter(engine: mockEngine1)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        let result1 = try await router.transcribe(audioBuffer: buffer)
        XCTAssertEqual(result1, "Engine 1")
        
        await router.setEngine(mockEngine2)
        
        let result2 = try await router.transcribe(audioBuffer: buffer)
        XCTAssertEqual(result2, "Engine 2")
    }
}
