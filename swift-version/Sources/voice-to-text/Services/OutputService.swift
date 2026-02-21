import Cocoa
import ApplicationServices
import CoreGraphics

class OutputService: @unchecked Sendable {
    
    /// Main entry point for outputting the transcribed text.
    func handleTranscriptionValue(_ text: String) {
        guard !text.isEmpty else { return }
        
        var processedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let shouldRemoveFillers = UserDefaults.standard.bool(forKey: "removeFillerWords")
        if shouldRemoveFillers {
            // Remove common conversational filler words.
            // (?i) makes it case-insensitive.
            // \b ensures we match whole words only (so we don't turn "plumber" into "plber" by removing "um").
            // [\s,]* optionally matched trailing spaces and commas.
            let pattern = "(?i)\\b(um|uh|ah|like|you know)\\b[\\s,]*"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: " ")
            }
            
            // Clean up any double spaces introduced by replacement
            processedText = processedText.replacingOccurrences(of: "  ", with: " ")
            processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if processedText.isEmpty { return }
        
        Logger.shared.info("Transcription: \(processedText)")
        
        // 1. Copy text to the system pasteboard
        copyToPasteboard(text: processedText + " ") // Add a trailing space for fluid dictation UX
        
        // 2. Play a subtle success sound
        NSSound(named: NSSound.Name("Pop"))?.play()
        
        // 3. Attempt to actively paste the text using CGEvent (Cmd+V) if we have accessibility trust
        if AXIsProcessTrusted() {
            simulatePasteKeystroke()
        } else {
            Logger.shared.error("AXIsProcessTrusted() returned false. Falling back to clipboard only.")
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
        
        Logger.shared.info("Cmd+V synthesized via CGEvent!")
    }
}
