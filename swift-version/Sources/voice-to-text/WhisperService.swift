import Foundation
import WhisperKit

protocol WhisperServiceDelegate: AnyObject {
    func whisperServiceDidUpdateState(_ state: String)
    func whisperServiceDidTranscribe(_ text: String)
}

class WhisperService: ObservableObject, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    @Published private(set) var isReady = false
    weak var delegate: WhisperServiceDelegate?
    
    @Published var downloadProgresses: [String: Float] = [:]
    @Published var downloadState: String = "Initializing Engine..."
    @Published var downloadedModels: Set<String> = []
    
    @Published var activeModel: String = ""
    @Published var loadingModel: String? = nil
    
    // Fetch from UserDefaults or fallback to recommended model
    private var defaultModelName: String {
        UserDefaults.standard.string(forKey: "selectedModel") ?? ""
    }
    
    // Convert UI string to WhisperKit locale code
    private var dictationLanguageCode: String {
        let saved = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "English (US)"
        switch saved {
        case "Spanish (ES)": return "es"
        case "French (FR)": return "fr"
        case "German (DE)": return "de"
        case "Indonesian (ID)": return "id"
        default: return "en"
        }
    }
    
    // Base Directory for WhisperKit
    private var baseDirectoryPath: URL {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let vocaGlyphDir = homeDir.appendingPathComponent(".VocaGlyph", isDirectory: true)
        let baseDir = vocaGlyphDir.appendingPathComponent("models", isDirectory: true)
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: baseDir.path) {
            do {
                try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create models directory: \(error)")
            }
        }
        return baseDir
    }
    
    // The actual directory where WhisperKit saves the models
    private var actualModelsDirectory: URL {
        return baseDirectoryPath.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    }
    
    init() {
        checkDownloadedModels()
        Task {
            await autoInitialize()
        }
    }
    
    func checkDownloadedModels() {
        let downloaded = getDownloadedModelsSync()
        DispatchQueue.main.async {
            self.downloadedModels = downloaded
        }
    }
    
    private func getDownloadedModelsSync() -> Set<String> {
        let fileManager = FileManager.default
        let modelsDir = actualModelsDirectory

        
        var downloaded = Set<String>()
        do {
            let items = try fileManager.contentsOfDirectory(atPath: modelsDir.path)
            for item in items {
                if item.hasPrefix("openai_whisper-") {
                    let model = String(item.dropFirst("openai_whisper-".count))
                    downloaded.insert(model)
                }
            }
        } catch {
            print("No models downloaded yet or directory missing.")
        }
        return downloaded
    }
    
    private func autoInitialize() async {
        let available = getDownloadedModelsSync()
        if available.contains(defaultModelName) {
            await initializeWhisper(modelName: defaultModelName)
        } else if let firstAvailable = available.first {
            // Fallback to whichever model is available so the user isn't outright broken
            DispatchQueue.main.async {
                self.downloadState = "Falling back to \(firstAvailable)..."
            }
            await initializeWhisper(modelName: firstAvailable)
        } else {
            DispatchQueue.main.async {
                self.downloadState = "Model not downloaded."
                self.isReady = false
            }
        }
    }
    
    private func initializeWhisper(modelName: String) async {
        print("Initializing WhisperKit...")
        do {
            let available = getDownloadedModelsSync()
            if !available.contains(modelName) {
                // Do not auto-download. Just return or set state.
                DispatchQueue.main.async {
                    self.downloadState = "Model not downloaded."
                    self.isReady = false
                    self.loadingModel = nil
                }
                return
            }
            
            DispatchQueue.main.async {
                self.downloadState = "Loading into memory..."
                self.loadingModel = modelName
            }
            
            let modelPath = actualModelsDirectory.appendingPathComponent("openai_whisper-\(modelName)")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss.SSS"
            let timeString = dateFormatter.string(from: Date())
            
            print("[\(timeString)] Model available at \(modelPath). Initializing Engine...")
            whisperKit = try await WhisperKit(modelFolder: modelPath.path)
            isReady = true
            
            let timeStringReady = dateFormatter.string(from: Date())
            print("[\(timeStringReady)] WhisperKit is ready using model: \(modelName)")
            
            DispatchQueue.main.async {
                self.activeModel = modelName
                UserDefaults.standard.set(modelName, forKey: "selectedModel")
                self.loadingModel = nil
                self.downloadState = "Ready"
            }
            
            delegate?.whisperServiceDidUpdateState("Ready")
        } catch {
            print("Failed to initialize WhisperKit: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.loadingModel = nil
            }
            delegate?.whisperServiceDidUpdateState("Failed")
        }
    }
    
    // MARK: - Dynamic Configuration
    func changeModel(to modelName: String) {
        // Only load the engine if the model is actually downloaded.
        isReady = false
        let available = getDownloadedModelsSync()
        if available.contains(modelName) {
            delegate?.whisperServiceDidUpdateState("Processing") // Set to processing while loading
            Task {
                await initializeWhisper(modelName: modelName)
            }
        } else {
            DispatchQueue.main.async {
                self.downloadState = "Model not downloaded."
            }
        }
    }
    
    func downloadModel(_ modelName: String) {
        DispatchQueue.main.async {
            self.downloadState = "Downloading"
            self.downloadProgresses[modelName] = 0.0
        }
        
        Task {
            do {
                _ = try await WhisperKit.download(variant: modelName, downloadBase: baseDirectoryPath, progressCallback: { progress in
                    DispatchQueue.main.async {
                        self.downloadProgresses[modelName] = Float(progress.fractionCompleted)
                        self.downloadState = "Downloading... \(Int(progress.fractionCompleted * 100))%"
                    }
                })
                
                checkDownloadedModels()
                
                DispatchQueue.main.async {
                    self.downloadProgresses.removeValue(forKey: modelName)
                    self.downloadState = "Ready"
                }
                
                // If this is the currently selected model, initialize it now
                if defaultModelName == modelName {
                    await initializeWhisper(modelName: modelName)
                }
                
            } catch {
                print("Download failed: \(error)")
                DispatchQueue.main.async {
                    self.downloadState = "Failed"
                    self.downloadProgresses.removeValue(forKey: modelName)
                }
            }
        }
    }
    
    func deleteModel(_ modelName: String) {
        let fileManager = FileManager.default
        let modelDir = actualModelsDirectory.appendingPathComponent("openai_whisper-\(modelName)")
        
        do {
            try fileManager.removeItem(at: modelDir)
            checkDownloadedModels()
            
            // If we deleted the currently active model, unload it.
            if activeModel == modelName {
                self.whisperKit = nil
                self.isReady = false
                DispatchQueue.main.async {
                    self.activeModel = ""
                    self.downloadState = "Model not downloaded."
                }
            }
            print("Deleted model \(modelName)")
        } catch {
            print("Failed to delete model: \(error)")
        }
    }
    
    func transcribe(audioArray: [Float]) {
        guard isReady, let whisperKit = whisperKit else {
            print("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] WhisperKit is not ready yet.")
            DispatchQueue.main.async {
                self.delegate?.whisperServiceDidUpdateState("Model warming up...")
            }
            return
        }
        
        Task {
            do {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH:mm:ss.SSS"
                
                print("[\(dateFormatter.string(from: Date()))] Starting WhisperKit transcription on \(audioArray.count) frames...")
                print("[\(dateFormatter.string(from: Date()))] Transcribing \(audioArray.count) samples using language code: \(dictationLanguageCode)")
        
                // Prepare decoding options dynamically
                let decodingOptions = DecodingOptions(
                    language: dictationLanguageCode,
                    usePrefillPrompt: false,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: true
                )
                
                let results = try await whisperKit.transcribe(audioArray: audioArray, decodeOptions: decodingOptions)
                let combinedText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                print("[\(dateFormatter.string(from: Date()))] Transcription finished: '\(combinedText)'")
                
                DispatchQueue.main.async {
                    self.delegate?.whisperServiceDidTranscribe(combinedText)
                }
            } catch {
                print("Transcription error: \(error.localizedDescription)")
            }
        }
    }
}
