import XCTest
import AVFoundation
import Speech
@testable import VocaGlyph


final class MockSystemPermissionsProvider: SystemPermissionsProvider, @unchecked Sendable {
    var microphoneStatus: AVAuthorizationStatus = .notDetermined
    var isAccessibilityTrusted: Bool = false
    var speechRecognitionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var didRequestMicrophoneAccess = false
    
    func getMicrophoneAuthorizationStatus() -> AVAuthorizationStatus {
        return microphoneStatus
    }
    
    func requestMicrophoneAccess() async -> Bool {
        didRequestMicrophoneAccess = true
        return true
    }
    
    func checkAccessibilityTrusted() -> Bool {
        return isAccessibilityTrusted
    }
    
    func promptAccessibilityTrusted() -> Bool {
        return isAccessibilityTrusted
    }

    func getSpeechRecognitionAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        return speechRecognitionStatus
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        return speechRecognitionStatus == .authorized
    }
}

final class PermissionsServiceTests: XCTestCase {
    var service: PermissionsService!
    var mockProvider: MockSystemPermissionsProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockSystemPermissionsProvider()
        service = PermissionsService(provider: mockProvider)
    }
    
    override func tearDown() {
        service = nil
        mockProvider = nil
        super.tearDown()
    }
    
    func testAllPermissionsGranted() {
        mockProvider.microphoneStatus = .authorized
        mockProvider.isAccessibilityTrusted = true

        XCTAssertTrue(service.isMicrophoneAuthorized)
        XCTAssertTrue(service.isAccessibilityTrusted)
        XCTAssertTrue(service.areAllCorePermissionsGranted)
    }
    
    func testPermissionsDenied() {
        mockProvider.microphoneStatus = .denied
        mockProvider.isAccessibilityTrusted = false

        XCTAssertFalse(service.isMicrophoneAuthorized)
        XCTAssertFalse(service.isAccessibilityTrusted)
        XCTAssertFalse(service.areAllCorePermissionsGranted)
    }

    func testMicrophoneGrantedAccessibilityDenied() {
        mockProvider.microphoneStatus = .authorized
        mockProvider.isAccessibilityTrusted = false

        XCTAssertTrue(service.isMicrophoneAuthorized)
        XCTAssertFalse(service.areAllCorePermissionsGranted)
    }
}
