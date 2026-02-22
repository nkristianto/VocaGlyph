---
story_key: story-11.1
**Epic**: [Epic 11: Swift Feature Parity](./epic-11-swift-feature-parity.md)
title: Implement Missing Swift MVP Features
**Status**: Review
**Assignee**: [AI Agent]
---

# Story 11.1: Implement Missing Swift MVP Features

## Description
Based on the Feature Parity Architecture review, several MVP requirements from the original PRD remain un-implemented in the native Swift version of VocaGlyph. This story encompasses the end-to-end implementation of those remaining features: Menu Bar Dropdown, Launch at Login, Dynamic Hotkeys, Dynamic Language/Punctuation for WhisperKit, Filler Word Removal, and a Model Download Progress Bar.

## Acceptance Criteria
- **Given** the app is running in the menu bar, **When** the user clicks the icon, **Then** a dropdown menu appears with "Settings..." and "Quit VocaGlyph" options.
- **Given** the user is in Settings, **When** they toggle "Launch at Login", **Then** the app is added or removed from the macOS system login items.
- **Given** the user changes the global hotkey in Settings, **When** they press the new key combination, **Then** dictation starts, and the old combination no longer works.
- **Given** the user changes their dictation language, **When** they begin dictation, **Then** the updated language code is passed to WhisperKit's `DecodingOptions`.
- **Given** the user selects "Remove Filler Words", **When** they dictate "um" or "uh", **Then** those words are stripped from the final pasted text.
- **Given** the user switches to a new model size, **When** the model begins downloading, **Then** a progress bar reflects the download completion state in the Settings UI.

## Technical Notes
- Target the code strictly within the `Swift-version` directory.
- Use `SMAppService.mainApp` for Launch at Login toggling.
- Use an AppKit `NSMenu` and attach it to the `NSStatusItem` in `AppDelegate.swift`.
- Update `HotkeyService.swift` to allow modifying `targetKeyCode` and `targetFlags` instead of hardcoding `Ctrl+Shift+C`. 
- Define a Regular Expression for filler words (e.g., `(?i)\b(um|uh|ah|like|you know)\b[\s,]*`).

## Tasks/Subtasks
- [x] Subtask 1: Replace direct Settings toggle with Menu Bar Dropdown in `AppDelegate.swift`
- [x] Subtask 2: Implement "Launch at Login" toggle in `SettingsView.swift` referencing `SMAppService`
- [x] Subtask 3: Refactor `HotkeyService.swift` and `SettingsView.swift` to support dynamic global hotkey binding
- [x] Subtask 4: Link `dictationLanguage` and `autoPunctuation` `@AppStorage` variables to WhisperKit `DecodingOptions`
- [x] Subtask 5: Implement filler word removal logic using Regex before text pipeline output
- [x] Subtask 6: Surface the WhisperKit `.download` callback into a SwiftUI `ProgressView` in `SettingsView.swift`
- [x] Subtask 7: Update `AppStateManager` or mock tests to incorporate new properties if necessary and confirm them green

## Dev Notes
- Ensure `@AppStorage` defaults are consistently read without locking the UI thread.
- Downloading models should update `@Published` variables on the Main Actor to avoid SwiftUI state purple warnings.

## Dev Agent Record
### Debug Log

### Completion Notes

## File List

## Change Log
