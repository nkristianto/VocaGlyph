import Cocoa
import SwiftUI
import AppKit
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow!
    
    let stateManager = AppStateManager()
    var hotkeyService: HotkeyService!
    var audioRecorder: AudioRecorderService!
    var whisper: WhisperService!
    var output: OutputService!
    
    var sharedModelContainer: ModelContainer? = {
        let schema = Schema([
            TranscriptionItem.self,
            PostProcessingTemplate.self,
            TemplateRule.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Could not create ModelContainer: \(error)")
            return nil
        }
    }()
    
    lazy var permissionsService = PermissionsService()
    var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide application from dock and cmd-tab switcher
        NSApp.setActivationPolicy(.accessory)
        
        if permissionsService.areAllCorePermissionsGranted {
            initializeCoreServices()
        } else {
            showOnboardingWindow()
        }
    }
    
    func showOnboardingWindow() {
        let onboardingView = OnboardingView(permissionsService: permissionsService) { [weak self] in
            DispatchQueue.main.async {
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.initializeCoreServices()
                self?.toggleSettingsWindow(nil) // Open Settings after onboarding
            }
        }
        
        let hostingController = NSHostingController(rootView: onboardingView)
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        onboardingWindow?.center()
        onboardingWindow?.isReleasedWhenClosed = false
        onboardingWindow?.contentViewController = hostingController
        onboardingWindow?.title = "Welcome to VocaGlyph"
        onboardingWindow?.titleVisibility = .hidden
        onboardingWindow?.titlebarAppearsTransparent = true
        onboardingWindow?.isMovableByWindowBackground = true
        
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor func initializeCoreServices() {
        // Seed default post-processing templates if this is a first launch
        if let container = sharedModelContainer {
            let context = container.mainContext
            TemplateSeederService.seedDefaultTemplatesIfNeeded(context: context)
            stateManager.modelContext = context
        }

        // Initialize Core Services
        stateManager.delegate = self
        audioRecorder = AudioRecorderService()
        whisper = WhisperService()
        whisper.delegate = self
        stateManager.sharedWhisper = whisper // Let AppStateManager reuse this single instance
        stateManager.engineRouter = EngineRouter(engine: whisper) // initial default
        stateManager.startEngine() // Boot up whatever model is selected in UserDefaults
        output = OutputService()
        hotkeyService = HotkeyService(stateManager: stateManager)
        hotkeyService.start()
        
        // Setup Settings Window
        var anySettingsView: AnyView
        let settingsView = SettingsView(whisper: whisper, stateManager: stateManager)
        if let container = sharedModelContainer {
            anySettingsView = AnyView(settingsView.modelContainer(container))
        } else {
            anySettingsView = AnyView(settingsView)
        }
        let hostingController = NSHostingController(rootView: anySettingsView)
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        settingsWindow.center()
        settingsWindow.setFrameAutosaveName("SettingsWindow")
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.contentViewController = hostingController
        settingsWindow.title = "VocaGlyph Settings"
        
        // Hide native title bar completely for custom SwiftUI sidebar appearance
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        
        // Add an empty toolbar to ensure standard margin (~10-15px) for traffic light buttons
        let dummyToolbar = NSToolbar()
        dummyToolbar.showsBaselineSeparator = false
        settingsWindow.toolbar = dummyToolbar
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let imgUrl = Bundle.module.url(forResource: "appbaricon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: imgUrl) {
                // Ensure proper sizing for the status bar
                nsImage.size = NSSize(width: 18, height: 18)
                nsImage.isTemplate = true // Allows macOS to tint it for light/dark mode
                button.image = nsImage
            } else {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VocaGlyph")
            }
        }
        
        let menu = NSMenu()
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(toggleSettingsWindow(_:)), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitMenuItem = NSMenuItem(title: "Quit VocaGlyph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitMenuItem.target = NSApp
        menu.addItem(quitMenuItem)
        
        statusItem.menu = menu
        
        // Setup Overlay Panel for Recording
        OverlayPanelManager.shared.setupPanel(with: stateManager)
    }
    
    @objc func simulateRecording() {
        stateManager.startRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.stateManager.stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.stateManager.setIdle()
            }
        }
    }
    
    // MARK: - Window Actions
    @objc func toggleSettingsWindow(_ sender: AnyObject?) {
        if settingsWindow.isVisible {
            settingsWindow.orderOut(nil)
        } else {
            // makeKeyAndOrderFront ensures window comes to front
            settingsWindow.makeKeyAndOrderFront(nil)
            // Bring app to front so it has focus and can intercept clicks
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension AppDelegate: AppStateManagerDelegate {
    // MARK: - AppStateManagerDelegate
    func appStateDidChange(newState: AppState) {
        let button = statusItem.button
        
        switch newState {
        case .idle:
            // Let HotkeyService know it can accept the next hotkey press.
            hotkeyService.resetToIdle()
            if let imgUrl = Bundle.module.url(forResource: "appbaricon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: imgUrl) {
                nsImage.size = NSSize(width: 18, height: 18)
                nsImage.isTemplate = true
                button?.image = nsImage
            } else {
                button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VocaGlyph")
            }
        case .initializing:
            let img = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "initializing")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
            button?.image = img?.withSymbolConfiguration(config)
        case .recording:
            let img = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "recording")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button?.image = img?.withSymbolConfiguration(config)

            // Start capturing audio. startRecording() now throws on engine
            // failure so we can reset state immediately rather than hanging.
            do {
                try audioRecorder.startRecording()
            } catch {
                Logger.shared.error("AppDelegate: audioRecorder.startRecording() failed — \(error.localizedDescription). Resetting to idle.")
                stateManager.setIdle()
            }
        case .processing:
            let img = NSImage(systemSymbolName: "hourglass.circle.fill", accessibilityDescription: "processing")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button?.image = img?.withSymbolConfiguration(config)

            // Stop capturing audio
            if let buffer = audioRecorder.stopRecording() {
                print("Finished capturing audio segment.")
                stateManager.processAudio(buffer: buffer)
            } else {
                stateManager.setIdle()
            }
        }
        
        // Update overlay panel
        OverlayPanelManager.shared.updateVisibility(for: newState)
    }

    func appStateManagerDidTranscribe(text: String) {
        // The transcription has successfully completed.
        print("Final transcription output bound in AppDelegate: \(text)")
        
        // Save to local history
        if !text.isEmpty, let container = sharedModelContainer {
            Task { @MainActor in
                let context = container.mainContext
                let newItem = TranscriptionItem(text: text)
                context.insert(newItem)
                
                self.cleanupOldHistoryItems(context: context)
                
                do {
                    try context.save()
                } catch {
                    print("Failed to save new transcription item: \(error)")
                }
            }
        }
        
        DispatchQueue.main.async {
            self.output.handleTranscriptionValue(text)
        }
    }
    
    @MainActor
    private func cleanupOldHistoryItems(context: ModelContext) {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return }
        
        let fetchDescriptor = FetchDescriptor<TranscriptionItem>(
            predicate: #Predicate { $0.timestamp < thirtyDaysAgo }
        )
        
        do {
            let oldItems = try context.fetch(fetchDescriptor)
            for item in oldItems {
                context.delete(item)
            }
        } catch {
            print("Failed to fetch old items for cleanup: \(error)")
        }
    }
}

extension AppDelegate: WhisperServiceDelegate {
    func whisperServiceDidUpdateState(_ state: String) {
        // e.g., "Ready" vs "Failed" to update UI visually later
        print("WhisperService state update: \(state)")
        
        DispatchQueue.main.async {
            switch state {
            case "Initializing Engine...", "Loading into memory...", "Warming up Neural Engine...", "Processing":
                if self.stateManager.currentState != .initializing {
                    self.stateManager.setInitializing()
                }
            case "Ready", "Model not downloaded.", "Failed", "Model warming up...":
                if self.stateManager.currentState == .initializing {
                    self.stateManager.setIdle()
                }
            default:
                if state.hasPrefix("Downloading") || state.hasPrefix("Falling back") {
                    if self.stateManager.currentState != .initializing {
                        self.stateManager.setInitializing()
                    }
                }
            }
        }
    }
}
