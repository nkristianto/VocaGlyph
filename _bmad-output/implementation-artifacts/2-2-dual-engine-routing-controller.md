# Story 2.2: Dual Engine Routing Controller

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an orchestrator,
I want to automatically route audio to either WhisperKit or MLX,
so that the correct architecture parses the data seamlessly.

## Acceptance Criteria

1. **Given** the user selects Parakeet (or other MLX model) in Settings
2. **When** dictation starts
3. **Then** the `AppStateManager` routes the buffer exclusively to the `MLXEngine` instead of `WhisperKit`
4. **And** only the active engine parses the data for transcription

## Tasks / Subtasks

- [x] Task 1: Engine Selection Logic (AC: 1, 3)
  - [x] Read the active model selection from AppStorage/UserDefaults
  - [x] Initialize the matching `TranscriptionEngine` protocol wrapper (`WhisperService` or `MLXEngine`)
- [x] Task 2: Audio Routing (AC: 2, 4)
  - [x] Modify `AppStateManager` or orchestrator logic to dynamically pass the `AVAudioPCMBuffer` to the initialized engine
  - [x] Ensure non-active engines are unloaded from memory to free up RAM (NFR)
- [x] Task 3: Testing & Validation
  - [x] Create unit tests that mock the routing dependency
  - [x] Verify audio is never double-processed

## Dev Notes

- **Architecture Boundary**: The orchestrator (`AppStateManager`) shouldn't care *which* engine it is calling. It should just hold a generic property `let currentEngine: TranscriptionEngine` and route to it.
- **Memory Management**: MLX (Unified Memory) and CoreML (WhisperKit) can consume massive amounts of memory. When switching between them in Settings, ensure the previously active engine correctly drops its loaded resources.

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

