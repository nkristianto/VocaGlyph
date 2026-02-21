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
    private let canRecordCallback: () -> Bool
    private var isRecording = false
    
    init(stateManager: AppStateManager, canRecordCallback: @escaping () -> Bool) {
        self.stateManager = stateManager
        self.canRecordCallback = canRecordCallback
        
        loadShortcutFromDefaults()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.loadShortcutFromDefaults()
        }
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
            tap: .cghidEventTap,
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
                if !isRecording {
                    guard canRecordCallback() else {
                        NSSound.beep()
                        return nil // Consume event
                    }
                    
                    isRecording = true
                    DispatchQueue.main.async {
                        self.stateManager.startRecording()
                    }
                }
                return nil // Consume event
            } else if type == .keyUp {
                // If it's keyUp and we are recording, stop it immediately, regardless of whether modifiers are still held
                if isRecording {
                    isRecording = false
                    DispatchQueue.main.async {
                        self.stateManager.stopRecording()
                    }
                    // Consume the event to prevent system from handling the orphaned keyUp
                    return nil
                }
                
                // If we aren't recording but the keys match perfectly, consume it anyway
                if matchesMask {
                    return nil
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
