# Story 3.1: Transcription Architecture Abstraction

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an AI Architect,
I want to refactor the audio routing state layer to rely strictly on a `TranscriptionEngine` protocol,
so that I can run either Whisper or Apple Native models behind the same unified interface.

## Acceptance Criteria

1. **Given** the dictation pipeline requires transcription
   **When** initiating an audio decoding request
   **Then** the request is forwarded to an abstracted protocol instead of a concrete class
   **And** audio buffer isolation relies strictly on Swift Concurrency (`Actor`) to prevent OOM or data races

## Tasks / Subtasks

- [x] Define the `TranscriptionEngine` protocol
  - [x] Must inherit from `Sendable`
  - [x] Must define an `async throws -> String` method for transcribing an `AVAudioPCMBuffer`
- [x] Refactor existing transcription logic
  - [x] Update `WhisperService` or underlying engine logic to conform to the new `TranscriptionEngine` protocol
- [x] Refactor the Orchestrator / App State Manager
  - [x] Ensure the main orchestrator (e.g., `AppStateManager`) interacts only with the `TranscriptionEngine` protocol, not concrete engine implementations
  - [x] Ensure the active engine instance is strictly isolated within an `Actor` to prevent data races when multiple ML engines touch the audio buffer
- [x] Write/Update Unit Tests
  - [x] Create a `MockTranscriptionEngine` confirming to the protocol for fast UI/orchestrator testing
  - [x] Verify state transitions and delegation continue to work seamlessly with the mocked engine

## Dev Notes

- **Architecture:** Protocol-Oriented Programming (POP) and the Dependency Inversion Principle (DIP). High-level audio recording managers must depend on the abstract `TranscriptionEngine` protocol.
- **Concurrency:** Strictly use Swift Concurrency (`async`/`await`, `Task`, `actor`). Avoid Grand Central Dispatch (`DispatchQueue`). Core ML and future MLX compute jobs must run exclusively in the `Engines/` directory, isolated from the `@MainActor`.
- **Error Handling:** Never swallow errors or return `nil`. Always throw typed errors (e.g., enums) to allow orchestrator fallbacks.
- **Resource Gating:** The implementation must guarantee that only one engine instance processes the buffer actively at a time (unless explicitly one-to-many via `AVAudioEngine`, which will be relevant in Story 3.2). Currently, protect the instance behind an Actor.

### Project Structure Notes

- New protocols should go into `Domain/Protocols.swift` or a dedicated interface file within `Domain/`.
- The revised Whisper/MLX wrappers should remain in `Engines/Transcription/`.
- UI files (`UI/`) should remain completely unaware of this refactoring, communicating only via intents to the Orchestrator (`App/AppStateManager.swift`).

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Engine-Abstraction]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]

## Dev Agent Record

### Agent Model Used

gemini-2.5-pro

### Debug Log References

### Completion Notes List
- Implemented `TranscriptionEngine` protocol extending `Sendable`.
- Modified `AudioRecorderService.stopRecording` to return `AVAudioPCMBuffer?` directly for more accurate buffer forwarding.
- Created `EngineRouter` actor to safely sandbox and proxy the memory-heavy AI transcription calls without blocking the orchestrator.
- Refactored `AppStateManager` to own the engine router natively and execute transcription as a `Task { }`, pushing results back to the delegate when finished.
- Verified test suite passes successfully.
  
### File List
- `Sources/voice-to-text/Domain/Protocols.swift`
- `Sources/voice-to-text/Engines/Transcription/EngineRouter.swift`
- `Sources/voice-to-text/Services/AudioRecorderService.swift`
- `Sources/voice-to-text/Engines/Transcription/WhisperService.swift`
- `Sources/voice-to-text/App/AppStateManager.swift`
- `Sources/voice-to-text/App/AppDelegate.swift`
- `Tests/voice-to-textTests/Engines/EngineRouterTests.swift`
