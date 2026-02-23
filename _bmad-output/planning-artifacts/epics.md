---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
---

# voice-to-text - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for voice-to-text, decomposing the requirements from the PRD and Architecture requirements into implementable stories. *Items marked with `[x]` have already been natively implemented in the Swift-version codebase.*

## Requirements Inventory

### Functional Requirements

FR1: Users can start and stop dictation globally via a customizable hotkey. [x]
FR2: Users receive visual feedback indicating the current system state (Listening, Processing, Inactive). [x]
FR3: Users can manually cancel an active dictation session via the visual interface.
FR4: Users receive visual feedback identifying the currently active processing engine.
FR5: System captures voice input while dictation is active. [x]
FR6: System converts spoken audio to text locally using a designated high-efficiency model (e.g., CoreML). [x]
FR7: System converts spoken audio to text locally using a designated high-accuracy model (e.g., GGUF).
FR8: Users can enable or disable automated text post-processing.
FR9: System can refine transcribed text using native OS intelligence frameworks (e.g., Apple Intelligence).
FR10: System can refine transcribed text using user-selected local open models (e.g., Qwen) for offline processing.
FR11: System can refine transcribed text using configured external cloud APIs.
FR12: Users can define custom instructions (prompts) that govern how post-processing modifies the text.
FR13: System outputs raw transcription if the post-processing engine fails or times out.
FR14: System inserts final processed text directly into the previously focused application at the cursor position. [x]
FR15: Users can access application settings via a persistent system menu. [x]
FR16: Users can select their active transcription model from available local models. [x]
FR17: Users can select their active post-processing engine.
FR18: Users can securely store API credentials for cloud-based engines.
FR19: Users can configure the application to launch automatically on system startup. [x]

### NonFunctional Requirements

NFR1 (Startup): The application must be ready to receive audio within 100ms. [x]
NFR2 (Raw Transcription latency): TTFT for MLX or CoreML must not exceed 500ms. [x]
NFR3 (Pipeline Latency): Total perceived latency for post-processing must not exceed 1.5 seconds.
NFR4 (Memory Footprint): Background process must consume less than 100MB of RAM.
NFR5 (Local First): Core transcription and local post-processing must execute 100% on-device offline.
NFR6 (Ephemeral Data): Audio recordings must be held only in volatile memory (RAM). [x]
NFR7 (API Key Storage): External API keys must be securely stored in macOS Keychain.
NFR8 (Graceful Degradation): Cloud API timeouts (>2000ms) automatically abort and paste raw text.

### Additional Requirements

- **Actor-Isolated MVVM Architecture**: Implementation must isolate the Main thread from Engine tasks using Swift Concurrency (`actor`, `@MainActor`, `async/await`). [x]
- **State Machine Pattern**: The Orchestrator must manage strict asynchronous hardware states (Microphone Active -> Neural Engine Inference). [x]
- **Protocol-Oriented Engine Wrappers**: Post-processing must adhere to strict Swift protocols to abstract local vs cloud behavior.
- **Accessibility Integration**: `CGEvent` synthesis wrapped around `NSPasteboard` for reliable active-window pasting. [x]

### FR Coverage Map

FR1: Epic 1 - Configured in HotkeyService
FR2: Epic 1 - Menu Bar icon updates
FR3: Epic 1 - HUD interaction
FR4: Epic 3 - Feedback updates for LLM vs CoreML
FR5: Epic 1 - AudioRecorderService buffers
FR6: Epic 1 - WhisperKit transcription
FR7: Epic 2 - MLX/GGUF integration
FR8: Epic 3 - Toggle in Settings
FR9: Epic 3 - Foundation Models
FR10: Epic 4 - Open Models
FR11: Epic 4 - Cloud APIs
FR12: Epic 3 - Custom prompt injection
FR13: Epic 3 - Intelligent Fallback
FR14: Epic 1 - OutputService pasting
FR15: Epic 1 - AppDelegate StatusItem
FR16: Epic 1 - Model Settings view
FR17: Epic 3 - Model Sandbox UI
FR18: Epic 4 - Keychain Service
FR19: Epic 1 - SMAppService integration

## Epic List

