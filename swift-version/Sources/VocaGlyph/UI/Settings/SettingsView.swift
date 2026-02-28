import SwiftUI
import SwiftData
import ServiceManagement
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Binding Helper

extension Binding {
    /// Wraps a Binding so every write is logged to the shared Logger.
    func logged(name: String) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                let oldValue = self.wrappedValue
                Logger.shared.debug("Settings: Changed \(name) from '\(oldValue)' to '\(newValue)'")
                self.wrappedValue = newValue
            }
        )
    }
}

// MARK: - SettingsTab

enum SettingsTab: Hashable {
    case history
    case general
    case model
    case postProcessing
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var parakeet: ParakeetService
    @ObservedObject var stateManager: AppStateManager
    var microphoneService: MicrophoneService
    @State private var settingsViewModel = SettingsViewModel()

    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            CustomSidebar(selectedTab: $selectedTab)
                .frame(width: 240)
                .background(Color.white.opacity(0.5))

            Divider()
                .overlay(Theme.textMuted.opacity(0.1))

            // Main Content Area
            ZStack {
                Color.white.opacity(0.8)

                switch selectedTab {
                case .history:
                    HistorySettingsView()
                case .general:
                    GeneralSettingsView(whisper: whisper, stateManager: stateManager, microphoneService: microphoneService)
                case .model:
                    ModelSettingsView(whisper: whisper, parakeet: parakeet, stateManager: stateManager)
                case .postProcessing:
                    PostProcessingSettingsView(whisper: whisper, stateManager: stateManager, viewModel: settingsViewModel)
                case .none:
                    Text("Select an item").foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: selectedTab) { _, newValue in
                if let tab = newValue {
                    Logger.shared.debug("Settings: Navigated to \(String(describing: tab)) tab")
                }
            }
        }
        .frame(minWidth: 850, minHeight: 650)
        .background(Theme.background)
        .environment(\.font, .system(size: 14))
        .ignoresSafeArea(.all, edges: .all)
    }
}
