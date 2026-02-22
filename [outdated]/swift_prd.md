---
title: Product Requirements Document - VocaGlyph (Swift Edition)
author: Novian
date: 2026-02-21
---

# Product Requirements Document - VocaGlyph

## Executive Summary

VocaGlyph is a personal-use macOS menu bar dictation application that delivers fast, private, fully offline speech-to-text transcription. Moving away from the Wails/Go tech stack, this iteration is built entirely using **Native Swift**, leveraging **WhisperKit** and Apple's CoreML/Neural Engine for maximum performance with an ultra-low memory footprint. The user activates recording via a global hotkey, speaks, and the transcribed text is intelligently typed/pasted directly into the active application.

### Why Swift & WhisperKit?

The migration to native Swift directly resolves the idle memory footprint issues caused by embedded webviews (Wails/Electron) and complex CGo build pipelines. By using WhisperKit, VocaGlyph taps directly into the Apple Neural Engine, offering lightning-fast transcription latency with native macOS AppKit and SwiftUI integration.

## Project Classification

| Attribute | Value |
|-----------|-------|
| **Project Type** | Desktop App (macOS native, AppKit + SwiftUI) |
| **Domain** | Personal Productivity / Local AI Tooling |
| **Complexity** | Medium |
| **Tech Stack** | Swift 5.10+, macOS 14+, SwiftUI, AppKit, WhisperKit (CoreML), AVFoundation |
| **OS Integration** | Global hotkey via `CGEvent` tap; paste via `CGEvent` keyboard synthesis; clipboard via `NSPasteboard` |
| **Storage** | Models/config persist via `AppStorage` and FileManager |

---

## Success Criteria

### Technical Success
| Metric | Target |
|--------|--------|
| **Transcription latency** | < 500ms from end of utterance to text insertion |
| **Memory footprint** | < 100MB RAM during idle, highly optimized during active use |
| **Transcription accuracy** | 90–95% on base/small CoreML models |
| **App startup** | Instant readiness |
| **Offline operation** | 100% — zero network calls at runtime after model download |

---

## Product Scope

### MVP — Minimum Viable Product

- macOS menu bar icon (persistent, Accessory app mode)
- Menu bar dropdown menu on click (showing at least "Settings" and "Quit")
- Global hotkey to start/stop recording (Ctrl+Shift+C)
- WhisperKit local inference (CoreML variants: tiny, base, small)
- Ultra-minimalist HUD floating overlay (`NSPanel`) for Recording/Processing states
- Auto-paste transcribed text into the active application via `CGEvent` synthesis
- **Auto-remove filler words** (e.g., "um", "uh", "like") from the transcription before pasting
- Copy to clipboard (`NSPasteboard`) as fallback
- Settings UI (SwiftUI): hotkey configuration, model selection, language selection, auto-punctuation, filler word removal
- Display a precise progress bar during model downloads in Settings
- Launch at login support

### Growth Features (Post-MVP)
- Download progress indicators for models in SettingsView
- Auto-send (press Enter after paste)
- Context-aware text enhancement
- Custom dictionaries

---

## Functional Requirements

### Recording & Audio Capture
- **FR1:** App captures audio at 16kHz via default macOS mic using `AVFoundation`.
- **FR2:** App registers a global hotkey to toggle recording on/off.
- **FR3:** Visual HUD overlay appears when recording is active.

### Transcription
- **FR4:** App utilizes `WhisperKit` for fully local, offline transcription.
- **FR5:** User can change WhisperKit models (tiny vs base).
- **FR6:** The app automatically filters out common conversational filler words (e.g., "um", "uh") from the final text if enabled in settings.

### Text Output
- **FR7:** Text is pasted directly to the active app via Cmd+V synthetic key events.
- **FR8:** Fallback copies text to the native clipboard automatically.

### UI & UX
- **FR9:** Clicking the menu bar icon opens a dropdown menu with options like "Settings" and "Quit", rather than immediately opening the Settings window.
- **FR10:** Settings presented in a native transparent/material Swift Window without standard titlebars.
- **FR11:** `RecordingOverlayView` appears as a `.nonactivatingPanel` to prevent focus stealing.
- **FR12:** Settings modifications (language, hotkey, models, filler word removal) apply dynamically.
- **FR13:** A visual progress bar is displayed in the Settings UI when a new model is being downloaded.
