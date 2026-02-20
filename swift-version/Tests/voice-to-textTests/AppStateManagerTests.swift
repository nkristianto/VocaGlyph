import XCTest
@testable import voice_to_text

class MockAppStateManagerDelegate: AppStateManagerDelegate {
    var lastStateReceived: AppState?
    
    func appStateDidChange(newState: AppState) {
        lastStateReceived = newState
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
}
