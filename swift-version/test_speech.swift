import Foundation
import AVFoundation
import Speech

@available(macOS 15.0, *)
func getTranscrip(buffer: AVAudioPCMBuffer) async throws -> String {
    let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .transcription)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    
    let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    continuation.yield(AnalyzerInput(buffer: buffer))
    continuation.finish()
    
    Task {
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            print("Error: \(error)")
        }
    }
    
    var finalResult = ""
    for try await transcript in transcriber.results {
        finalResult = String(transcript.text.characters)
    }
    return finalResult
}
