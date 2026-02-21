import Foundation
import AVFoundation

public actor EngineRouter {
    private var activeEngine: any TranscriptionEngine
    
    public init(engine: any TranscriptionEngine) {
        self.activeEngine = engine
    }
    
    public func setEngine(_ engine: any TranscriptionEngine) {
        self.activeEngine = engine
    }
    
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        return try await activeEngine.transcribe(audioBuffer: audioBuffer)
    }
}
