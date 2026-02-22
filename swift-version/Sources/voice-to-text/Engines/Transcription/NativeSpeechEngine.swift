import Foundation
import AVFoundation



#if canImport(Speech)
import Speech

@available(macOS 15.0, *)
public actor NativeSpeechEngine: TranscriptionEngine {
    
    private var analyzer: Any?
    private var transcriber: Any?
    
    public init() {
        Logger.shared.info("NativeSpeechEngine: Initialized Apple Dictation Engine")
    }
    
    public func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        Logger.shared.info("NativeSpeechEngine: Starting transcription for \(audioBuffer.frameLength) frames")
        
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        Logger.shared.info("NativeSpeechEngine: Auth Status: \(authStatus.rawValue)")
        
        guard authStatus == .authorized else {
            Logger.shared.info("NativeSpeechEngine: Auth denied")
            throw NSError(domain: "NativeSpeechEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Apple Speech Recognition permission denied or restricted."])
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            Logger.shared.info("NativeSpeechEngine: No recognizer for en-US")
            throw NSError(domain: "NativeSpeechEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "No Apple Dictation recognizer found for en-US."])
        }
        
        guard recognizer.isAvailable else {
            Logger.shared.info("NativeSpeechEngine: Recognizer is NOT available")
            throw NSError(domain: "NativeSpeechEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: "Apple Dictation is temporarily unavailable natively on this device."])
        }
        
        Logger.shared.info("NativeSpeechEngine: Recognizer is available. Converting buffer to disk.")
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
        
        Logger.shared.info("NativeSpeechEngine: Awaiting recognitionTask completion...")
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var bestStringSoFar = ""

            // Capture the task so we can cancel it from the timeout handler
            var recognitionTaskRef: SFSpeechRecognitionTask?

            recognitionTaskRef = recognizer.recognitionTask(with: request) { result, error in
                Logger.shared.debug("NativeSpeechEngine: recognitionTask block hit. Error: \(error?.localizedDescription ?? "None"), Result: \(result != nil)")
                if let error = error {
                    if !hasResumed {
                        Logger.shared.info("NativeSpeechEngine Error: \(error.localizedDescription)")
                        hasResumed = true
                        try? FileManager.default.removeItem(at: fileURL)

                        if error.localizedDescription.localizedCaseInsensitiveContains("No speech detected") || (error as NSError).code == 201 || (error as NSError).code == 1110 || (error as NSError).code == 207 {
                            continuation.resume(returning: bestStringSoFar)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }

                if let result = result {
                    bestStringSoFar = result.bestTranscription.formattedString
                    Logger.shared.debug("NativeSpeechEngine: Received result. isFinal: \(result.isFinal), String: '\(bestStringSoFar)'")
                    if result.isFinal {
                        if !hasResumed {
                            Logger.shared.info("NativeSpeechEngine Final String Resuming: '\(bestStringSoFar)'")
                            hasResumed = true
                            try? FileManager.default.removeItem(at: fileURL)
                            continuation.resume(returning: bestStringSoFar)
                        }
                    }
                }
            }

            // Timeout ceiling: cancel the task first so its callback won't fire after resuming
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
                if !hasResumed {
                    Logger.shared.info("NativeSpeechEngine: Timeout reached! Cancelling task, returning partial: '\(bestStringSoFar)'")
                    recognitionTaskRef?.cancel()
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
