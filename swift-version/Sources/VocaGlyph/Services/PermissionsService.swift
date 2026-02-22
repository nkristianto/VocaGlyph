import Foundation
import AppKit
import AVFoundation

@Observable
final class PermissionsService {
    
    // Abstracted provider for testing
    private let provider: SystemPermissionsProvider
    
    init(provider: SystemPermissionsProvider = DefaultSystemPermissionsProvider()) {
        self.provider = provider
    }
    
    var isMicrophoneAuthorized: Bool {
        return provider.getMicrophoneAuthorizationStatus() == .authorized
    }
    
    var isAccessibilityTrusted: Bool {
        return provider.checkAccessibilityTrusted()
    }
    
    var isFullDiskAccessGranted: Bool {
        return provider.checkFullDiskAccess()
    }
    
    var areAllCorePermissionsGranted: Bool {
        return isMicrophoneAuthorized && isAccessibilityTrusted
    }
    
    func requestMicrophoneAccess() async -> Bool {
        return await provider.requestMicrophoneAccess()
    }
    
    func promptAccessibilityTrusted() -> Bool {
        return provider.promptAccessibilityTrusted()
    }
    
    func promptFullDiskAccess() {
        provider.promptFullDiskAccess()
    }
}

struct DefaultSystemPermissionsProvider: SystemPermissionsProvider {
    func getMicrophoneAuthorizationStatus() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestMicrophoneAccess() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    func checkAccessibilityTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func promptAccessibilityTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func checkFullDiskAccess() -> Bool {
        // macOS doesn't have a direct API for FDA. 
        // Best practice is to check a known restricted directory.
        let path = NSString(string: "~/Library/Safari/Bookmarks.plist").expandingTildeInPath
        let isReadable = FileManager.default.isReadableFile(atPath: path)
        return isReadable
    }
    
    func promptFullDiskAccess() {
        // Explicitly attempt to read protected files to trigger TCC into adding
        // the application to the System Settings "Full Disk Access" list.
        let safariPath = NSString(string: "~/Library/Safari/Bookmarks.plist").expandingTildeInPath
        _ = try? Data(contentsOf: URL(fileURLWithPath: safariPath))
        
        let messagesPath = NSString(string: "~/Library/Messages").expandingTildeInPath
        _ = try? FileManager.default.contentsOfDirectory(atPath: messagesPath)
    }
}
