import Foundation
import AVFoundation

func devLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/vocaglyph_debug.log")
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let time = formatter.string(from: Date())
    let line = "[\(time)] \(message)\n"
    
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) { handle.write(data) }
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}

#if canImport(Speech)
import Speech

@available(macOS 15.0, *)
public actor NativeSpeechEngine: TranscriptionEngine {
    
    private var analyzer: Any?
    private var transcriber: Any?
    
    public init() {}
    
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        devLog("NativeSpeechEngine: Starting transcription for \(audioBuffer.frameLength) frames")
        
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        devLog("NativeSpeechEngine: Auth Status: \(authStatus.rawValue)")
        
        guard authStatus == .authorized else {
            devLog("NativeSpeechEngine: Auth denied")
            throw NSError(domain: "NativeSpeechEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Apple Speech Recognition permission denied or restricted."])
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            devLog("NativeSpeechEngine: No recognizer for en-US")
            throw NSError(domain: "NativeSpeechEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "No Apple Dictation recognizer found for en-US."])
        }
        
        guard recognizer.isAvailable else {
            devLog("NativeSpeechEngine: Recognizer is NOT available")
            throw NSError(domain: "NativeSpeechEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: "Apple Dictation is temporarily unavailable natively on this device."])
        }
        
        devLog("NativeSpeechEngine: Recognizer is available. Converting buffer to disk.")
        // due to internal IPC buffer limits. For complete buffers, SFSpeechURLRecognitionRequest is 100% reliable.
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        
        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: audioBuffer.format.settings)
            try audioFile.write(from: audioBuffer)
        } catch {
            throw NSError(domain: "NativeSpeechEngine", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to write temporary audio file for Apple Dictation: \(error.localizedDescription)"])
        }
        
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = true
        // Allow fallback to server if on-device offline models aren't completely downloaded
        request.requiresOnDeviceRecognition = false 
        
        devLog("NativeSpeechEngine: Awaiting recognitionTask completion...")
        // Await the task block 
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var bestStringSoFar = ""
            
            recognizer.recognitionTask(with: request) { result, error in
                devLog("NativeSpeechEngine: recognitionTask block hit. Error: \(error?.localizedDescription ?? "None"), Result: \(result != nil)")
                if let error = error {
                    if !hasResumed {
                        devLog("NativeSpeechEngine Error: \(error.localizedDescription)")
                        hasResumed = true
                        // Cleanup
                        try? FileManager.default.removeItem(at: fileURL)
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                if let result = result {
                    bestStringSoFar = result.bestTranscription.formattedString
                    devLog("NativeSpeechEngine: Received result. isFinal: \(result.isFinal), String: '\(bestStringSoFar)'")
                    if result.isFinal {
                        if !hasResumed {
                            devLog("NativeSpeechEngine Final String Resuming: '\(bestStringSoFar)'")
                            hasResumed = true
                            try? FileManager.default.removeItem(at: fileURL)
                            continuation.resume(returning: bestStringSoFar)
                        }
                    }
                }
            }
            
            // Fallback timeout or aggressive return if needed
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds ceiling
                if !hasResumed {
                    devLog("NativeSpeechEngine: Timeout Reached! Returning partial: '\(bestStringSoFar)'")
                    hasResumed = true
                    try? FileManager.default.removeItem(at: fileURL)
                    continuation.resume(returning: bestStringSoFar)
                }
            }
        }
    }
}
#else

// Fallback for older SDKs that can't even import the modern Speech framework
public actor NativeSpeechEngine: TranscriptionEngine {
    public init() {}
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        throw NSError(domain: "NativeSpeechEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Modern Speech Framework unavailable on this OS."])
    }
}

#endif
