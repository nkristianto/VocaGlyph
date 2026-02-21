import Foundation
import AVFoundation
import Speech

@available(macOS 15.0, *)
public actor NativeSpeechEngine {
    private var analyzer: Any?
    private var transcriber: Any?

    public init() {}
    
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        if #available(macOS 26.0, *) {
            let transcriberObj = SpeechTranscriber(locale: Locale.current, preset: .transcription)
            let analyzerObj = SpeechAnalyzer(modules: [transcriberObj])
            
            self.transcriber = transcriberObj
            self.analyzer = analyzerObj
            
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            continuation.yield(AnalyzerInput(buffer: audioBuffer))
            continuation.finish()
            
            Task {
                do {
                    try await analyzerObj.start(inputSequence: stream)
                } catch {}
            }
            var finalTranscription = ""
            for try await transcript in transcriberObj.results {
                finalTranscription = String(transcript.text.characters)
            }
            
            self.transcriber = nil
            self.analyzer = nil
            return finalTranscription
        } else {
            return "Simulated Native Transcription for < macOS 26"
        }
    }
}
