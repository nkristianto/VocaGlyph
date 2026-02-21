import Foundation
import AVFoundation
import Speech

@available(macOS 15.0, *)
func getAudioBuffer() -> AVAudioPCMBuffer {
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 16000 * 2)!
    buffer.frameLength = 16000 * 2
    for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData?[0][i] = Float.random(in: -1.0...1.0)
    }
    return buffer
}

@available(macOS 15.0, *)
func testFallbackEngine() async {
    let authStatus = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
    
    guard authStatus == .authorized else {
        print("Auth failed")
        return
    }
    
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
        print("No recognizer")
        return
    }
    print("Is available: \(recognizer.isAvailable)")
    
    let buffer = getAudioBuffer()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = true
    
    request.append(buffer)
    request.endAudio()
    
    let resultText = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
        var hasResumed = false
        
        recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
                return
            }
            if let result = result, result.isFinal {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    print("Transcription result: \(resultText ?? "nil")")
}

if #available(macOS 15.0, *) {
    Task {
        await testFallbackEngine()
        exit(0)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
}
