import SwiftUI
import ServiceManagement
#if canImport(FoundationModels)
import FoundationModels
#endif

extension Binding {
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

enum SettingsTab: Hashable {
    case history
    case general
    case model
    case postProcessing
}

struct SettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    @State private var settingsViewModel = SettingsViewModel()
    
    @State private var selectedTab: SettingsTab? = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Custom Sidebar
            CustomSidebar(selectedTab: $selectedTab)
                .frame(width: 240)
                .background(Color.white.opacity(0.5)) // Slight transparency for the sidebar
            
            Divider()
                .overlay(Theme.textMuted.opacity(0.1))
            
            // Main Content Area
            ZStack {
                Color.white.opacity(0.8) // Whiter main area
                
                switch selectedTab {
                case .history:
                    HistorySettingsView()
                case .general:
                    GeneralSettingsView(whisper: whisper, stateManager: stateManager)
                case .model:
                    ModelSettingsView(whisper: whisper, stateManager: stateManager)
                case .postProcessing:
                    PostProcessingSettingsView(whisper: whisper, stateManager: stateManager, viewModel: settingsViewModel)
                case .none:
                    Text("Select an item").foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: selectedTab) { newValue in
                if let tab = newValue {
                    Logger.shared.debug("Settings: Navigated to \(String(describing: tab)) tab")
                }
            }
        }
        .frame(minWidth: 850, minHeight: 650)
        .background(Theme.background) // Base background
        .environment(\.font, .system(size: 14))
        .ignoresSafeArea(.all, edges: .all) // Allow drawing into titlebar AND bottom safe areas
    }
}

struct CustomSidebar: View {
    @Binding var selectedTab: SettingsTab?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Padding for native macOS traffic lights (red/yellow/green buttons)
            Spacer().frame(height: 60) // Increased by 10px for live margin
            
            // App Identity
            HStack(spacing: 24) {
                if let imgUrl = Bundle.module.url(forResource: "appicon", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: imgUrl) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8)) // App icons are typically squircles
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                } else {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Theme.accent, Theme.navy], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .opacity(0.8)
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 16).bold())
                            .foregroundStyle(.white)
                    }
                }
                Text("VocaGlyph")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            }
            .padding(.leading, 16) // Exact alignment with traffic lights
            .padding(.bottom, 24)
            
            // Navigation Links
            VStack(spacing: 4) {
                SidebarItemView(title: "General", icon: "gearshape.fill", tab: .general, selectedTab: $selectedTab)
                SidebarItemView(title: "History", icon: "clock.arrow.circlepath", tab: .history, selectedTab: $selectedTab)
                SidebarItemView(title: "Model", icon: "brain.head.profile", tab: .model, selectedTab: $selectedTab)
                SidebarItemView(title: "Post-Processing", icon: "wand.and.stars", tab: .postProcessing, selectedTab: $selectedTab, showExperimentalBadge: true)
            }
            .padding(.horizontal, 6) // Container padding 6 + Inner 10 = 16pt icon alignment
            
            Spacer()
            
            // Footer
            VStack(alignment: .leading, spacing: 4) {
                Text("Under Development")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Version 0.0.1 (Beta)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.leading, 18)
            .padding(.bottom, 24)
        }
    }
}

struct SidebarItemView: View {
    let title: String
    let icon: String
    let tab: SettingsTab
    @Binding var selectedTab: SettingsTab?
    var showExperimentalBadge: Bool = false
    
