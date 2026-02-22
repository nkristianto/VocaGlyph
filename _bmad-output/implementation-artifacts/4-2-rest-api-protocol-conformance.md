# Story 4.2: rest-api-protocol-conformance

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an advanced user,
I want Gemini to translate my dictation to Japanese,
so that I can seamlessly write across international lines.

## Acceptance Criteria

1. **Given** the Post-Processing Engine is set to Cloud API (Gemini or Anthropic)
   **When** the user speaks English
   **Then** the Audio is transcribed offline locally
   **And** sent via secure REST to the configured Cloud API with the custom prompt
   **And** the translated result is typed automatically.
2. **Given** a Cloud API takes longer than 2000ms to respond or fails
   **When** processing occurs
   **Then** the system must automatically abort the network request and instantly paste the raw transcribed text instead, preventing UX lockup. (Graceful Degradation NFR8)
3. **Given** the Orchestrator needs the API Key
   **When** initiating the Cloud API request
   **Then** the key is securely retrieved from `KeychainService` in memory, never exposing it to plaintext logs.

## Tasks / Subtasks

- [x] Task 1: Create `CloudEngine` adhering to `PostProcessingEngine`
  - [x] Implement `GeminiEngine` (or a generic `CloudEngine`) class that conforms to the `PostProcessingEngine` protocol (`async throws -> String`).
  - [x] Use `URLSession.shared.data(for: request)` with Swift Concurrency to hit the generative AI REST endpoint.
  - [x] Inject `KeychainService` so the engine can retrieve the user's saved API key securely in memory before making the request.
- [x] Task 2: Implement 2000ms Timeout & Graceful Degradation
  - [x] Wrap the `URLSession` network call in an async timeout Task (e.g. `withThrowingTaskGroup` or iOS/macOS 14+ `Task.sleep` racing).
  - [x] If the task exceeds 2.0 seconds, throw a specific `EngineError.timeout` error.
  - [x] Ensure the central `AppStateManager` (Orchestrator) catches this error and cleanly falls back to emitting the raw text via `OutputService`.
- [x] Task 3: UI Settings Integration (If not fully present)
  - [x] Ensure `SettingsView` allows selecting "Cloud API (Gemini/Anthropic)" as the `selectedTaskModel`.
  - [x] Hook the new `CloudEngine` into the Orchestrator routing logic.

## Dev Notes

- **Architecture Rules:** Follow the Actor-Isolated MVVM pattern and strict Open Model Sandbox abstraction. The orchestrator must not care whether it's talking to `AppleIntelligenceEngine` or `CloudEngine`. Both simply implement `func refine(text: String, prompt: String) async throws -> String` on a `Sendable` protocol.
- **Concurrency & Networking:** Do NOT use callbacks. Use raw `URLSession` `async`/`await` methods. Do not import heavyweight third-party AI SDKs—a simple `Codable` struct for the REST JSON body is preferred to keep the app lightweight and secure.
- **Security:** Do not log the API Key or the raw audio buffers. Use the `KeychainService` built previously in Story 4.1.

### Project Structure Notes

- Place the new engine in `Swift-version/Sources/voice-to-text/Engines/PostProcessing/`.
- Maintain strict main-thread isolation relative to the rest of the application. Network wait times must never block the `AppKit`/`SwiftUI` `@MainActor`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic-4]
- [Source: _bmad-output/planning-artifacts/prd.md#Non-Functional-Requirements] (NFR8: Graceful Degradation)
- [Source: _bmad-output/project-context.md#Framework-Specific-Rules]

## Dev Agent Record

### Agent Model Used

gemini-2.5-pro

### Debug Log References

- MockURLProtocol was used to bypass network dependency during tests.
- SwiftUI ViewBuilder compilation issue fixed in `SettingsView.swift` by simplifying a trailing conditional string assignment.

### Completion Notes List

- Implemented `GeminiEngine` adhering to `PostProcessingEngine`.
- Hooked `GeminiEngine` up to `AppStateManager.switchPostProcessingEngine()`.
- Added UI state updates to `SettingsView` to allow selection of Cloud API.
- Verified timeout handling using the existing `withThrowingTaskGroup` + `Task.sleep` fallback logic in `AppStateManager`.
- Wrote full unit test coverage using `MockURLProtocol`.

### File List

- `Swift-version/Sources/voice-to-text/Engines/PostProcessing/GeminiEngine.swift` (New)
- `Swift-version/Sources/voice-to-text/UI/Settings/SettingsView.swift` (Modified)
- `Swift-version/Sources/voice-to-text/App/AppStateManager.swift` (Modified)
- `Swift-version/Tests/voice-to-textTests/Engines/GeminiEngineTests.swift` (New)
