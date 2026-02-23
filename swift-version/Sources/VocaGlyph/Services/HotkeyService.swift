import AppKit
import CoreGraphics
import Foundation

enum GlobalShortcutOption: String, CaseIterable, Identifiable {
    case ctrlShiftC = "⌃ ⇧ C"
    case optionSpace = "⌥ Space"
    case cmdShiftSpace = "⌘ ⇧ Space"
    case ctrlSpace = "⌃ Space"
    
    var id: String { self.rawValue }
    
    var keyCode: CGKeyCode {
        switch self {
        case .ctrlShiftC: return 8 // C
        case .optionSpace, .cmdShiftSpace, .ctrlSpace: return 49 // Space
        }
    }
    
    var flags: CGEventFlags {
        switch self {
        case .ctrlShiftC: return [.maskControl, .maskShift]
        case .optionSpace: return [.maskAlternate]
        case .cmdShiftSpace: return [.maskCommand, .maskShift]
        case .ctrlSpace: return [.maskControl]
        }
    }
}


class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var targetKeyCode: CGKeyCode = 8
    private var targetFlags: CGEventFlags = [.maskControl, .maskShift]

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
        let presetRaw = UserDefaults.standard.string(forKey: "globalShortcutPreset") ?? GlobalShortcutOption.ctrlShiftC.rawValue
        let preset = GlobalShortcutOption(rawValue: presetRaw) ?? .ctrlShiftC
        
        self.targetKeyCode = preset.keyCode
        self.targetFlags = preset.flags
        Logger.shared.info("Hotkey Service updated to listen for: \(presetRaw) (Code: \(targetKeyCode), Flags: \(targetFlags.rawValue))")
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
        
        Logger.shared.info("Hotkey capture started for Ctrl+Shift+C")
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
        if targetFlags.contains(.maskControl) { matchesMask = matchesMask && flags.contains(.maskControl) } else { matchesMask = matchesMask && !flags.contains(.maskControl) }
        if targetFlags.contains(.maskShift) { matchesMask = matchesMask && flags.contains(.maskShift) } else { matchesMask = matchesMask && !flags.contains(.maskShift) }
        if targetFlags.contains(.maskCommand) { matchesMask = matchesMask && flags.contains(.maskCommand) } else { matchesMask = matchesMask && !flags.contains(.maskCommand) }
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