    var isSelected: Bool { selectedTab == tab }
    
    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 14).weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)
                
                Spacer()
                
                if showExperimentalBadge {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
            }
            .padding(.horizontal, 10) // Inner padding 10
            .padding(.vertical, 10)
            .contentShape(Rectangle()) // Make the entire area clickable
            .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering && !isSelected {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    
    @AppStorage("globalShortcutPreset") private var globalShortcutPreset: String = GlobalShortcutOption.ctrlShiftC.rawValue
    @AppStorage("dictationLanguage") private var dictationLanguage: String = "Auto-Detect"
    @AppStorage("autoPunctuation") private var autoPunctuation: Bool = true
    @AppStorage("removeFillerWords") private var removeFillerWords: Bool = false
    @AppStorage("selectedModel") private var selectedModel: String = "apple-native"
    
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                Logger.shared.debug("Settings: Changed Launch at Login from '\(launchAtLogin)' to '\(newValue)'")
                launchAtLogin = newValue
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to update Launch at Login: \(error.localizedDescription)")
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky Header
            VStack(alignment: .leading, spacing: 4) {
                Text("General Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.navy)
                Text("Configure voice input, system integration, and application behavior")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.8))
            
            Divider().background(Theme.textMuted.opacity(0.1))
            
            ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // Input Configuration Section
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text("Input Configuration")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.navy)
                    } icon: {
                        Image(systemName: "mic")
                            .foregroundStyle(Theme.navy)
                    }
                    
                    VStack(spacing: 0) {
                        // Global Shortcut
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Global Shortcut")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("Press to start/stop dictation")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Menu {
                                ForEach(GlobalShortcutOption.allCases) { option in
                                    Button(option.rawValue) {
                                        Logger.shared.debug("Settings: Changed Global Shortcut from '\(globalShortcutPreset)' to '\(option.rawValue)'")
                                        globalShortcutPreset = option.rawValue
                                    }
                                }
                            } label: {
                                Text(globalShortcutPreset)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.navy)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .clipShape(.rect(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
                        }
                        .padding(16)
                        
                        Divider().background(Theme.textMuted.opacity(0.1))
                        

                        
                        // Dictation Language
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dictation Language")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text(dictationLanguage == "Auto-Detect" ? "Whisper detects language automatically" : "Primary language for transcription")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Menu {
                                Button("Auto-Detect") {
                                    Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'Auto-Detect'")
                                    dictationLanguage = "Auto-Detect"
                                }
                                Divider()
                                Button("English (US)") { 
                                    Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'English (US)'")
                                    dictationLanguage = "English (US)" 
                                }
                                Button("Spanish (ES)") { 
                                    Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'Spanish (ES)'")
                                    dictationLanguage = "Spanish (ES)" 
                                }
                                Button("French (FR)") { 
                                    Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'French (FR)'")
                                    dictationLanguage = "French (FR)" 
                                }
                                Button("German (DE)") { 
                                    Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'German (DE)'")
                                    dictationLanguage = "German (DE)" 
                                }
                                Button("Indonesian (ID)") { 
                                    Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'Indonesian (ID)'")
                                    dictationLanguage = "Indonesian (ID)" 
                                }
                            } label: {
                                HStack {
                                    Text(dictationLanguage)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.navy)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                                )
                                .contentShape(Rectangle()) // Ensure entire area is clickable
                            }
                            .buttonStyle(.plain) // Use plain button style to draw the custom label properly
                            .frame(width: 140)
                        }
                        .padding(16)
                        
                        Divider().background(Theme.textMuted.opacity(0.1))
                        
                        // Auto-Punctuation
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Punctuation")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("Automatically add commas, periods, and question marks")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $autoPunctuation.logged(name: "Auto-Punctuation"))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding(16)
                        
                        Divider()
                            .background(Theme.textMuted.opacity(0.1))
                            .padding(.horizontal, 16)
                            
                        // Filter Filler Words
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove Filler Words")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("Automatically strip conversational words (um, uh, like)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $removeFillerWords.logged(name: "Remove Filler Words"))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // System Integration Section
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text("System Integration")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.navy)
                    } icon: {
                        Image(systemName: "macwindow")
                            .foregroundStyle(Theme.navy)
                    }
                    
                    VStack(spacing: 0) {
                        // Launch at Login
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("Automatically start VocaGlyph when you log into macOS")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: launchAtLoginBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Developer Options Section
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text("Developer Options")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.navy)
                    } icon: {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(Theme.navy)
                    }
                    
                    VStack(spacing: 0) {
                        // Enable Debug Logging
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Debug Logging")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("Save internal operation logs to a local file for troubleshooting")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            @AppStorage("enableDebugLogging") var isDebugEnabled: Bool = false
                            Toggle("", isOn: $isDebugEnabled.logged(name: "Debug Logging"))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding(16)
                        
                        Divider()
                            .background(Theme.textMuted.opacity(0.1))
                            .padding(.horizontal, 16)
                            
                        // Reveal Log File
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Application Logs")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("View the unified local log file")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Button("Reveal in Finder") {
                                Logger.shared.debug("Settings: Clicked Reveal in Finder")
                                NSWorkspace.shared.selectFile(Logger.shared.getLogFileURL().path, inFileViewerRootedAtPath: "")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(16)
                    }
                    .background(Color.white)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
                    )
                }
                
            }
            .padding(40)
            .padding(.bottom, 20) // Add extra space at the bottom to prevent cropping
            }
        }
    }
}

