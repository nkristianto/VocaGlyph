import Cocoa
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
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
        hotkeyService = HotkeyService(stateManager: stateManager)
        hotkeyService.start()
        
        // Setup popover
        let settingsView = SettingsView(stateManager: stateManager, whisper: whisper)
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.preferredContentSize = CGSize(width: 320, height: 280) // Set a base height for the SwiftUI View
        
        popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Voice to Text")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
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
    
    // MARK: - Popover Actions
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Bring app to front so it has focus and can intercept clicks
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

extension AppDelegate: AppStateManagerDelegate {
    // MARK: - AppStateManagerDelegate
    func appStateDidChange(newState: AppState) {
        let button = statusItem.button
        switch newState {
        case .idle:
            button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "voice-to-text")
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
    }
}

extension AppDelegate: WhisperServiceDelegate {
    func whisperServiceDidUpdateState(_ state: String) {
        // e.g., "Ready" vs "Failed" to update UI visually later
        print("WhisperService state update: \(state)")
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
