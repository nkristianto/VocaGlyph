# Story 3.3: Post-Processing Protocol Engine

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an AI architect,
I want a strict `PostProcessingEngine` protocol abstraction,
so that I can hot-swap different language models endlessly.

## Acceptance Criteria

1. **Given** a text string is transcribed
2. **When** post-processing is enabled
3. **Then** it is strictly forced through an `async throws -> String` protocol wrapper

## Tasks / Subtasks

- [x] Task 1: Define the `PostProcessingEngine` protocol
  - [x] Subtask 1.1: Create the `PostProcessingEngine` protocol inheriting from `Sendable` in `Sources/voice-to-text/Domain/Protocols.swift`.
  - [x] Subtask 1.2: Define the `refine(text: String, prompt: String) async throws -> String` method within the protocol.
- [x] Task 2: Integrate `PostProcessingEngine` into the Orchestrator (`AppStateManager` or `EngineRouter`)
  - [x] Subtask 2.1: Add an optional `postProcessingEngine` instance or selection state.
  - [x] Subtask 2.2: Update the text completion logic so that if post-processing is enabled, the raw transcribed text is passed to `refine(text:prompt:)` before it's sent to the `OutputService`.
  - [x] Subtask 2.3: Ensure errors and timeouts from `refine` are appropriately handled, implementing **graceful degradation** (FR13 / NFR8) to instantly output the raw transcription if post-processing fails or takes too long.
- [x] Task 3: Update `SettingsView` integration for Post-Processing
  - [x] Subtask 3.1: Expose a toggle in `SettingsView` (and state in `SettingsViewModel`) to enable/disable automated text post-processing.
  - [x] Subtask 3.2: Expose a text field for the custom instructions (prompt) to govern how post-processing modifies the text (FR12).

## Dev Notes

- **Architecture:** Protocol-Oriented Engine Wrappers. Building `PostProcessingEngine` alongside the existing `TranscriptionEngine`. The exact structure can be referenced in `_bmad-output/planning-artifacts/architecture.md`.
- **Concurrency:** Implement using strict Swift Concurrency (`async`/`await`, `actor`, `Sendable`). The orchestrator should safely call the protocol without blocking the Main Thread (`@MainActor`).
- **Reliability (Graceful Degradation):** If the post-processing engine times out (>2000ms as per NFR3 for pipeline latency, NFR8 for cloud API timeouts) or throws an error, the orchestrator MUST rescue the operation and send the original raw transcribed text to `OutputService`. Never swallow errors blindly; catch them, log them, and trigger the fallback.

### Project Structure Notes

- `PostProcessingEngine` protocol should be placed in `Sources/voice-to-text/Domain/Protocols.swift`.
- The orchestrator logic should be in `Sources/voice-to-text/App/AppStateManager.swift` or `Sources/voice-to-text/Engines/Transcription/EngineRouter.swift`.
- Settings additions go to `Sources/voice-to-text/UI/Settings/SettingsView.swift` and `SettingsViewModel.swift`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-3-3-Post-Processing-Protocol-Engine]
- [Source: _bmad-output/planning-artifacts/architecture.md#3-Open-Model-Sandbox-Structure]
- [Source: _bmad-output/planning-artifacts/prd.md#3-Engine-Orchestration--Post-Processing]
- [Source: _bmad-output/project-context.md]

## Dev Agent Record

### Agent Model Used

Gemini 2.5 Pro

### Debug Log References
- Added missing `import AVFoundation` in `AppStateManagerTests.swift`.

### Completion Notes List
- Implemented `PostProcessingEngine` protocol in `Protocols.swift`.
- Added `MockPostProcessingEngine` to test framework and verified graceful degradation logic (falling back to raw output on error/timeout).
- Added `TaskGroup` racing in `AppStateManager` to strictly enforce the 2000ms NFR3/NFR8 timeout before gracefully bypassing the engine.
- Exposed Post-Processing Enable toggle and Prompt modification logic directly to `GeneralSettingsView` (SwiftUI).

### File List
- `Sources/voice-to-text/Domain/Protocols.swift`
- `Sources/voice-to-text/App/AppStateManager.swift`
- `Sources/voice-to-text/UI/Settings/SettingsView.swift`
- `Tests/voice-to-textTests/AppStateManagerTests.swift`
