# Story 3.4: Apple Foundation Models Integration

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an M-series Mac owner,
I want macOS Native GenAI to fix my grammar,
So that I don't have to download multi-gigabyte models myself.

## Acceptance Criteria

1. **Given** the OS is macOS 15.1+
2. **When** the user applies an Apple Intelligence "Grammar Fix" custom prompt via the AppStateManager
3. **Then** the OS natively refines the dictation string before it is handed to `OutputService`

## Tasks / Subtasks

- [x] Task 1: Create the `AppleIntelligenceEngine`
  - [x] Subtask 1.1: Create `AppleIntelligenceEngine.swift` in `Sources/voice-to-text/Engines/PostProcessing/`.
  - [x] Subtask 1.2: Conform `AppleIntelligenceEngine` to the `PostProcessingEngine` protocol.
  - [x] Subtask 1.3: Implement the `refine(text: String, prompt: String) async throws -> String` method, making use of macOS 15.1+ native AI frameworks (e.g., using `LanguageModel` or bridging `UITextView` / `NSTextView` Writing Tools if an explicit framework isn't available). Ensure it fails gracefully on older OS versions.
- [x] Task 2: Integrate `AppleIntelligenceEngine` into `AppStateManager`
  - [x] Subtask 2.1: Update `AppStateManager` to initialize `AppleIntelligenceEngine` as the default `postProcessingEngine` (if running on macOS 15.1+).
  - [x] Subtask 2.2: Ensure the existing 2000ms timeout logic in `AppStateManager` correctly bounds the Apple Intelligence call to meet NFR3 and NFR8 (Graceful Fallback).
- [x] Task 3: Update `SettingsView` UI for Apple Intelligence
  - [x] Subtask 3.1: Add a model selection UI in the Settings (under Post-Processing or Model tab) to let the user select "Apple Intelligence" vs other future downloaded models.
  - [x] Subtask 3.2: Prevent selection or display a warning if the user's OS is below macOS 15.1 or the hardware doesn't support Apple Intelligence.

## Dev Notes

- **Architecture:** `AppleIntelligenceEngine` must strictly conform to `PostProcessingEngine` (Wait, `PostProcessingEngine` is a `Sendable` `protocol`).
- **OS Availability:** Apple Intelligence requires macOS 15.1+. Use `#available(macOS 15.1, *)` checks comprehensively. Throw a specific `Error` if invoked on unsupported systems so the Orchestrator safely falls back to printing the raw string.
- **Concurrency:** Ensure the engine doesn't block the main thread. If utilizing AppKit UI-bound features (like hidden `NSTextView` for WritingTools), you might need to use `@MainActor` internally but expose the async non-blocking interface to the `AppStateManager`.

### Project Structure Notes

- New engine lives in `Sources/voice-to-text/Engines/PostProcessing/AppleIntelligenceEngine.swift`.
- Orchestrator updates live in `Sources/voice-to-text/App/AppStateManager.swift`.
- UI updates live in `Sources/voice-to-text/UI/Settings/`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-3-4-Apple-Foundation-Models-Integration]
- [Source: _bmad-output/planning-artifacts/architecture.md#3-Open-Model-Sandbox-Structure]
- [Source: _bmad-output/project-context.md]

## Dev Agent Record

### Agent Model Used

Gemini 2.5 Pro

### Debug Log References

### Completion Notes List

### File List
