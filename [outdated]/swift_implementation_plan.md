# VocaGlyph Swift Migration: Feature Parity Implementation Plan

This plan documents the changes required to bring the Swift codebase to 100% feature parity with the MVP requirements outlined in the PRD, based on the gap analysis.

## User Review Required

> [!WARNING]
> **Dynamic Hotkeys in macOS** requires complex keycode mapping if we want full customizability. Implementing a robust global shortcut recorder (like the `KeyboardShortcuts` package) might be necessary. To keep things native and simple for the MVP, we can implement predefined enum-based shortcuts or wire up a basic key listener in Settings. **Is using a 3rd party package like `sindresorhus/KeyboardShortcuts` acceptable, or should we strictly stick to native `CGEvent` code?**

## Proposed Changes

### 1. Menu Bar Dropdown Menu
Use standard AppKit `NSMenu` attached to the `NSStatusItem`.
#### [MODIFY] `Swift-version/Sources/voice-to-text/AppDelegate.swift`
- Remove the direct `button.action = #selector(toggleSettingsWindow(_:))` assignment from `statusItem`.
- Create an `NSMenu`.
- Add an `NSMenuItem` titled "Settings..." with the action `toggleSettingsWindow(_:)`.
- Add an `NSMenuItem` titled "Quit VocaGlyph" with the action `terminate(_:)`.
- Assign the menu to `statusItem.menu`.

### 2. Launch at Login Integration
Use macOS 13+ `SMAppService` to handle launch at login.
#### [MODIFY] `Swift-version/Sources/voice-to-text/SettingsView.swift`
- Add a new `Toggle` in the "General" tab for "Launch at Login".
- Connect the toggle state to `SMAppService.mainApp.status` read/write operations to register the application in the system's login items.

### 3. Dynamic Hotkey Binding
Wire the Settings UI selection to the actual `HotkeyService`.
#### [MODIFY] `Swift-version/Sources/voice-to-text/HotkeyService.swift`
- Modify the class to accept and listen for changes to the `@AppStorage` defaults.
- Re-configure the `targetKeyCode` and `targetFlags` dynamically instead of hardcoding `Ctrl+Shift+C`. 
- Provide an API `func updateShortcut(keyCode: CGKeyCode, flags: CGEventFlags)` to restart the tap with new variables.

#### [MODIFY] `Swift-version/Sources/voice-to-text/SettingsView.swift`
- Expand the Shortcut visual button to invoke a key capture mode (or present a Picker with common shortcut combinations) and save both the character name and the actual `CGKeyCode`.

### 4. Dynamic Language & Whisper Settings
Pass UI settings down into the `WhisperKit` inference engine.
#### [MODIFY] `Swift-version/Sources/voice-to-text/WhisperService.swift`
- Read `dictationLanguage` from `UserDefaults` mapping semantic strings (e.g. "Spanish (ES)") to WhisperKit compatible locale codes (e.g. "es").
- Read `autoPunctuation` from `UserDefaults`. Apply custom post-processing or pass relevant tokens if supported by WhisperKit decoding options.
- Update `transcribe()` to construct `DecodingOptions` dynamically using these values.

### 5. Filler Word Removal
Filter the transcription text before outputting it.
#### [MODIFY] `Swift-version/Sources/voice-to-text/SettingsView.swift`
- Add an `@AppStorage("removeFillerWords")` toggle under the Recording or General tab.
#### [MODIFY] `Swift-version/Sources/voice-to-text/WhisperService.swift` or `OutputService.swift`
- Check `removeFillerWords`. If true, apply a Regular Expression (e.g., `(?i)\b(um|uh|ah|like|you know)\b[\s,]*`) to strip filler words and clean up adjacent punctuation before sending to `OutputService`.

### 6. Model Download Progress Bar
#### [MODIFY] `Swift-version/Sources/voice-to-text/WhisperService.swift`
- Utilize the `progressCallback` provided by `WhisperKit.download()` to update an `@Published` progress float (0.0 to 1.0) and a status string.
#### [MODIFY] `Swift-version/Sources/voice-to-text/SettingsView.swift`
- Observe the download progress state from `WhisperService`.
- Replace the unconnected "Download Model" button with a native SwiftUI `ProgressView(value: whisper.downloadProgress)` and a dynamic status label ("Downloading... 45%") when downloading is active.

---

## Verification Plan

### Automated Tests
- Run the exising Swift XCTest suite (`swift test` or via Xcode) to ensure `AppStateManager` and mock delegates are not broken by the new properties.

### Manual Verification
1. **Menu Bar Menu:** Click the menu bar icon. Verify a dropdown appears with "Settings..." and "Quit". Verify clicking them performs the expected actions.
2. **Launch at Login:** Toggle the setting in UI, check `System Settings > General > Login Items` to visually confirm VocaGlyph is added/removed.
3. **Dynamic Hotkey:** Change the shortcut in Settings. Press the new shortcut. Verify that the HUD pill appears and recording starts. Press the old shortcut and verify it does *not* trigger recording.
4. **Language Selection:** Switch language to Spanish. Speak a Spanish phrase. Verify the transcribed output matches Spanish rather than hallucinated English.
5. **Download Progress Bar:** Delete local models in `~/Library/Caches/`. Open Settings, select a model, and verify that a distinct `ProgressView` fills up linearly.
6. **Filler Word Removal:** Enable the toggle. Dictate "Um, hello there, like, how are you?". Verify the output is "Hello there, how are you?".
