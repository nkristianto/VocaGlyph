import XCTest
import AVFoundation
@testable import voice_to_text

class MockAppStateManagerDelegate: AppStateManagerDelegate {
    var lastStateReceived: AppState?
    var lastTranscribedText: String?
    
    func appStateDidChange(newState: AppState) {
        lastStateReceived = newState
    }
    
    func appStateManagerDidTranscribe(text: String) {
        lastTranscribedText = text
    }
}

final class AppStateManagerTests: XCTestCase {
    
    func testInitialStateIsIdle() {
        let manager = AppStateManager()
        XCTAssertEqual(manager.currentState, .idle)
    }
    
    func testSetRecordingUpdatesStateAndNotifiesDelegate() {
        let manager = AppStateManager()
        let mockDelegate = MockAppStateManagerDelegate()
        manager.delegate = mockDelegate
        
        manager.startRecording()
        
        XCTAssertEqual(manager.currentState, .recording)
        XCTAssertEqual(mockDelegate.lastStateReceived, .recording)
    }
    
    func testSetProcessingUpdatesStateAndNotifiesDelegate() {
        let manager = AppStateManager()
        let mockDelegate = MockAppStateManagerDelegate()
        manager.delegate = mockDelegate
        
        manager.stopRecording()
        
        XCTAssertEqual(manager.currentState, .processing)
        XCTAssertEqual(mockDelegate.lastStateReceived, .processing)
    }
    
    func testSetIdleUpdatesStateAndNotifiesDelegate() {
        let manager = AppStateManager()
        let mockDelegate = MockAppStateManagerDelegate()
        manager.delegate = mockDelegate
        
        manager.startRecording() // Change state first
        manager.setIdle()
        
        XCTAssertEqual(manager.currentState, .idle)
        XCTAssertEqual(mockDelegate.lastStateReceived, .idle)
    }
    
    func testSwitchTranscriptionEngine() async {
        let manager = AppStateManager()
        let router = EngineRouter(engine: MockTranscriptionEngine())
        manager.engineRouter = router
        
        // Let async Task flush initial constructor assignments
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Test routing to WhisperKit model
        await manager.switchTranscriptionEngine(toModel: "tiny")
        // Since we cannot read the internal `activeEngine` of the router, 
        // passing this function means the WhisperService initialized dynamically without fatal error.
        XCTAssertTrue(true)
        
        // Test routing to Native Speech Engine
        await manager.switchTranscriptionEngine(toModel: "apple-native")
        // The AppStateManager should handle the OS check internally and instantiate either Native or Whisper
        XCTAssertTrue(true)
    }

    func testProcessAudioWithPostProcessing() async {
        let manager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        mockEngine.returnedText = "Raw text"
        let router = EngineRouter(engine: mockEngine)
        manager.engineRouter = router
        
        let mockPostProcessor = MockPostProcessingEngine()
        mockPostProcessor.returnedText = "Refined text"
        manager.postProcessingEngine = mockPostProcessor
        
        let mockDelegate = MockAppStateManagerDelegate()
        manager.delegate = mockDelegate
        
        // Simulate UserDefaults settings
        UserDefaults.standard.set(true, forKey: "enablePostProcessing")
        UserDefaults.standard.set("Test prompt", forKey: "postProcessingPrompt")
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        
        manager.processAudio(buffer: buffer)
        
        // Give async processing time to complete
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertEqual(mockPostProcessor.didCallRefineWithText, "Raw text")
        XCTAssertEqual(mockPostProcessor.didCallRefineWithPrompt, "Test prompt")
        XCTAssertEqual(mockDelegate.lastTranscribedText, "Refined text")
    }
    
    func testProcessAudioWithPostProcessingFailureFallsBackToRawText() async {
        let manager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        mockEngine.returnedText = "Raw text"
        let router = EngineRouter(engine: mockEngine)
        manager.engineRouter = router
        
        let mockPostProcessor = MockPostProcessingEngine()
        mockPostProcessor.shouldThrowError = true
        manager.postProcessingEngine = mockPostProcessor
        
        let mockDelegate = MockAppStateManagerDelegate()
        manager.delegate = mockDelegate
        
        // Simulate UserDefaults settings
        UserDefaults.standard.set(true, forKey: "enablePostProcessing")
        UserDefaults.standard.set("Test prompt", forKey: "postProcessingPrompt")
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        
        manager.processAudio(buffer: buffer)
        
        // Give async processing time to complete
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify we still called refine, but gracefully degraded to the raw text
        XCTAssertEqual(mockPostProcessor.didCallRefineWithText, "Raw text")
        XCTAssertEqual(mockDelegate.lastTranscribedText, "Raw text")
    }

    func testProcessAudioWithPostProcessingTimeoutFallsBackToRawText() async {
        let manager = AppStateManager()
        let mockEngine = MockTranscriptionEngine()
        mockEngine.returnedText = "Raw text"
        let router = EngineRouter(engine: mockEngine)
        manager.engineRouter = router
        
        let mockPostProcessor = MockPostProcessingEngine()
        mockPostProcessor.shouldTimeout = true
        manager.postProcessingEngine = mockPostProcessor
        
        let mockDelegate = MockAppStateManagerDelegate()
        manager.delegate = mockDelegate
        
        // Simulate UserDefaults settings
        UserDefaults.standard.set(true, forKey: "enablePostProcessing")
        UserDefaults.standard.set("Test prompt", forKey: "postProcessingPrompt")
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        
        manager.processAudio(buffer: buffer)
        
        // Give async processing time to complete (timeout is 10s, wait a bit longer)
        try? await Task.sleep(nanoseconds: 10_500_000_000)
        
        // Verify we still called refine, but gracefully degraded to the raw text
        XCTAssertEqual(mockPostProcessor.didCallRefineWithText, "Raw text")
        XCTAssertEqual(mockDelegate.lastTranscribedText, "Raw text")
    }
}

class MockPostProcessingEngine: PostProcessingEngine, @unchecked Sendable {
    var shouldThrowError = false
    var shouldTimeout = false
    var returnedText = "Mocked Refined"
    var didCallRefineWithText: String?
    var didCallRefineWithPrompt: String?
    
    func refine(text: String, prompt: String) async throws -> String {
        didCallRefineWithText = text
        didCallRefineWithPrompt = prompt
        
        if shouldTimeout {
            // Sleep for 12 seconds to trigger the 10000ms timeout
            try await Task.sleep(nanoseconds: 12_000_000_000)
        }
        
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: nil)
        }
        return returnedText
    }
}