struct PostProcessingSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    @ObservedObject var viewModel: SettingsViewModel
    
    @AppStorage("enablePostProcessing") private var enablePostProcessing: Bool = false
    @AppStorage("selectedTaskModel") private var selectedTaskModel: String = "apple-native"
    @AppStorage("selectedCloudProvider") private var selectedCloudProvider: String = "gemini"
    @AppStorage("selectedLocalLLMModel") private var selectedLocalLLMModel: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"
    @AppStorage("postProcessingPrompt") private var postProcessingPrompt: String = "Fix grammar and formatting. Return only the revised text."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Post-Processing Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("experimental")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.9))
                }
                Text("Configure AI refinement for your dictation")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.8))
            
            Divider().background(Theme.textMuted.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    aiPostProcessingSection
                }
                .padding(40)
                .padding(.bottom, 20)
            }
        }
    }
    
    @ViewBuilder
    private var aiPostProcessingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("AI Post-Processing")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Theme.navy)
            }
            
            VStack(spacing: 0) {
                // Enable Post-Processing
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automated Text Refinement")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Use an AI engine to fix grammar and rephrase text before pasting")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $enablePostProcessing.logged(name: "Automated Text Refinement"))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(16)
                
                if enablePostProcessing {
                    Divider().background(Theme.textMuted.opacity(0.1))
                    
                    // Model Selection
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Processing Model")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.navy)
                            Text("Select the AI to refine your text")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Menu {
                            Button("Apple Intelligence") { 
                                Logger.shared.debug("Settings: Changed AI Processing Model from '\(selectedTaskModel)' to 'apple-native'")
                                selectedTaskModel = "apple-native" 
                                stateManager.switchPostProcessingEngine()
                            }
                            Button("Cloud API (Gemini/Anthropic)") { 
                                Logger.shared.debug("Settings: Changed AI Processing Model from '\(selectedTaskModel)' to 'cloud-api'")
                                selectedTaskModel = "cloud-api" 
                                stateManager.switchPostProcessingEngine()
                            }
                            Button("Local AI (Qwen)") {
                                Logger.shared.debug("Settings: Changed AI Processing Model from '\(selectedTaskModel)' to 'local-llm'")
                                selectedTaskModel = "local-llm"
                                stateManager.switchPostProcessingEngine()
                            }
                        } label: {
                            HStack {
                                let display = selectedTaskModel == "apple-native" ? "Apple Intelligence"
                                    : selectedTaskModel == "cloud-api" ? "Cloud API (Gemini/Anthropic)"
                                    : selectedTaskModel == "local-llm" ? "Local AI (Qwen)"
                                    : selectedTaskModel
                                Text(display)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.navy)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 160)
                    }
                    .padding(16)
                    
                    appleNativeCheck
                    
                    if selectedTaskModel == "local-llm" {
                        Divider().background(Theme.textMuted.opacity(0.1))
                        localLLMSection
                    }
                    
                    if selectedTaskModel == "cloud-api" {
                        Divider().background(Theme.textMuted.opacity(0.1))
                        
                        // Cloud Provider Selection
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cloud Provider")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.navy)
                                Text("Select the external AI service to use")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Menu {
                                Button("Google Gemini") { 
                                    Logger.shared.debug("Settings: Changed Cloud Provider from '\(selectedCloudProvider)' to 'gemini'")
                                    selectedCloudProvider = "gemini" 
                                    stateManager.switchPostProcessingEngine()
                                }
                                Button("Anthropic Claude") { 
                                    Logger.shared.debug("Settings: Changed Cloud Provider from '\(selectedCloudProvider)' to 'anthropic'")
                                    selectedCloudProvider = "anthropic" 
                                    stateManager.switchPostProcessingEngine()
                                }
                            } label: {
                                HStack {
                                    Text(selectedCloudProvider == "anthropic" ? "Anthropic Claude" : "Google Gemini")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.navy)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 160)
                        }
                        .padding(16)
                        
                        Divider().background(Theme.textMuted.opacity(0.1))
                        
                        // Error Message Display
                        errorDisplaySection
                        
                        // External API Credentials Group
                        externalApiCredentialsSection
                    }
                    
                    Divider().background(Theme.textMuted.opacity(0.1))
                    
                    // Custom Prompt
                    customPromptSection
                }
            }
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private var externalApiCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("External API Credentials")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.navy)
            Text("Securely save your keys in macOS Keychain. They are never stored in plaintext.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                
            if selectedCloudProvider == "anthropic" {
                // Anthropic Key Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic API Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.navy)
                    
                    HStack(spacing: 8) {
                        SecureField(viewModel.isAnthropicKeySaved ? "sk-ant-... (Saved in Keychain)" : "sk-ant-...", text: $viewModel.anthropicApiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                        
                        Button(action: {
                            if let clipboardStr = NSPasteboard.general.string(forType: .string) {
                                viewModel.anthropicApiKey = clipboardStr
                            }
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Paste from clipboard")
                        
                        if viewModel.isAnthropicKeySaved {
                            Button(action: {
                                Task { @MainActor in await viewModel.deleteAnthropicKey() }
                            }) {
                                Text("Delete")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .help("Key is securely stored in Keychain")
                        } else {
                            Button(action: {
                                Task { @MainActor in await viewModel.saveAnthropicKey() }
                            }) {
                                Text("Save Securely")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.anthropicApiKey.isEmpty)
                        }
                    }
                }
                .padding(.top, 8)
            }
            
            if selectedCloudProvider == "gemini" {
                // Gemini Key Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini API Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.navy)
                    
                    HStack(spacing: 8) {
                        SecureField(viewModel.isGeminiKeySaved ? "AIzaSy... (Saved in Keychain)" : "AIzaSy...", text: $viewModel.geminiApiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                        
                        Button(action: {
                            if let clipboardStr = NSPasteboard.general.string(forType: .string) {
                                viewModel.geminiApiKey = clipboardStr
                            }
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Paste from clipboard")
                        
                        if viewModel.isGeminiKeySaved {
                            Button(action: {
                                Task { @MainActor in await viewModel.deleteGeminiKey() }
                            }) {
                                Text("Delete")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .help("Key is securely stored in Keychain")
                        } else {
                            Button(action: {
                                Task { @MainActor in await viewModel.saveGeminiKey() }
                            }) {
                                Text("Save Securely")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.geminiApiKey.isEmpty)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.white)
    }
    
    @ViewBuilder
    private var appleNativeCheck: some View {
        if selectedTaskModel == "apple-native" {
            appleIntelligenceStatusBadge
        }
    }

    /// Shows a live badge indicating Apple Intelligence availability for the selected model.
    ///
    /// Three states:
    /// - macOS < 26: warns that Foundation Models is unavailable
    /// - macOS 26+, AI not enabled: prompts user to enable it in System Settings
    /// - macOS 26+, AI available: confirms the engine is ready
    @ViewBuilder
    private var appleIntelligenceStatusBadge: some View {
        if #available(macOS 26.0, *) {
            #if canImport(FoundationModels)
            appleIntelligenceStatusBadgeMacOS26
            #else
            // Compiled with older SDK — warn accordingly
            appleIntelligenceUnsupportedBadge(message: "Rebuild with Xcode 26 SDK to enable Foundation Models.")
            #endif
        } else {
            appleIntelligenceUnsupportedBadge(message: "Requires macOS 26 (Tahoe) – will fall back to raw text.")
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @ViewBuilder
    private var appleIntelligenceStatusBadgeMacOS26: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Apple Intelligence ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        case .unavailable(.appleIntelligenceNotEnabled):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence is not enabled.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text("Will fall back to raw text until enabled.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.general") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        default:
            appleIntelligenceUnsupportedBadge(message: "Apple Intelligence unavailable on this device – will fall back to raw text.")
        }
    }
    #endif

    @ViewBuilder
    private func appleIntelligenceUnsupportedBadge(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var localLLMSection: some View {
        // Model size picker
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Local Model")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Select model size (larger = better quality, more RAM)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Menu {
                Button("Qwen 2.5 7B (4.3 GB, 16GB RAM)") {
                    selectedLocalLLMModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"
                    stateManager.switchPostProcessingEngine()
                }
                Button("Qwen 2.5 1.5B (1.1 GB, 8GB RAM)") {
                    selectedLocalLLMModel = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
                    stateManager.switchPostProcessingEngine()
                }
                Button("Qwen 3 0.6B (0.4 GB, any Mac) — Testing") {
                    selectedLocalLLMModel = "mlx-community/Qwen3-0.6B-4bit"
                    stateManager.switchPostProcessingEngine()
                }
            } label: {
                HStack {
                    Text({
                        switch selectedLocalLLMModel {
                        case "mlx-community/Qwen2.5-1.5B-Instruct-4bit": return "Qwen 2.5 1.5B"
                        case "mlx-community/Qwen3-0.6B-4bit": return "Qwen 3 0.6B (Test)"
                        default: return "Qwen 2.5 7B"
                        }
                    }())
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 160)
        }
        .padding(16)

        // RAM / disk warning (7B only)
        if selectedLocalLLMModel == "mlx-community/Qwen2.5-7B-Instruct-4bit" {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Requires ~4.3 GB disk + 16 GB RAM. Model downloads once and is cached.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }

        Divider().background(Theme.textMuted.opacity(0.1))

        // ── Model Download / Status row ──────────────────────────────────
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if stateManager.localLLMIsWarmedUp {
                        // State 3: model is in memory and shader-warmed → ready
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(.green)
                        Text("Model ready in memory")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                    } else if stateManager.localLLMIsDownloaded && stateManager.localLLMDownloadProgress != nil {
                        // State 2: on disk, currently loading into RAM
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.accent)
                        Text("Loading model into memory…")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                    } else if stateManager.localLLMIsDownloaded {
                        // State 2b: on disk but not yet loaded / warm-up finished badge
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Model downloaded")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                    } else {
                        // State 1: not on disk
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(Theme.navy)
                        Text("Model not downloaded")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                    }
                }
                if let progress = stateManager.localLLMDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .frame(maxWidth: 240)
                        Text(progress < 1.0
                             ? "Downloading… \(Int(progress * 100))%"
                             : "✅ Complete!")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                    }
                } else if !stateManager.localLLMIsDownloaded {
                    Text("Download the model before your first use to avoid delays during dictation.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                } else if !stateManager.localLLMIsWarmedUp {
                    Text("Model loaded on next use. Launch app again to warm up automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Spacer()
            if stateManager.localLLMDownloadProgress != nil {
                ProgressView()
                    .controlSize(.small)
            } else if !stateManager.localLLMIsDownloaded {
                Button("Download") {
                    Task { await stateManager.preloadLocalLLMModel() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(16)

        Divider().background(Theme.textMuted.opacity(0.1))

        // ── Delete from Disk row ─────────────────────────────────────────
        if stateManager.localLLMIsDownloaded {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete Model from Disk")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.navy)
                    Text("Removes downloaded weights (~4.3 GB) from your HuggingFace cache.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button("Delete") {
                    Task { await stateManager.deleteLocalLLMModel() }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(16)

            Divider().background(Theme.textMuted.opacity(0.1))
        }

        // ── Free RAM row ─────────────────────────────────────────────────
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Free Model Memory")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Unload weights from RAM. Model stays on disk and reloads on next use.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button("Free RAM") {
                Task { await stateManager.unloadLocalLLMEngine() }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(16)
    }



    @ViewBuilder
    private var customPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Instructions (Prompt)")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.navy)
            Text("Define exactly how the AI should modify your transcribed text.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
            
            if #available(macOS 14.0, *) {
                TextField("e.g. Translate this to professional Spanish", text: $postProcessingPrompt.logged(name: "Custom Prompt"), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.navy)
                    .padding(10)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.2), lineWidth: 1))
                    .disabled(selectedTaskModel == "apple-native" && !AppStateManager.isMacOS15OrNewer())
            } else {
                TextField("e.g. Translate this to professional Spanish", text: $postProcessingPrompt.logged(name: "Custom Prompt"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.navy)
                    .padding(10)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.textMuted.opacity(0.2), lineWidth: 1))
                    .disabled(selectedTaskModel == "apple-native" && !AppStateManager.isMacOS15OrNewer())
            }
        }
        .padding(16)
        .background(Color.white) // Distinguish child area slightly if needed
    }
    
    @ViewBuilder
    private var errorDisplaySection: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        }
    }
}

struct ModelSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    @AppStorage("selectedModel") private var selectedModel: String = "apple-native"
    @State private var focusedModel: String = "apple-native"
    
    @State private var modelToDeleteTitle: String? = nil
    @State private var modelDeleteAction: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Sticky Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("Manage offline transcription models")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.8))
                
                Divider().background(Theme.textMuted.opacity(0.1))
                
                // AI Model Section
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text("AI Model Local Inference")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.navy)
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(Theme.navy)
                    }
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            
                        if #available(macOS 15.0, *) {
                            ModelCardView(
                                title: "Apple Intelligence Native (System)",
                                description: "Apple's built-in neural dictation. Requires macOS 15.0+ and runs completely on-device. No download required.",
                                size: "0 MB",
                                isSelected: focusedModel == "apple-native",
                                isDownloaded: true,
                                isActive: selectedModel == "apple-native", // Since it doesn't need "loading", active == selected
                                isLoading: false,
                                downloadProgress: nil,
                                onSelect: {
                                    focusedModel = "apple-native"
                                },
                                onUse: {
                                    selectedModel = "apple-native"
                                    Task {
                                        await stateManager.switchTranscriptionEngine(toModel: "apple-native")
                                    }
                                },
                                onDownload: {},
                                onDeleteRequest: nil
                            )
                        }
                            
                        ModelCardView(
                            title: "Tiny",
                            description: "Fastest inference for Whisper. Suitable for quick commands, basic punctuation, and short sentences.",
                            size: "75 MB",
                            isSelected: focusedModel == "tiny",
                            isDownloaded: whisper.downloadedModels.contains("tiny"),
                            isActive: selectedModel == "tiny" && whisper.activeModel == "tiny",
                            isLoading: whisper.loadingModel == "tiny",
                            downloadProgress: whisper.downloadProgresses["tiny"],
                            onSelect: {
                                focusedModel = "tiny"
                            },
                            onUse: {
                                selectedModel = "tiny"
                                whisper.changeModel(to: "tiny")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "tiny")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("tiny")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Tiny"
                                    modelDeleteAction = { whisper.deleteModel("tiny") }
                                }
                            }
                        )
                        
                        
                        ModelCardView(
                            title: "Base (English Only)",
                            description: "Optimized for English. Slightly better accuracy and speed than standard Base.",
                            size: "140 MB",
                            isSelected: focusedModel == "base.en",
                            isDownloaded: whisper.downloadedModels.contains("base.en"),
                            isActive: selectedModel == "base.en" && whisper.activeModel == "base.en",
                            isLoading: whisper.loadingModel == "base.en",
                            downloadProgress: whisper.downloadProgresses["base.en"],
                            onSelect: {
                                focusedModel = "base.en"
                            },
                            onUse: {
                                selectedModel = "base.en"
                                whisper.changeModel(to: "base.en")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "base.en")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("base.en")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Base (English Only)"
                                    modelDeleteAction = { whisper.deleteModel("base.en") }
                                }
                            }
                        )
                        
                        ModelCardView(
                            title: "Small (Multilingual)",
                            description: "Higher accuracy with acceptable speeds on modern Mac hardware.",
                            size: "240 MB",
                            isSelected: focusedModel == "small",
                            isDownloaded: whisper.downloadedModels.contains("small"),
                            isActive: selectedModel == "small" && whisper.activeModel == "small",
                            isLoading: whisper.loadingModel == "small",
                            downloadProgress: whisper.downloadProgresses["small"],
                            onSelect: {
                                focusedModel = "small"
                            },
                            onUse: {
                                selectedModel = "small"
                                whisper.changeModel(to: "small")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "small")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("small")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Small"
                                    modelDeleteAction = { whisper.deleteModel("small") }
                                }
                            }
                        )
                        
                        ModelCardView(
                            title: "Distil Large v3",
                            description: "Distil-Whisper English-optimised model. Fast inference at ~60% of large-v3 size. English only — use multilingual models below for Indonesian.",
                            size: "1.5 GB",
                            isSelected: focusedModel == "distil-whisper_distil-large-v3",
                            isDownloaded: whisper.downloadedModels.contains("distil-whisper_distil-large-v3"),
                            isActive: selectedModel == "distil-whisper_distil-large-v3" && whisper.activeModel == "distil-whisper_distil-large-v3",
                            isLoading: whisper.loadingModel == "distil-whisper_distil-large-v3",
                            downloadProgress: whisper.downloadProgresses["distil-whisper_distil-large-v3"],
                            onSelect: {
                                focusedModel = "distil-whisper_distil-large-v3"
                            },
                            onUse: {
                                selectedModel = "distil-whisper_distil-large-v3"
                                whisper.changeModel(to: "distil-whisper_distil-large-v3")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "distil-whisper_distil-large-v3")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("distil-whisper_distil-large-v3")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Distil Large v3"
                                    modelDeleteAction = { whisper.deleteModel("distil-whisper_distil-large-v3") }
                                }
                            }
                        )

                        // MARK: - Multilingual Models (good for Indonesian + 98 other languages)

                        ModelCardView(
                            title: "Medium (Multilingual)",
                            description: "99-language multilingual model. Good Indonesian accuracy (~14% WER). Best balance of speed and quality for non-English dictation on 8 GB Macs.",
                            size: "1.5 GB",
                            isSelected: focusedModel == "medium",
                            isDownloaded: whisper.downloadedModels.contains("medium"),
                            isActive: selectedModel == "medium" && whisper.activeModel == "medium",
                            isLoading: whisper.loadingModel == "medium",
                            downloadProgress: whisper.downloadProgresses["medium"],
                            onSelect: {
                                focusedModel = "medium"
                            },
                            onUse: {
                                selectedModel = "medium"
                                whisper.changeModel(to: "medium")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "medium")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("medium")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Medium (Multilingual)"
                                    modelDeleteAction = { whisper.deleteModel("medium") }
                                }
                            }
                        )

                        ModelCardView(
                            title: "Large v3 Quantized (Multilingual) ⭐",
                            description: "Best under-1GB multilingual model. Near large-v3 accuracy at only ~626 MB. Great for Indonesian on any Apple Silicon Mac.",
                            size: "626 MB",
                            isSelected: focusedModel == "large-v3-v20240930_626MB",
                            isDownloaded: whisper.downloadedModels.contains("large-v3-v20240930_626MB"),
                            isActive: selectedModel == "large-v3-v20240930_626MB" && whisper.activeModel == "large-v3-v20240930_626MB",
                            isLoading: whisper.loadingModel == "large-v3-v20240930_626MB",
                            downloadProgress: whisper.downloadProgresses["large-v3-v20240930_626MB"],
                            onSelect: {
                                focusedModel = "large-v3-v20240930_626MB"
                            },
                            onUse: {
                                selectedModel = "large-v3-v20240930_626MB"
                                whisper.changeModel(to: "large-v3-v20240930_626MB")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "large-v3-v20240930_626MB")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("large-v3-v20240930_626MB")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Large v3 Quantized (Multilingual)"
                                    modelDeleteAction = { whisper.deleteModel("large-v3-v20240930_626MB") }
                                }
                            }
                        )


                        ModelCardView(
                            title: "Large v3 (Multilingual) ⭐",
                            description: "Best overall multilingual accuracy. Top Indonesian performance (~7% WER). Requires 16 GB RAM and Apple Silicon.",
                            size: "3 GB",
                            isSelected: focusedModel == "large-v3",
                            isDownloaded: whisper.downloadedModels.contains("large-v3"),
                            isActive: selectedModel == "large-v3" && whisper.activeModel == "large-v3",
                            isLoading: whisper.loadingModel == "large-v3",
                            downloadProgress: whisper.downloadProgresses["large-v3"],
                            onSelect: {
                                focusedModel = "large-v3"
                            },
                            onUse: {
                                selectedModel = "large-v3"
                                whisper.changeModel(to: "large-v3")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "large-v3")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("large-v3")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Large v3 (Multilingual)"
                                    modelDeleteAction = { whisper.deleteModel("large-v3") }
                                }
                            }
                        )

                        ModelCardView(
                            title: "Large v3 Turbo (Multilingual) ⭐",
                            description: "Speed-optimised large-v3 variant. Near-identical accuracy at 2× faster inference. Best choice for Indonesian on 16 GB Macs.",
                            size: "1.5 GB",
                            isSelected: focusedModel == "large-v3_turbo",
                            isDownloaded: whisper.downloadedModels.contains("large-v3_turbo"),
                            isActive: selectedModel == "large-v3_turbo" && whisper.activeModel == "large-v3_turbo",
                            isLoading: whisper.loadingModel == "large-v3_turbo",
                            downloadProgress: whisper.downloadProgresses["large-v3_turbo"],
                            onSelect: {
                                focusedModel = "large-v3_turbo"
                            },
                            onUse: {
                                selectedModel = "large-v3_turbo"
                                whisper.changeModel(to: "large-v3_turbo")
                                Task {
                                    await stateManager.switchTranscriptionEngine(toModel: "large-v3_turbo")
                                }
                            },
                            onDownload: {
                                whisper.downloadModel("large-v3_turbo")
                            },
                            onDeleteRequest: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    modelToDeleteTitle = "Large v3 Turbo (Multilingual)"
                                    modelDeleteAction = { whisper.deleteModel("large-v3_turbo") }
                                }
                            }
                        )
                    }
                    .padding(.trailing, 8) // Scrollbar clearance
                    .onAppear {
                        focusedModel = selectedModel
                    }
                }
                
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            
            // MARK: Delete Confirmation Overlay
            if let title = modelToDeleteTitle, let action = modelDeleteAction {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            modelToDeleteTitle = nil
                            modelDeleteAction = nil
                        }
                    }

                CustomConfirmationDialog(
                    title: "Delete \(title)?",
                    message: "Are you sure you want to delete this AI model? You will need to download it again before you can use it for transcription.",
                    confirmTitle: "Yes, delete it",
                    cancelTitle: "Cancel",
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            action()
                            modelToDeleteTitle = nil
                            modelDeleteAction = nil
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            modelToDeleteTitle = nil
                            modelDeleteAction = nil
                        }
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: modelToDeleteTitle != nil)
    }
}