### Epic 1: Core Dictation & macOS Parity `[Status: Mostly Implemented]`
Provides the fundamental voice-to-text pipeline, ensuring global app accessibility, high-efficiency offline transcription via CoreML, and seamless pasting into macOS applications.
**FRs covered:** FR1, FR2, FR3, FR5, FR6, FR14, FR15, FR16, FR19

### Epic 2: High-Accuracy Translation Infrastructure `[Status: Not Started]`
Enables support for advanced GGUF-based models (like Parakeet) natively via Apple's MLX architecture for unmatched local precision.
**FRs covered:** FR7

### Epic 3: Apple Intelligence & Pipeline Post-Processing `[Status: Not Started]`
Introduces the "Dynamic Model Juggler" allowing native Apple Foundation models to optionally alter, fix, and post-process raw text before pasting.
**FRs covered:** FR4, FR8, FR9, FR12, FR13, FR17

### Epic 4: External Engine Sandbox (Cloud APIs & KVC) `[Status: Not Started]`
Completes the open model sandbox by letting power users securely drop in Anthropic or Gemini API capabilities as post-processing orchestrators.
**FRs covered:** FR10, FR11, FR18

### Epic 6: First-Launch Experience `[Status: Done]`
Provides a seamless onboarding flow ensuring all required system permissions are granted before dictation begins.
**FRs covered:** N/A (Usability/Permissions)

### Epic 7: Local History & Management `[Status: Done]`
Provides a local historical record of all transcriptions using SwiftData, allowing users to view, search, copy, and delete past dictations.
**FRs covered:** N/A (Usability/Data Management)

### Epic 8: Post-Processing Template System `[Status: Not Started]`
Replaces the monolithic free-text post-processing prompt with a named, ordered, editable template system stored in SwiftData. Reduces local LLM hallucinations by rendering templates as strictly structured numbered prompts. Gives users full control over refinement behaviour without requiring code changes.
**FRs covered:** FR12 (custom instructions for post-processing)

---

## Epic 1: Core Dictation & macOS Parity

Provides the fundamental voice-to-text pipeline, ensuring global app accessibility, high-efficiency offline transcription via CoreML, and seamless pasting into macOS applications.

### Story 1.1: Audio Capture & Global Hotkeys `[x] Implemented`

As a power user,
I want to globally trigger recording via custom hotkeys,
So that I can start dictating instantly regardless of my active app.

**Acceptance Criteria:**
**Given** VocaGlyph is running in the background
**When** the user presses `Ctrl+Shift+C` (or configured hotkey)
**Then** `AudioRecorderService` immediately begins capturing a 16kHz Float array
**And** the global engine state transitions to `.recording`

### Story 1.2: CoreML Offline Transcription Engine `[x] Implemented`

As a privacy-conscious user,
I want my speech transcribed completely offline instantly,
So that I never leak audio to the cloud.

**Acceptance Criteria:**
**Given** the user releases the recording hotkey
**When** the audio buffer is dispatched to `WhisperService`
**Then** it natively processes the CoreML model and returns text under 500ms
**And** conversational filler words are optionally stripped if enabled in settings

### Story 1.3: Synthetic OS Output Service `[x] Implemented`

As a fast-paced user,
I want transcribed text to automatically type into my focused window,
So that I don't have to manually copy and paste.

**Acceptance Criteria:**
**Given** `WhisperService` finishes decoding
**When** the Orchestrator receives the raw text
**Then** `OutputService` writes it to `NSPasteboard` and successfully dispatches a `CGEvent` `Cmd+V` stroke

### Story 1.4: App Settings Lifecycle `[x] Implemented`

As an everyday user,
I want the app to invisibly manage itself and launch on login,
So that I never think about keeping it open.

**Acceptance Criteria:**
**Given** the user opens the Menu Bar settings
**When** they check "Launch at login"
**Then** macOS `SMAppService` registers the daemon persistently
**And** users can dynamically download or delete WhisperKit models from the UI

---

## Epic 2: High-Accuracy Translation Infrastructure

Enables support for advanced GGUF-based models natively via Apple's MLX architecture.

### Story 2.1: MLX Swift Engine Integration `[ ] Not Started`

As a technical user,
I want to use Parakeet GGUF models on my M-series Mac,
So that I get the highest possible offline dictation accuracy.

