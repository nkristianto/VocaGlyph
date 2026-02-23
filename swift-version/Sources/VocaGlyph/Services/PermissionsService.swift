import Foundation
import AppKit
import AVFoundation
import Speech

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

    var isSpeechRecognitionAuthorized: Bool {
        return provider.getSpeechRecognitionAuthorizationStatus() == .authorized
    }

    var areAllCorePermissionsGranted: Bool {
        return isMicrophoneAuthorized && isAccessibilityTrusted
    }

    func requestMicrophoneAccess() async -> Bool {
        return await provider.requestMicrophoneAccess()
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        return await provider.requestSpeechRecognitionAccess()
    }

    func promptAccessibilityTrusted() -> Bool {
        return provider.promptAccessibilityTrusted()
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

    func getSpeechRecognitionAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        return SFSpeechRecognizer.authorizationStatus()
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
