import SwiftUI

struct SettingsView: View {
    @ObservedObject var stateManager: AppStateManager
    var whisper: WhisperService
    
    // AppStorage for UserDefaults persistence
    @AppStorage("selectedModel") private var selectedModel: String = "large-v3-v20240930"
    
    let availableModels = [
        "large-v3-v20240930": "Large V3 Turbo (Recommended)",
        "base": "Base (Fast)",
        "small": "Small",
        "medium": "Medium"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.blue)
                Text("Voice to Text Engine")
                    .font(.headline)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // State Indicator
            HStack {
                Text("Current State:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Group {
                    if stateManager.currentState == .idle {
                        Text("Idle")
                            .foregroundColor(.secondary)
                    } else if stateManager.currentState == .recording {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                            Text("Recording...")
                        }
                        .foregroundColor(.red)
                    } else if stateManager.currentState == .processing {
                        HStack {
                            Image(systemName: "hourglass.circle.fill")
                            Text("Processing...")
                        }
                        .foregroundColor(.orange)
                    }
                }
                .font(.subheadline.bold())
            }
            
            // Settings Form
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Transcription Model")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $selectedModel) {
                    ForEach(Array(availableModels.keys.sorted()), id: \.self) { key in
                        Text(availableModels[key] ?? key).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: selectedModel) { newValue in
                    whisper.changeModel(to: newValue)
                }
                
                Text("**Note:** Models download on first use. Larger models improve accuracy but take more memory.")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            
            Divider()
                .padding(.vertical, 4)
            
            // Hotkey visual mapping (Mock representation for 9.6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Global Shortcut")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(height: 28)
                        
                        Text("⌃ ⇧ C")
                            .font(.system(.body, design: .monospaced).bold())
                    }
                    
                    Spacer()
                }
                Text("Hold to record. Release to transcribe & paste.")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Divider()
            
            HStack {
                Button("Quit Voice to Text") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