**Acceptance Criteria:**
**Given** MLX Swift libraries are linked
**When** a user initiates dictation targeting an MLX model
**Then** the `MLXEngine` correctly mounts the unified memory and decodes the audio tensor
**And** the TTFT latency remains within strict limits

### Story 2.2: Dual Engine Routing Controller `[ ] Not Started`

As an orchestrator,
I want to automatically route audio to either WhisperKit or MLX,
So that the correct architecture parses the data seamlessly.

**Acceptance Criteria:**
**Given** the user selects Parakeet in Settings
**When** dictation starts
**Then** the `AppStateManager` routes the buffer exclusively to the `MLXEngine` instead of `WhisperKit`

---

## Epic 3: Apple Intelligence & Pipeline Post-Processing

Introduces the "Dynamic Model Juggler" allowing native Apple Foundation models to optionally alter, fix, and post-process raw text before pasting, along with Concurrent Co-existence transcription through Apple native ML frameworks.

### Story 3.1: Transcription Architecture Abstraction `[ ] Not Started`

As an AI Architect,
I want to refactor the audio routing state layer to rely strictly on a `TranscriptionEngine` protocol,
So that I can run either Whisper or Apple Native models behind the same unified interface.

**Acceptance Criteria:**
**Given** the dictation pipeline requires transcription
**When** initiating an audio decoding request
**Then** the request is forwarded to an abstracted protocol instead of a concrete class
**And** audio buffer isolation relies strictly on Swift Concurrency (`Actor`) to prevent OOM or data races

### Story 3.2: Native Apple Speech Transcription (`SpeechAnalyzer`) `[x] Implemented`

As a user on macOS 15.1+,
I want to transcribe text natively using Apple's Neural Engine,
So that I save RAM and achieve blazing fast inference while maintaining privacy via Private Cloud Compute boundaries.

**Acceptance Criteria:**
**Given** the user selects "Apple Intelligent Native" as their transcription engine
**When** the dictation begins
**Then** `AVAudioEngine` successfully routes the stream to `SpeechAnalyzer`/`SpeechTranscriber`
**And** the engine parses the Attributed String stream accurately and efficiently
**And** the existing Whisper engine safely deallocates from RAM to prevent jetsam events

### Story 3.3: Post-Processing Protocol Engine `[ ] Not Started`

As an AI architect,
I want a strict `PostProcessingEngine` protocol abstraction,
So that I can hot-swap different language models endlessly.

**Acceptance Criteria:**
**Given** a text string is transcribed
**When** post-processing is enabled
**Then** it is strictly forced through an `async throws -> String` protocol wrapper

### Story 3.4: Apple Foundation Models Integration `[ ] Not Started`

As an M-series Mac owner,
I want macOS Native GenAI to fix my grammar,
So that I don't have to download multi-gigabyte models myself.

**Acceptance Criteria:**
**Given** the OS is macOS 15.1+
**When** the user applies an Apple Intelligence "Grammar Fix" custom prompt
**Then** the OS natively refines the dictation string before it is handed to `OutputService`

### Story 3.5: Graceful Fallback Switcher `[ ] Not Started`

As a user dictating quickly,
I want the app to paste raw text if Apple Intelligence times out,
So that I am never locked waiting for an AI API.

**Acceptance Criteria:**
**Given** a Post-Processing engine fails or exceeds 2000ms
**When** processing occurs
**Then** the Orchestrator instantly terminates the job and passes the raw `WhisperKit` text onward to be typed

---

## Epic 4: External Engine Sandbox (Cloud APIs & KVC)

Completes the open model sandbox by letting power users securely drop in Anthropic or Gemini API capabilities directly.

### Story 4.1: Secure Keychain Settings `[ ] Not Started`

As a security-minded developer,
I want API credentials stored in hardware cryptography,
So that my expensive cloud tokens are secure.

**Acceptance Criteria:**
**Given** the user wants to add an Anthropic Key
**When** inputted into the UI
**Then** the key is encrypted via Apple `KeychainService` and never written to `UserDefaults`

### Story 4.2: REST API Protocol Conformance `[ ] Not Started`

As an advanced user,
I want Gemini to translate my dictation to Japanese,
So that I can seamlessly write across international lines.

