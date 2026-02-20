import AppKit
import CoreGraphics
import Foundation

class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // We are looking for Ctrl (Control) + Shift + C
    // "C" is keycode 8 on macOS
    private let targetKeyCode: CGKeyCode = 8
    private let targetFlags: CGEventFlags = [.maskControl, .maskShift]
    
    private let stateManager: AppStateManager
    private var isRecording = false
    
    init(stateManager: AppStateManager) {
        self.stateManager = stateManager
    }
    
    func start() {
        // Request accessibility permissions if needed (required for CGEvent tap)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("Accessibility permissions not granted. Hotkeys will not work until granted.")
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
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("Hotkey capture started for Ctrl+Shift+C")
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
        
        // Exact match for Ctrl + Shift + C
        let matchesMask = flags.contains(.maskControl) && flags.contains(.maskShift)
        // Ensure no other conflicting modifier masks are present that we don't want (like Command or Option)
        let noCommand = !flags.contains(.maskCommand)
        let noOption = !flags.contains(.maskAlternate)
        
        if keyCode == targetKeyCode && matchesMask && noCommand && noOption {
            if type == .keyDown {
                if !isRecording {
                    isRecording = true
                    DispatchQueue.main.async {
                        self.stateManager.startRecording()
                    }
                }
            } else if type == .keyUp {
                if isRecording {
                    isRecording = false
                    DispatchQueue.main.async {
                        self.stateManager.stopRecording()
                    }
                    // Simulate processing delay for scaffolding purposes, will be replaced by WhisperKit later
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.stateManager.setIdle()
                    }
                }
            }
            // Consume the event so it isn't passed to the active application
            return nil 
        }
        
        return Unmanaged.passUnretained(event)
    }
}
