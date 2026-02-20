import Cocoa
import ApplicationServices

class OutputService {
    
    /// Main entry point for outputting the transcribed text.
    func handleTranscriptionValue(_ text: String) {
        guard !text.isEmpty else { return }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty { return }
        
        print("OutputService attempting to paste: '\(trimmedText)'")
        
        // 1. Copy text to the system pasteboard
        copyToPasteboard(text: trimmedText + " ") // Add a trailing space for fluid dictation UX
        
        // 2. Play a subtle success sound
        NSSound(named: NSSound.Name("Pop"))?.play()
        
        // 3. Attempt to actively paste the text using CGEvent (Cmd+V) if we have accessibility trust
        if AXIsProcessTrusted() {
            simulatePasteKeystroke()
        } else {
            print("AXIsProcessTrusted() returned false. Falling back to clipboard only.")
        }
    }
    
    private func copyToPasteboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func simulatePasteKeystroke() {
        let src = CGEventSource(stateID: .hidSystemState)
        
        // Virtual key code for 'v' is 0x09
        let keyV: CGKeyCode = 0x09
        
        // Create Cmd+V down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true) else { return }
        keyDownEvent.flags = .maskCommand
        
        // Create Cmd+V up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false) else { return }
        keyUpEvent.flags = .maskCommand
        
        // Post events to the system
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
        
        print("Cmd+V synthesized via CGEvent!")
    }
}