**Acceptance Criteria:**
**Given** the Post-Processing Engine is set to Cloud API
**When** the user speaks english
**Then** the Audio is transcribed offline, sent via secure REST to Gemini, translated, and typed automatically

---

## Epic 6: First-Launch Experience

Provides a seamless first-launch onboarding flow that ensures all required system permissions are granted before dictation begins, preventing broken states and manual restarts.

### Story 6.1: Onboarding Permissions Screen `[ ] Not Started`

As a new user,
I want to be guided to grant Microphone, Accessibility, and Full Disk Access permissions on first launch,
So that the app functions correctly immediately without requiring a manual restart.

**Acceptance Criteria:**
**Given** a fresh install (no permissions), when the app launches, then the Onboarding window is shown and the main engines/hotkeys do NOT start.
**Given** the Onboarding window is visible, when a user clicks a permission row, then the native macOS permission prompt appears.
**Given** the Onboarding window, when all permissions are granted, then the "Continue" button becomes active.
**Given** an active "Continue" button, when clicked, then the Onboarding window closes and the main application (status bar icon, hotkeys, transcription engine) starts up seamlessly without requiring an app restart.
**Given** all permissions were previously granted, when the app launches, then the Onboarding window is bypassed and the app starts normally.

---

## Epic 7: Local History & Management

Provides a local historical record of all transcriptions using SwiftData, allowing users to view, search, copy, and delete past dictations.

### Story 7.1: Transcription History Settings Page `[ ] Not Started`

As an active user,
I want to view a chronological history of my recent dictations within Settings,
So that I can recover text if I lost my clipboard or want to reference past thoughts.

**Acceptance Criteria:**
**Given** a successful dictation, when the text is finalized by the engine, then a new `TranscriptionItem` is automatically saved to the local SwiftData store.
**Given** the History Settings page is open, when the user views the list, then the transcriptions are displayed grouped chronologically by date with their timestamps.
**Given** a populated history list, when the user types in the search bar, then the list instantly filters to show only matching transcriptions.
**Given** a specific history item, when the user clicks the Copy button, then the text is copied to the macOS clipboard.
**Given** a specific history item, when the user selects Delete from the menu, then the item is deleted from the database and the UI updates immediately.
**Given** a database containing items older than 30 days, when a new dictation finishes (or the app launches), then those old items are automatically deleted from SwiftData.

---

## Epic 8: Post-Processing Template System

Replaces the monolithic free-text post-processing prompt with a named, ordered, editable template system stored in SwiftData. Reduces local LLM hallucinations by rendering templates as tightly structured numbered prompts. Gives users full control over refinement behaviour across any engine without requiring code changes.

### Story 8.1: Post-Processing Template System `[ ] Not Started`

As a power user who relies on post-processing AI to refine my dictations,
I want to define and manage named templates — each containing an ordered list of discrete rules — to control how the AI refines my text,
So that I can precisely tune the AI's behaviour per use-case, reduce hallucinations from local models, and easily switch between different refinement styles.

**Acceptance Criteria:**
**Given** no templates exist, when the app launches for the first time, then three system templates are seeded: "General Cleanup" (active default), "Meeting Notes", and "Raw — No Processing".
**Given** the user opens Settings → Post-Processing, when viewing the section, then a Template subsection is visible with a picker, rule editor, and template management controls.
**Given** the user selects a template, when a dictation finishes and post-processing is enabled, then `TemplatePromptRenderer.render(template:)` builds a numbered-list prompt that is passed to `engine.refine(text:prompt:)`.
**Given** a template with no enabled rules, when `render(template:)` is called, then it returns an empty string, effectively suppressing post-processing.
**Given** the combined character count of all enabled rules exceeds 800 characters, when the template editor is open, then an inline warning is shown: "Too many rules may reduce accuracy for local AI engines."
**Given** the user has edited a system template, when they tap "Reset to Default", then the template's rules are restored to their original seeded values.
**Given** a custom (non-system) template, when the user taps "Delete Template", then it is permanently removed from SwiftData.
**Given** the implementation is complete, when `AppStateManager.processAudio()` builds the post-processing prompt, then it no longer reads `UserDefaults["postProcessingPrompt"]`.
