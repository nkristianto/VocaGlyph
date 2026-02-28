import Cocoa
import ApplicationServices
import CoreGraphics

func osDevLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/vocaglyph_debug.log")
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let time = formatter.string(from: Date())
    let line = "[\(time)] OutputService: \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) { handle.write(data) }
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}

class OutputService: @unchecked Sendable {
    
    /// Main entry point for outputting the transcribed text.
    func handleTranscriptionValue(_ text: String) {
        osDevLog("handleTranscriptionValue called! Input string length: \(text.count), text: '\(text)'")
        
        guard !text.isEmpty else {
            osDevLog("String is empty, returning early.")
            return
        }
        
        var processedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        osDevLog("After trimming: '\(processedText)'")
        
        let shouldRemoveFillers = UserDefaults.standard.bool(forKey: "removeFillerWords")
        if shouldRemoveFillers {
            // Remove common conversational filler words.
            // (?i) makes it case-insensitive.
            // \b ensures we match whole words only (so we don't turn "plumber" into "plber" by removing "um").
            // [\s,]* optionally matches trailing spaces and commas.
            let pattern = "(?i)\\b(um|uh|ah|like|you know)\\b[\\s,]*"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: " ")
            }
            
            // Clean up any double spaces introduced by replacement
            processedText = processedText.replacingOccurrences(of: "  ", with: " ")
            processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Auto-punctuation: capitalize first letter and append a terminal period if absent.
        // Whisper and Apple engines produce punctuated output natively; the guard on existing
        // terminal punctuation makes this a safe no-op for those engines while fixing Parakeet,
        // which returns raw unpunctuated text from FluidAudio.
        let shouldAutoPunctuate = UserDefaults.standard.bool(forKey: "autoPunctuation")
        if shouldAutoPunctuate {
            processedText = applyBasicPunctuation(processedText)
        }
        
        if processedText.isEmpty { return }
        
        Logger.shared.info("Transcription: \(processedText)")
        
        // 1. Copy text to the system pasteboard
        copyToPasteboard(text: processedText + " ") // Add a trailing space for fluid dictation UX
        
        // 2. Play a subtle success sound
        NSSound(named: NSSound.Name("Pop"))?.play()
        
        // 3. Attempt to actively paste the text using CGEvent (Cmd+V) if we have accessibility trust
        if AXIsProcessTrusted() {
            // Add a tiny delay to ensure the user has fully released the hotkeys
            // and the system pasteboard has synchronized across applications.
            // Because Apple Native dictation is nearly instant, it can fire Cmd+V
            // before the modifier keys from the hotkey trigger are released.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.simulatePasteKeystroke()
            }
        } else {
            Logger.shared.error("AXIsProcessTrusted() returned false. Falling back to clipboard only.")
        }
    }
    
    // MARK: - Text Processing Helpers

    /// Capitalizes the first character and appends a period if no terminal punctuation exists.
    /// Engine-safe: if the text already ends with `.`, `?`, or `!` (Whisper/Apple output),
    /// this is a pure no-op — no double-punctuation occurs.
    func applyBasicPunctuation(_ text: String) -> String {
        var result = text
        // Capitalize first letter
        if let first = result.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first) {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        // Append period only when no terminal punctuation is present
        let terminators: Set<Character> = [".", "?", "!", ":", ";", ","]
        if let last = result.last, !terminators.contains(last) {
            result += "."
        }
        return result
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
        
        // Post events to the session event stream.
        // .cgSessionEventTap works in the App Sandbox when Accessibility permission is granted.
        keyDownEvent.post(tap: .cgSessionEventTap)
        keyUpEvent.post(tap: .cgSessionEventTap)
        
        Logger.shared.info("Cmd+V synthesized via CGEvent!")
    }
}
