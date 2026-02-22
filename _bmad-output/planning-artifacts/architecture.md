---
stepsCompleted:
  - step-01-init
  - step-02-context
  - step-03-starter
  - step-04-decisions
  - step-05-patterns
  - step-06-structure
  - step-07-validation
  - step-08-complete
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/research/technical-llm-integration-research-2026-02-21.md
workflowType: 'architecture'
project_name: 'voice-to-text'
user_name: 'Novian'
date: '2026-02-21'
lastStep: 8
status: 'complete'
completedAt: '2026-02-21T20:45:05+07:00'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
The system must globally capture audio and route it through a modular transcription engine (CoreML or GGUF). It must then optionally route the text through a secondary post-processing engine (Local ML, Apple Foundation Models, or Cloud APIs). The final output must be synthetically pasted into the active OS window. 

**Non-Functional Requirements:**
- **Performance:** Strict TTFT (< 500ms) and pipeline latency (< 1.5s) limits. Aggressive memory constraints (< 100MB inactive) mandate a robust lifecycle manager for large ML models.
- **Privacy/Security:** Must support 100% offline execution. Cloud integrations require secure, local API key storage.
- **Reliability:** The system must gracefully degrade and output raw transcription if secondary pipeline stages fail or timeout.

**Scale & Complexity:**
- Primary domain: Native macOS Application (Swift/AppKit/SwiftUI)
- Complexity level: Medium (High concurrency & memory management complexity, low UI complexity)
- Estimated architectural components: ~6 core domains (Audio Capture, Transcription Engine, Inference Engine, Orchestrator, UI/HUD, Output/Accessibility)

### Technical Constraints & Dependencies
- **Apple Silicon Requirement:** Heavy reliance on CoreML (Neural Engine) and MLX (Unified Memory) restricts the target architecture to Apple Silicon Macs.
- **Main Thread Safety:** Audio capture and ML inference must be strictly isolated from the UI thread to prevent Application Not Responding (ANR) states, especially given the global hotkey nature of the app.
- **macOS Permissions:** Requires broad OS permissions (Microphone access, Accessibility/System Events for pasting text).

### Cross-Cutting Concerns Identified
- **Concurrency & State mutations:** Safe state updates across different hardware engines and the UI.
- **Model Lifecycle Management:** Loading, warming up, and evicting multi-gigabyte models from active memory.

## Starter Template Evaluation

### Primary Technology Domain
Native macOS Desktop Application (Swift 6) existing in a brownfield context. 

### Selected Foundation: Actor-Isolated MVVM

**Rationale for Selection:**
The application requires tight integration with macOS native frameworks (Accessibility, AppKit, SwiftUI) while managing extremely heavy background processing tasks (MLX/CoreML). An Actor-isolated Model-View-ViewModel (MVVM) approach ensures that background compute never blocks the main UI thread. 

**Architectural Decisions Provided by Foundation:**

**Language & Runtime:**
Swift 6 with strict concurrency checking enabled.

**UI Framework:**
SwiftUI for declarative rendering of the Settings and floating HUD, wrapped in AppKit (`NSApplicationDelegate`, `NSWindow`, `NSStatusItem`) for low-level OS lifecycle and visual controls.

**State Management:**
`@Observable` pattern (Swift 17.0+) for ViewModels, enabling precise partial-view updates. 

**Concurrency Model:**
Core engine tasks (audio recording, WhisperKit transcription, MLX post-processing) will be defined as `globalactors` or isolated `actor` types. This enforces compile-time thread safety when passing audio buffers and large text blobs across boundaries.

## Core Architectural Decisions

### Data Flow & Inter-Process Communication (IPC)
**Decision:** `CGEvent` synthesis wrapped around `NSPasteboard` manipulation.
**Rationale:** The application paste functionality must work reliably across all generic macOS applications (native, Electron, chromium browsers). Relying on Accessibility API (`AXUIElement`) focus-detection is often flaky in third-party environments. Generating synthetic `Cmd+V` keystrokes immediately following a clipboard write is the most robust integration method.

### State Management (The "Juggler")
**Decision:** Formal State Machine Pattern for the central Orchestrator.
**Rationale:** VocaGlyph requires navigating complex, asynchronous hardware states (Microphone Active -> Neural Engine Inference -> Cloud API Wait -> OS UI Event). Using a formal State Machine ensures strict, valid state transitions (e.g. preventing the user from triggering a paste event while the microphone is still recording) and guarantees a safe fallback to the "Pasting Raw Output" state if a post-processing engine times out.

### Engine Abstraction ("Open Model Sandbox")
**Decision:** Protocol-Oriented Engine Wrappers (`TranscriptionEngine` and `PostProcessingEngine` protocols).
**Rationale:** The primary goal of Phase 2 is letting users seamlessly swap between models (Local CoreML vs. Local MLX vs. Cloud APIs). By defining strict Swift protocols (`async throws -> String` interfaces), the central Orchestrator `actor` remains completely unaware of whether it is talking to a local neural network or a REST endpoint over Wi-Fi.

## Implementation Patterns & Consistency Rules

