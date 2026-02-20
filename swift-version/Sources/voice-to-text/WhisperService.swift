import Foundation
import WhisperKit

protocol WhisperServiceDelegate: AnyObject {
    func whisperServiceDidUpdateState(_ state: String)
    func whisperServiceDidTranscribe(_ text: String)
}

class WhisperService {
    private var whisperKit: WhisperKit?
    private var isReady = false
    weak var delegate: WhisperServiceDelegate?
    
    // Fetch from UserDefaults or fallback to recommended model
    private var currentModelName: String {
        UserDefaults.standard.string(forKey: "selectedModel") ?? "large-v3-v20240930"
    }
    
    init() {
        Task {
            await initializeWhisper()
        }
    }
    
    private func initializeWhisper() async {
        print("Initializing WhisperKit...")
        do {
            print("Checking/Downloading WhisperKit model...")
            let modelName = currentModelName
            let modelPath = try await WhisperKit.download(variant: modelName)
            print("Model available at \(modelPath). Initializing Engine...")
            whisperKit = try await WhisperKit(modelFolder: modelPath.path)
            isReady = true
            print("WhisperKit is ready using model: \(modelName)")
            delegate?.whisperServiceDidUpdateState("Ready")
        } catch {
            print("Failed to initialize WhisperKit: \(error.localizedDescription)")
            delegate?.whisperServiceDidUpdateState("Failed")
        }
    }
    
    // MARK: - Dynamic Configuration
    func changeModel(to modelName: String) {
        // Redownload/reinit the engine asynchronously
        isReady = false
        delegate?.whisperServiceDidUpdateState("Processing") // Set to processing while downloading
        
        Task {
            await initializeWhisper()
        }
    }
    
    func transcribe(audioArray: [Float]) {
        guard isReady, let whisperKit = whisperKit else {
            print("WhisperKit is not ready yet.")
            return
        }
        
        Task {
            do {
                print("Starting WhisperKit transcription on \(audioArray.count) frames...")
                
                // WhisperKit can sometimes return empty strings on macOS if language isn't explicitly defined or it tries to use incorrect fallback decoding options
                let decodingOptions = DecodingOptions(
                    language: "en",
                    usePrefillPrompt: false,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: true
                )
                
                let results = try await whisperKit.transcribe(audioArray: audioArray, decodeOptions: decodingOptions)
                let combinedText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                print("Transcription finished: '\(combinedText)'")
                
                DispatchQueue.main.async {
                    self.delegate?.whisperServiceDidTranscribe(combinedText)
                }
            } catch {
                print("Transcription error: \(error.localizedDescription)")
            }
        }
    }
}
