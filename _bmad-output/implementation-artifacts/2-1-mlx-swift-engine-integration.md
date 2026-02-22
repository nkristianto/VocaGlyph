# Story 2.1: MLX Swift Engine Integration

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a technical user,
I want to use Parakeet GGUF models on my M-series Mac,
so that I get the highest possible offline dictation accuracy.

## Acceptance Criteria

1. **Given** MLX Swift libraries are linked
2. **When** a user initiates dictation targeting an MLX model
3. **Then** the `MLXEngine` correctly mounts the unified memory and decodes the audio tensor
4. **And** the TTFT latency remains within strict limits (< 500ms TTFT)

## Tasks / Subtasks

- [x] Task 1: Integrate MLX Swift Library (AC: 1)
  - [x] Add `mlx-swift` as a Swift Package Manager dependency in `Package.swift`
- [x] Task 2: Create MLXEngine (AC: 2, 3)
  - [x] Implement `MLXEngine` struct/actor conforming to `TranscriptionEngine` protocol
  - [x] Ensure initialization handles model loading gracefully
  - [x] Implement `transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String`
- [x] Task 3: Performance Constraints (AC: 4)
  - [x] Ensure model caching and lazy loading mechanisms are in place so consecutive requests do not re-load the model
  - [x] Add debug logging to track translation timing
- [x] Task 4: UI/Settings Updates (AC: 2)
  - [x] Update `SettingsViewModel` and `SettingsView` to reflect MLX models options, so the user can select an MLX model target

## Dev Notes

- **Architecture:** The project heavily emphasizes Actor-Isolated MVVM. This means the `MLXEngine` logic MUST NOT run on the main UI thread. It should be designated as an `actor` or `globalactor`, isolated from everything else.
- All errors inside the MLX engine should throw strongly typed domain-specific error enums (e.g., `MLXEngineError.failedToLoadModel`) instead of Optionals. Do not return nil on error.
- **Reference:** The `TranscriptionEngine` protocol should be conceptually identical to the already-implemented logic within `WhisperKit` in Phase 1 (CoreML). Analyze Phase 1 for hints on expected audio buffer format.

### Project Structure Notes

- `MLXEngine.swift` must be placed in `Swift-version/Sources/voice-to-text/Engines/Transcription/MLXEngine.swift`
- The `TranscriptionEngine` protocol should be defined in `Swift-version/Sources/voice-to-text/Domain/Protocols.swift` if it doesn't exist yet, or updated to be imported natively across engines.

### References

- Application Architectures and Constraints can be found fully detailed in `_bmad-output/planning-artifacts/architecture.md`.
- Ensure Parakeet GGUF models or MLX-hosted models are used. Apple MLX docs should be referenced for setup: https://github.com/ml-explore/mlx-swift

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