struct ModelCardView: View {
    let title: String
    let description: String
    let size: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isActive: Bool
    let isLoading: Bool
    let downloadProgress: Float?
    let onSelect: () -> Void
    let onUse: () -> Void
    let onDownload: () -> Void
    let onDeleteRequest: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)
                .font(.system(size: 16))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isActive ? Color.green : Theme.navy)
                    Spacer()
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: 4))
                    } else if isDownloaded {
                        Text("DOWNLOADED")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.1))
                            .foregroundStyle(Theme.accent)
                            .clipShape(.rect(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(0.2), lineWidth: 1))
                    }
                    
                    Text(size)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.background)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.textMuted.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(Theme.textMuted)
                        .clipShape(.rect(cornerRadius: 4))
                }
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                
                HStack {
                    if !isDownloaded {
                        if let progress = downloadProgress {
                            HStack(spacing: 6) {
                                if #available(macOS 14.0, *) {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(Theme.accent)
                                        .symbolEffect(.pulse, options: .repeating)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(Theme.accent)
                                }
                                
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .contentTransition(.numericText())
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 6))
                        } else {
                            Button(action: {
                                Logger.shared.debug("Settings: Clicked Download for \(title)")
                                onDownload()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Download")
                                }
                                .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Theme.accent.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 6))
                        }
                    } else if !isActive {
                        HStack(spacing: 8) {
                            Button(action: {
                                Logger.shared.debug("Settings: Clicked Use Model for \(title)")
                                onUse()
                            }) {
                                HStack(spacing: 4) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .controlSize(.small)
                                            .padding(.trailing, 2)
                                        Text("Initializing...")
                                    } else {
                                        Image(systemName: "play.circle")
                                        Text("Use Model")
                                    }
                                }
                                .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                            .foregroundStyle(isLoading ? Theme.textMuted : Theme.navy)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background((isLoading ? Theme.textMuted : Theme.navy).opacity(0.1))
                            .clipShape(.rect(cornerRadius: 6))
                            .clipShape(.rect(cornerRadius: 6))
                            
                            if let deleteRequestAction = onDeleteRequest {
                                Button(action: { deleteRequestAction() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Delete")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoading)
                                .foregroundStyle(.red)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.red.opacity(0.1))
                                .clipShape(.rect(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(isSelected ? Theme.navy.opacity(0.05) : Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.navy : Theme.textMuted.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle()) // Makes the whole card area tappable
        .onTapGesture {
            onSelect()
        }
    }
}

