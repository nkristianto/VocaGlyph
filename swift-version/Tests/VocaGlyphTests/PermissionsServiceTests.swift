import XCTest
import AVFoundation
@testable import voice_to_text

final class MockSystemPermissionsProvider: SystemPermissionsProvider, @unchecked Sendable {
    var microphoneStatus: AVAuthorizationStatus = .notDetermined
    var isAccessibilityTrusted: Bool = false
    var isFullDiskAccessGranted: Bool = false
    
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
    
    func checkFullDiskAccess() -> Bool {
        return isFullDiskAccessGranted
    }
    
    func promptFullDiskAccess() {
        // Mock prompt
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
        mockProvider.isFullDiskAccessGranted = true
        
        XCTAssertTrue(service.isMicrophoneAuthorized)
        XCTAssertTrue(service.isAccessibilityTrusted)
        XCTAssertTrue(service.isFullDiskAccessGranted)
        XCTAssertTrue(service.areAllCorePermissionsGranted)
        
        // Also test when FDA is false, core permissions should still be granted
        mockProvider.isFullDiskAccessGranted = false
        XCTAssertTrue(service.areAllCorePermissionsGranted)
    }
    
    func testPermissionsDenied() {
        mockProvider.microphoneStatus = .denied
        mockProvider.isAccessibilityTrusted = false
        mockProvider.isFullDiskAccessGranted = false
        
        XCTAssertFalse(service.isMicrophoneAuthorized)
        XCTAssertFalse(service.isAccessibilityTrusted)
        XCTAssertFalse(service.isFullDiskAccessGranted)
        XCTAssertFalse(service.areAllCorePermissionsGranted)
    }
}
