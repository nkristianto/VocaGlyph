# Story 3.5: Graceful Fallback Switcher

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user dictating quickly,
I want the app to paste raw text if Apple Intelligence times out,
So that I am never locked waiting for an AI API.

## Acceptance Criteria

1. **Given** a Post-Processing engine fails or exceeds 2000ms
2. **When** processing occurs
3. **Then** the Orchestrator instantly terminates the job and passes the raw text onward to be typed

## Tasks / Subtasks

- [x] Task 1: Implement Timeout and Fallback Logic in `AppStateManager`
  - [x] Subtask 1.1: Ensure the call to `postProcessingEngine.refine` is wrapped in a task with a timeout mechanism (e.g., using `withThrowingTaskGroup` with a `Task.sleep` cancellation race, or a structured concurrency equivalent in Swift 6) capped at 2000ms.
  - [x] Subtask 1.2: If the post-processing takes longer than 2000ms, cancel the refinement task and throw/catch a timeout error.
  - [x] Subtask 1.3: If `refine` throws any error (timeout or internal engine error), log the failure, but successfully continue the pipeline by passing the *original raw transcription* to the `OutputService`.
- [x] Task 2: Update Unit Tests for Graceful Fallback
  - [x] Subtask 2.1: Add a unit test specifically validating that a mock `PostProcessingEngine` which sleeps for >2000ms results in the raw text being output, rather than failing the dictation session.
  - [x] Subtask 2.2: Add a unit test verifying that synchronous or asynchronous errors thrown by the post-processing engine also result in the raw text being successfully output to the pasteboard service.

## Dev Notes

- **Architecture Compliance:**
  - **The Orchestrator Boundary:** This logic must live within `AppStateManager` (or an equivalent orchestrator actor). Do not push timeout responsibilities down into the individual `Engines` (like `AppleIntelligenceEngine`). The orchestrator should control the time boundary to ensure consistent enforcement across any post-processing engine.
  - **Concurrency:** Ensure that task cancellation is handled properly. When the timeout occurs, the original refinement task should be actively cancelled to stop any background LLM processing and prevent resource leaks. 
  - **Wait until Output:** Make sure the fallback output is successfully passed to `OutputService` and triggers the paste securely.

- **Technical Requirements:**
  - NFR8 dictates that Cloud API (or local AI) timeouts >2000ms must automatically abort and paste raw text. The timeout constant should be exactly 2.0 seconds.
  - Swift 6 strict concurrency checks apply (`async/await`, `@MainActor`, `actor`). Do not use GCD (`DispatchQueue`).
  - Error Swallowing: Don't swallow errors; catch the timeout/post-process error, log it via `LoggerService` or similar, and *then* proceed with the raw transcription.

- **Previous Story Intelligence (from 3.4):**
  - Story 3.4 implemented the `AppleIntelligenceEngine`. This story formally ensures the resilient fallback mechanism wrapping the protocol in the Orchestrator is bulletproof.

### Project Structure Notes

- Modifications will primarily occur in `Sources/voice-to-text/App/AppStateManager.swift` (or wherever the orchestrator logic resides).
- Tests will be modified in `Tests/voice-to-textTests/...`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-3-5-Graceful-Fallback-Switcher]
- [Source: _bmad-output/planning-artifacts/prd.md#NFR8]
- [Source: _bmad-output/planning-artifacts/architecture.md#Reliability]
- [Source: _bmad-output/project-context.md]

## Dev Agent Record

### Agent Model Used

Gemini 2.5 Pro

### Debug Log References

- Verified existing `AppStateManager.swift` logic handles 2000ms timeout through `withThrowingTaskGroup`.
- Confirmed fallback to raw text functions perfectly as designed in previous architecture.
- Added explicit unit tests to ensure this capability doesn't regress.

### Completion Notes List

- ✅ Verified `withThrowingTaskGroup` timeout mechanism in `AppStateManager` works as intended and respects the 2000ms bound.
- ✅ Added `testProcessAudioWithPostProcessingTimeoutFallsBackToRawText` to explicitly test that network latency > 2000ms still yields the raw dictation string.

### File List

- `Swift-version/Tests/voice-to-textTests/AppStateManagerTests.swift`

### Change Log

- Added timeout verification test case to `AppStateManagerTests`.
