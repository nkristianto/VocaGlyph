import AVFoundation

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String
}

public protocol PostProcessingEngine: Sendable {
    func refine(text: String, prompt: String) async throws -> String
}

public protocol EngineRouterDelegate: AnyObject {
    func engineRouterDidReceiveTranscription(_ text: String)
    func engineRouterDidUpdateState(_ state: String)
}

protocol SystemPermissionsProvider: Sendable {
    func getMicrophoneAuthorizationStatus() -> AVAuthorizationStatus
    func requestMicrophoneAccess() async -> Bool
    func checkAccessibilityTrusted() -> Bool
    func promptAccessibilityTrusted() -> Bool
    func checkFullDiskAccess() -> Bool
    func promptFullDiskAccess()
}
