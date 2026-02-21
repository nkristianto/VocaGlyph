import Cocoa
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow!
    
    let stateManager = AppStateManager()
    var hotkeyService: HotkeyService!
    var audioRecorder: AudioRecorderService!
    var whisper: WhisperService!
    var output: OutputService!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide application from dock and cmd-tab switcher
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize Core Services
        stateManager.delegate = self
        audioRecorder = AudioRecorderService()
        whisper = WhisperService()
        whisper.delegate = self
        output = OutputService()
        hotkeyService = HotkeyService(stateManager: stateManager) { [weak self] in
            return self?.whisper.isReady ?? false
        }
        hotkeyService.start()
        
        // Setup Settings Window
        let settingsView = SettingsView(whisper: whisper, stateManager: stateManager)
        let hostingController = NSHostingController(rootView: settingsView)
        
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
            
            // Start capturing audio into 16Khz Float array
            audioRecorder.startRecording()
        case .processing:
            let img = NSImage(systemSymbolName: "hourglass.circle.fill", accessibilityDescription: "processing")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button?.image = img?.withSymbolConfiguration(config)
            
            // Stop capturing audio
            let floatArray = audioRecorder.stopRecording()
            print("Finished capturing audio segment. Float array size: \(floatArray.count)")
            
            // Send the float array straight to WhisperKit's neural engine processing!
            whisper.transcribe(audioArray: floatArray)
        }
        
        // Update overlay panel
        OverlayPanelManager.shared.updateVisibility(for: newState)
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
    
    func whisperServiceDidTranscribe(_ text: String) {
        // The transcription has successfully completed.
        print("Final transcription output bound in AppDelegate: \(text)")
        
        DispatchQueue.main.async {
            self.stateManager.setIdle()
            self.output.handleTranscriptionValue(text)
        }
    }
}
