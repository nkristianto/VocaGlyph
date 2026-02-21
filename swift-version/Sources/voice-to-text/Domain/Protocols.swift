import AVFoundation

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String
}

public protocol PostProcessingEngine: Sendable {
    func refine(text: String, prompt: String) async throws -> String
}
