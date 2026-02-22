# Feature Parity Analysis: Go/Wails PRD vs Swift Implementation

This document compares the original MVP requirements from the Go/Wails PRD (`prd.md`) against the current state of the native Swift codebase.

## 🟢 Implemented (Full Parity)

1. **Menu Bar Presence (Accessory Mode)**
   - *Requirement:* App runs as a macOS menu bar app with no Dock icon.
   - *Status:* **Implemented.** `NSApp.setActivationPolicy(.accessory)` and `NSStatusItem` are correctly configured in `AppDelegate.swift`.

2. **Global Hotkey Capture**
   - *Requirement:* Start/stop recording via hotkey.
   - *Status:* **Implemented.** `HotkeyService.swift` uses `CGEvent.tapCreate` to capture global key events.

3. **Audio Capture**
   - *Requirement:* Capture 16kHz audio from microphone.
   - *Status:* **Implemented.** `AudioRecorderService.swift` uses `AVFoundation` with `AVAudioConverter` to format audio precisely for WhisperKit.

4. **Local Transcription Inference**
   - *Requirement:* Use whisper.cpp local models without network calls.
   - *Status:* **Implemented.** Shifted to native `WhisperKit` in `WhisperService.swift` for CoreML acceleration on Apple Silicon.

5. **Transcription Overlay/HUD**
   - *Requirement:* Real-time UI indicator during operation.
   - *Status:* **Implemented.** `RecordingOverlayView` + `OverlayPanelManager` provides an ultra-minimalist floating glass pill.

6. **Text Output & Paste Fallback**
   - *Requirement:* Auto-paste to active app, copy to clipboard as fallback.
   - *Status:* **Implemented.** `OutputService.swift` copies to `NSPasteboard.general` and synthesizes `Cmd+V` using `CGEvent`.

7. **Settings UI Foundations**
   - *Requirement:* UI to configure the app.
   - *Status:* **Implemented.** `SettingsView.swift` accurately reflects the VocaGlyph design system using SwiftUI.

---

## 🔴 Missing or Incomplete Gaps (To Be Implemented)

1. **1. Launch at Login**
   - *Requirement:* App can be configured to launch at macOS login.
   - *Current State:* No logic present in the Swift version to enable this (requires `SMAppService`).

2. **2. Menu Bar Dropdown Menu**
   - *Requirement:* Clicking the menu bar icon should show a standard macOS menu with "Settings" and "Quit" options (like Wispr Flow).
1.  **1. Launch at Login**
    -   *Requirement:* App can be configured to launch at macOS login.
    -   *Current State:* No logic present in the Swift version to enable this (requires `SMAppService`).

2.  **2. Menu Bar Dropdown Menu**
    -   *Requirement:* Clicking the menu bar icon should show a standard macOS menu with "Settings" and "Quit" options (like Wispr Flow).
    -   *Current State:* Currently, clicking the `NSStatusItem.button` directly calls `toggleSettingsWindow(_:)`. There is no `NSMenu` attached.

3.  **3. Dynamic Hotkey Binding**
    -   *Requirement:* User can rebind the hotkey in Settings.
    -   *Current State:* `SettingsView.swift` stores a string representation in `@AppStorage("globalShortcut")`, but `HotkeyService.swift` is hardcoded to listen specifically for `Ctrl + Shift + C` (keycode 8 + masks).

4.  **4. Dynamic Language & Punctuation Application**
    -   *Requirement:* Respect the user's selected dictation language and auto-punctuation preferences.
    -   *Current State:* `WhisperService.swift` hardcodes `DecodingOptions(language: "en")`. `@AppStorage` values from Settings are ignored during inference.

5.  **5. Model Download Progress UI**
    -   *Requirement:* When downloading a model, show a visible progress bar in the settings page.
    -   *Current State:* `WhisperKit.download(variant:)` handles downloads implicitly, but the `SettingsView` "Download Model" button is unconnected and lacks progress indication.

6.  **6. Filler Word Removal**
    -   *Requirement:* Automatically filter out common conversational filler words (e.g., "um", "uh") before inserting the text.
    -   *Current State:* Transcript string is passed verbatim to the `OutputService`. No filtering logic exists.