### 1. Naming Patterns & State
**The Pattern:**
- **Strictly use `@Observable`** (Swift 17+) macro for all ViewModels and UI state representations, leveraging the native Swift data-flow.
- **Do not use** older reactive patterns (`ObservableObject`, `@Published`) unless natively required for AppKit bridging backwards compatibility.
- **Naming Conventions:** ViewModels must be suffixed with `ViewModel` (e.g., `SettingsViewModel`, `JugglerViewModel`, `HUDViewModel`).

### 2. Concurrency & Error Handling
**The Pattern:**
- **Strictly use Swift Concurrency** (`async`/`await`, `Task`, `actor`, and `@MainActor`) for orchestrating complex hardware states and memory offloading without deadlocking the main AppKit thread.
- **Do not use** Grand Central Dispatch (`DispatchQueue`), Combine, or raw completion handlers (`(Result<T, Error>) -> Void`) except to interface with legacy Objective-C or CoreAudio libraries that strictly require them.
- **Error Types:** All engine components must return typed `Error` enums specific to their domain (e.g. `ModelLoadError.fileNotFound`, `InferenceError.nanTokens`). Functions must declare explicitly that they `throw`, rather than returning `nil` or optional strings on failure.

### 3. Open Model Sandbox Structure
**The Pattern:**
- **Protocol Inheritance:** All implementation engines must conform to protocols that inherit from `Sendable` to be safely boxed and passed across strict `actor` boundaries. 

**Example Pattern Implementation:**
```swift
protocol TranscriptionEngine: Sendable {
    /// Transcribes an active linear PCM audio buffer to raw string text natively or remotely.
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String
}

protocol PostProcessingEngine: Sendable {
    /// Refines a raw transcription block according to user-defined prompt modifiers.
    func refine(text: String, prompt: String) async throws -> String
}
```

## Project Structure & Boundaries

The current brownfield Xcode project (`Swift-version/Sources/voice-to-text/`) maintains a flat hierarchy. To support the "Open Sandbox" model abstraction and strict Swift 6 concurrency patterns, AI agents must adhere to the following directory structure when creating or refactoring components.

### Complete Project Directory Structure

```text
Swift-version/Sources/voice-to-text/
├── App/                 # Application Entry and Lifecycle
│   ├── main.swift
│   ├── AppDelegate.swift
│   └── AppStateManager.swift
├── Domain/              # Protocols and Core Business Logic
│   ├── Protocols.swift  # (Engine interfaces goes here)
│   └── Models/          # (Data structs like AppConfig)
├── Engines/             # Concrete Model Implementations
│   ├── Transcription/
│   │   ├── WhisperKitEngine.swift  # (Refactored WhisperService)
│   │   └── MLXEngine.swift         # (Future Phase 2)
│   └── PostProcessing/
│       ├── AppleIntelligenceEngine.swift
│       └── QwenEngine.swift        # (Future Phase 2)
├── Services/            # Core App Services (Actors)
│   ├── AudioRecorderService.swift
│   ├── HotkeyService.swift
│   └── OutputService.swift         # (The Paste Actor)
├── UI/                  # Views and ViewModels (@Observable)
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── SettingsViewModel.swift
│   └── HUD/
│       ├── RecordingOverlayView.swift
│       └── OverlayPanelManager.swift
└── Utilities/           # Cross-cutting concerns
    ├── LoggerService.swift
    └── Theme.swift
```

### Architectural Boundaries

**The Orchestrator Boundary:**
The `AppStateManager` (or a dedicated `JugglerService` actor) acts as the central conductor. UI components in the `UI/` folder *never* talk directly to the `Engines/`. They emit intents to the Orchestrator, which handles the complex async pipeline (Audio -> Transcription -> PostProcessing -> OutputService).

**The UI-Thread Boundary:**
Core ML and MLX compute jobs run exclusively in the `Engines/` directory. All engine implementations must be carefully isolated from the `@MainActor`. No transcription logic should ever be referenced directly inside a SwiftUI `View` or `ViewModel`.

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:**
The Actor-isolated MVVM pattern aligns perfectly with Swift 6 and the requirement to strictly isolate the main thread from heavy MLX/CoreML workloads.

### Requirements Coverage Validation ✅

**Epic/Feature Coverage:**
All functional requirements (Local models vs Cloud Post-processing) are architecturally supported by the "Open Sandbox" Engine Protocols. Non-Functional Requirements (Latency & Memory) are supported by explicit state machine management and strict concurrency rules.

### Implementation Readiness Validation ✅

**Structure Completeness:**
The physical folder structure provides a clear, unambiguous map for where new code should live, preventing spaghetti architecture as Phase 2 features are added.

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION
**Confidence Level:** High

**Key Strengths:**
*   **Safety First:** The strict concurrency rules (`@MainActor` vs `globalactor`) prevent the most common failure mode of macOS apps (App Not Responding).
*   **Future-Proof Sandbox:** The protocol-oriented engine approach means plugging in a new model (like Qwen via MLX) requires zero changes to the core orchestrator or UI.

**Areas for Future Enhancement:**
*   *XPC Services:* If model memory footprints become completely unmanageable within the main app process, the architecture allows for the `Engines/` to be extracted into separate macOS XPC processes later.

### Implementation Handoff

**AI Agent Guidelines:**
- Follow all architectural decisions exactly as documented.
- Use implementation patterns (Task, Actor, @Observable) consistently across all components.
- Respect project directory structure and boundaries (Main Actor vs Background Compute).
- Refer to this document for all architectural questions before refactoring existing code.
