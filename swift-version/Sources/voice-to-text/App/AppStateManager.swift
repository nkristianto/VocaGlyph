import Foundation
import Combine
import AVFoundation

enum AppState {
    case idle
    case initializing
    case recording
    case processing
}

protocol AppStateManagerDelegate: AnyObject {
    func appStateDidChange(newState: AppState)
    func appStateManagerDidTranscribe(text: String)
}

class AppStateManager: ObservableObject, @unchecked Sendable {
    weak var delegate: AppStateManagerDelegate?
    var engineRouter: EngineRouter?
    var sharedWhisper: WhisperService?
    var postProcessingEngine: (any PostProcessingEngine)?
    
    // We no longer track selectedEngine explicitly. We derive the engine 
    // from the model selection inside switchTranscriptionEngine.
    
    @Published var currentState: AppState = .idle {
        didSet {
            delegate?.appStateDidChange(newState: currentState)
        }
    }
    
    init() {}
    
    // Called by AppDelegate after all dependencies are injected
    func startEngine() {
        let initialModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "apple-native"
        Logger.shared.info("AppStateManager: startEngine called with model: \(initialModel)")
        Task {
            await switchTranscriptionEngine(toModel: initialModel)
        }
        
        // Initialize Post-Processing Engine if Apple Intelligence is enabled/selected
        if #available(macOS 15.1, *) {
            let selectedPostModel = UserDefaults.standard.string(forKey: "selectedTaskModel") ?? "apple-native"
            if selectedPostModel == "apple-native" {
                Logger.shared.info("AppStateManager: Initializing AppleIntelligenceEngine for post-processing")
                self.postProcessingEngine = AppleIntelligenceEngine()
            }
        }
    }
    
    func startRecording() {
        currentState = .recording
    }
    
    func stopRecording() {
        currentState = .processing
    }
    
    func setIdle() {
        currentState = .idle
    }
    
    func setInitializing() {
        currentState = .initializing
    }
    
    func processAudio(buffer: AVAudioPCMBuffer) {
        Logger.shared.info("AppStateManager: processAudio called with buffer size: \(buffer.frameLength)")
        guard let router = engineRouter else {
            Logger.shared.info("AppStateManager: engineRouter is nil. Aborting.")
            setIdle()
            return
        }
        
        let shouldPostProcess = UserDefaults.standard.bool(forKey: "enablePostProcessing")
        let postProcessPrompt = UserDefaults.standard.string(forKey: "postProcessingPrompt") ?? ""
        
        Task {
            do {
                var text = try await router.transcribe(audioBuffer: buffer)
                Logger.shared.info("AppStateManager: Router transcribed text successfully: '\(text)'")
                
                if shouldPostProcess, let postProcessor = self.postProcessingEngine {
                    Logger.shared.info("AppStateManager: Post processing enabled, refining text...")
                    do {
                        let originalText = text
                        let refinedText = try await withThrowingTaskGroup(of: String.self) { group in
                            group.addTask {
                                return try await postProcessor.refine(text: originalText, prompt: postProcessPrompt)
                            }
                            group.addTask {
                                try await Task.sleep(nanoseconds: 2_000_000_000)
                                throw NSError(domain: "TimeoutError", code: 408, userInfo: [NSLocalizedDescriptionKey: "Post-processing timed out after 2000ms"])
                            }
                            guard let result = try await group.next() else {
                                throw CancellationError()
                            }
                            group.cancelAll()
                            return result
                        }
                        text = refinedText
                        Logger.shared.info("AppStateManager: Post processing completed successfully: '\(text)'")
                    } catch {
                        Logger.shared.error("AppStateManager: Post processing failed: \(error.localizedDescription). Gracefully falling back to raw text.")
                    }
                }
                
                DispatchQueue.main.async {
                    Logger.shared.info("AppStateManager: Dispatching back to main UI thread...")
                    if let del = self.delegate {
                        Logger.shared.info("AppStateManager: Delegate exists, calling appStateManagerDidTranscribe()")
                        del.appStateManagerDidTranscribe(text: text)
                    } else {
                        Logger.shared.info("AppStateManager: ERROR! Delegate is unexpectedly nil!")
                    }
                    self.setIdle() // Orchestrator handles reset
                }
            } catch {
                Logger.shared.error("AppStateManager: Transcription failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.setIdle()
                }
            }
        }
    }
    
    public func switchTranscriptionEngine(toModel modelName: String) async {
        guard let router = engineRouter else { return }
        
        Logger.shared.info("AppStateManager: Requested to switch transcription engine to model: '\(modelName)'")
        
        if modelName == "apple-native" {
            if #available(macOS 15.0, *) {
                Logger.shared.info("AppStateManager: Dynamically routing to NativeSpeechEngine for model: apple-native")
                let native = NativeSpeechEngine()
                await router.setEngine(native)
            } else {
                // Fallback if somehow triggered on old macOS
                Logger.shared.error("AppStateManager: macOS too old for apple-native. Falling back to WhisperKit.")
                if let whisper = sharedWhisper { await router.setEngine(whisper) }
            }
        } else {
            Logger.shared.info("AppStateManager: Dynamically routing to shared WhisperService for model: \(modelName)")
            if let whisper = sharedWhisper {
                await router.setEngine(whisper)
            }
        }
    }
}

extension AppStateManager {
    static func isMacOS15OrNewer() -> Bool {
        if #available(macOS 15.0, *) {
            return true
        } else {
            return false
        }
    }
}
