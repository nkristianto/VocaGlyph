---
epic_key: epic-11
title: Swift Feature Parity Implementation
status: ready-for-dev
created: 2026-02-21
---

# Epic 11: Swift Feature Parity Implementation

## Epic Objectives
This epic aims to close the feature parity gap between the original Go/Wails requirements and the newly migrated native Swift AppKit/SwiftUI version of VocaGlyph. It covers critical user experience features, application lifecycle integrations, and offline transcription enhancements to ensure the application meets all MVP metrics defined in the updated Swift PRD.

## Success Metrics
- Clicking the Menu Bar icon presents a native dropdown menu with Settings and Quit options.
- The user can configure the app to launch automatically at macOS login.
- Global Hotkey bindings can be dynamically customized by the user in Settings.
- The `WhisperKit` engine dynamically applies user preferences for Dictation Language and Auto-Punctuation.
- The application automatically removes conversational filler words (e.g., "um", "uh") from transcriptions when enabled.
- A native `ProgressView` tracks the CoreML Whisper model download progress in the Settings UI so users aren't left waiting blindly.

## Key User Stories

### Story 11.1: Swift Feature Parity & Enhancements
- Implement the Menu Bar Dropdown `NSMenu` in `AppDelegate.swift`.
- Integrate macOS `SMAppService` for Launch at Login functionality.
- Dynamically bind and listen for `CGEvent` Custom Global Hotkeys.
- Pass Language and Auto-Punctuation variables into the WhisperKit `DecodingOptions`.
- Implement Regex string filtering to strip filler words during text output.
- Bind the WhisperKit download initialization to a SwiftUI `ProgressView` in `SettingsView`.
