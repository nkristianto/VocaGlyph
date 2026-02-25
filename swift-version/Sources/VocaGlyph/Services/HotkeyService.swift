import AppKit
import CoreGraphics
import Foundation

// MARK: - Shortcut Storage Keys
extension UserDefaults {
    static let customShortcutKeyCodeKey = "customShortcutKeyCode"
    static let customShortcutModifiersKey = "customShortcutModifiers"

    /// Default shortcut: ⌃ ⇧ C  (keyCode 8, Control + Shift)
    static let defaultShortcutKeyCode: Int = 8
    static let defaultShortcutModifiers: UInt64 = CGEventFlags([.maskControl, .maskShift]).rawValue
}

// MARK: - Shortcut Display Helpers
struct ShortcutDisplayHelper {
    /// Convert a CGKeyCode + CGEventFlags into a human-readable string like "⌃ ⇧ C"
    static func displayString(keyCode: CGKeyCode, flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskControl)  { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)    { parts.append("⇧") }
        if flags.contains(.maskCommand)  { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    static func keyName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0:  return "A"
        case 11: return "B"
        case 8:  return "C"
        case 2:  return "D"
        case 14: return "E"
        case 3:  return "F"
        case 5:  return "G"
        case 4:  return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1:  return "S"
        case 17: return "T"
        case 32: return "U"
        case 9:  return "V"
        case 13: return "W"
        case 7:  return "X"
        case 16: return "Y"
        case 6:  return "Z"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - HotkeyService
class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var targetKeyCode: CGKeyCode = CGKeyCode(UserDefaults.defaultShortcutKeyCode)
    private var targetFlags: CGEventFlags = CGEventFlags(rawValue: UserDefaults.defaultShortcutModifiers)

    private let stateManager: AppStateManager

    // --- Re-entry guards (accessed only on the CGEvent callback thread) ---
    // isRecording: true from first keyDown until resetToIdle() fires on main thread.
    private var isRecording = false
    // lastActivationTime: absolute time of the most recent recording start.
    // Debounce window prevents rapid re-triggers caused by audio engine startup
    // latency (~100 ms), where sub-threshold presses always capture 0 frames.
    private var lastActivationTime: CFAbsoluteTime = 0
    private let debounceInterval: CFAbsoluteTime = 0.05  // 50 ms — guards against key bounce and rapid double-taps

    init(stateManager: AppStateManager) {
        self.stateManager = stateManager

        loadShortcutFromDefaults()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.loadShortcutFromDefaults()
        }
    }

    /// Called by AppDelegate when AppState returns to .idle.
    /// Resets the re-entry guard so the next hotkey press is accepted.
    /// Must be called on the main thread.
    func resetToIdle() {
        isRecording = false
    }
    
    private func loadShortcutFromDefaults() {
        let keyCodeInt = UserDefaults.standard.object(forKey: UserDefaults.customShortcutKeyCodeKey) as? Int
            ?? UserDefaults.defaultShortcutKeyCode
        let modifiersRaw = UserDefaults.standard.object(forKey: UserDefaults.customShortcutModifiersKey) as? UInt64
            ?? UserDefaults.defaultShortcutModifiers

        self.targetKeyCode = CGKeyCode(keyCodeInt)
        self.targetFlags = CGEventFlags(rawValue: modifiersRaw)

        let display = ShortcutDisplayHelper.displayString(keyCode: targetKeyCode, flags: targetFlags)
        Logger.shared.info("Hotkey Service updated to listen for: \(display) (Code: \(targetKeyCode), Flags: \(targetFlags.rawValue))")
    }
    
    func start() {
        // Request accessibility permissions if needed (required for CGEvent tap)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            Logger.shared.error("Accessibility permissions not granted. Hotkeys will not work until granted.")
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        // CFMachPortCallback that triggers when keys are pressed
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mySelf = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return mySelf.handleEvent(proxy: proxy, type: type, event: event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.error("Failed to create event tap")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        Logger.shared.info("Hotkey capture started")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Match required masks completely (for keyDown only)
        var matchesMask = true
        if targetFlags.contains(.maskControl)  { matchesMask = matchesMask && flags.contains(.maskControl)  } else { matchesMask = matchesMask && !flags.contains(.maskControl) }
        if targetFlags.contains(.maskShift)    { matchesMask = matchesMask && flags.contains(.maskShift)    } else { matchesMask = matchesMask && !flags.contains(.maskShift) }
        if targetFlags.contains(.maskCommand)  { matchesMask = matchesMask && flags.contains(.maskCommand)  } else { matchesMask = matchesMask && !flags.contains(.maskCommand) }
        if targetFlags.contains(.maskAlternate) { matchesMask = matchesMask && flags.contains(.maskAlternate) } else { matchesMask = matchesMask && !flags.contains(.maskAlternate) }
        
        if keyCode == targetKeyCode {
            if type == .keyDown && matchesMask {
                let now = CFAbsoluteTimeGetCurrent()
                let withinDebounce = (now - lastActivationTime) < debounceInterval

                // Block re-entry if already recording OR if within the debounce window.
                // Also block (and flash a message) when the engine is still initialising:
                // the recording would succeed but transcription would immediately fail.
                if stateManager.currentState == .initializing {
                    DispatchQueue.main.async {
                        self.stateManager.flashNotReadyMessage()
                    }
                } else if !isRecording && !withinDebounce {
                    isRecording = true
                    lastActivationTime = now
                    DispatchQueue.main.async {
                        self.stateManager.startRecording()
                    }
                }
                return nil // Consume event
            } else if type == .keyUp {
                // Stop only if we actually started a recording in this press cycle.
                if isRecording {
                    // Don't clear isRecording here — keep it true until the app
                    // is fully idle (resetToIdle() is called from AppDelegate).
                    // This prevents a new keyDown from sneaking in while processing.
                    DispatchQueue.main.async {
                        self.stateManager.stopRecording()
                    }
                    return nil
                }

                // Consume matching keyUp even if we weren't recording
                if matchesMask { return nil }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
