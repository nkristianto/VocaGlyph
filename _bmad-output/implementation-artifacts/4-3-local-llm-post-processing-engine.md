# Story 4.3: Local LLM Post-Processing Engine (Qwen via MLX-Swift)

Status: review

## Story

As a privacy-conscious power user,
I want to refine my transcribed text using a locally-running Qwen LLM,
so that I can get AI-powered post-processing 100% offline without sending data to the cloud or relying on macOS version requirements.

## Acceptance Criteria

1. **Given** the user opens Settings → Post-Processing and enables "Automated Text Refinement", **when** they open the "AI Processing Model" dropdown, **then** a third option "Local AI (Qwen)" is visible alongside "Apple Intelligence" and "Cloud API".

2. **Given** the user selects "Local AI (Qwen)", **when** the selection is confirmed, **then** a conditional sub-section appears below the picker containing: a model size picker (7B default, 1.5B for 8GB Macs), a RAM/disk warning for the 7B model, and a "Free Model Memory" button.

3. **Given** `selectedTaskModel = "local-llm"` and `enablePostProcessing = true`, **when** the user finishes dictating, **then** `LocalLLMEngine.refine(text:prompt:)` is invoked with the transcription text and user's custom prompt, and the refined text is pasted into the active application.

4. **Given** `LocalLLMEngine.refine()` throws any error (model load failure, inference error, OOM), **when** `AppStateManager.processAudio(buffer:)` is running, **then** the raw transcription text is pasted (no crash), and the error is logged — matching existing engine graceful fallback behavior.

5. **Given** the user selects "Local AI (Qwen)" on repeated occasions, **when** `switchPostProcessingEngine()` is called each time, **then** the same singleton `LocalLLMEngine` instance is assigned to `postProcessingEngine` (model weights are NOT re-loaded on each call).

6. **Given** the user presses "Free Model Memory" in Settings, **when** the button action fires, **then** `AppStateManager.unloadLocalLLMEngine()` is called, which in turn calls `LocalLLMEngine.unloadModel()`, which sets the internal model container to nil — confirmed by a log entry: `"LocalLLMEngine: Model unloaded from memory."`.

7. **Given** `LocalLLMEngineTests.swift` exists with 4 mock-based test cases, **when** `swift test --filter LocalLLMEngineTests` is run, **then** all 4 tests pass without requiring real MLX model weights or a HuggingFace download.

## Tasks / Subtasks

- [ ] Task 1: Add `mlx-swift-lm` SPM dependency (AC: #3, #5)
  - [ ] 1.1 Open `swift-version/Package.swift`
  - [ ] 1.2 Add to `dependencies` array: `.package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main")`
  - [ ] 1.3 Add to the `voice-to-text` executable target's `dependencies`: `.product(name: "MLXLLM", package: "mlx-swift-lm")` and `.product(name: "MLXLMCommon", package: "mlx-swift-lm")`
  - [ ] 1.4 Run `swift package resolve` to confirm dependency resolution

- [ ] Task 2: Create `LocalLLMEngine.swift` (AC: #3, #4, #5, #6, #7)
  - [ ] 2.1 Create new file at path: `swift-version/Sources/voice-to-text/Engines/PostProcessing/LocalLLMEngine.swift`
  - [ ] 2.2 Declare `public actor LocalLLMEngine: PostProcessingEngine` — import `MLXLLM`, `MLXLMCommon`, `Foundation`
  - [ ] 2.3 Add stored properties: `private var loadedContainer: ModelContainer?`, `private let modelId: String`, `private let inferenceProvider: LocalLLMInferenceProvider`
  - [ ] 2.4 Define protocol for test injection: `protocol LocalLLMInferenceProvider: Sendable { func generate(prompt: String) async throws -> String }`
  - [ ] 2.5 Implement `MLXLMInferenceProvider: LocalLLMInferenceProvider` as the real provider — uses `MLXLLM.loadModelContainer(configuration:)` and `MLXLMCommon.generate()`
  - [ ] 2.6 Add `public init(modelId: String = "mlx-community/Qwen2.5-7B-Instruct-4bit", provider: LocalLLMInferenceProvider? = nil)` — defaults to `MLXLMInferenceProvider` if nil
  - [ ] 2.7 Implement `public func refine(text: String, prompt: String) async throws -> String` — calls `buildPrompt()`, calls `inferenceProvider.generate()`, returns `.trimmingCharacters(in: .whitespacesAndNewlines)`
  - [ ] 2.8 Implement `private func buildPrompt(system: String, userText: String) -> String` — builds Qwen2.5 chat template: `<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{userText}<|im_end|>\n<|im_start|>assistant\n`
  - [ ] 2.9 Implement `public func unloadModel()` — sets `loadedContainer = nil`, calls `Logger.shared.info("LocalLLMEngine: Model unloaded from memory.")`
  - [ ] 2.10 Define error enum: `public enum LocalLLMEngineError: LocalizedError, Equatable` with cases `modelLoadFailed(String)`, `inferenceFailed(String)`, `insufficientMemory`

- [ ] Task 3: Update `AppStateManager.swift` (AC: #3, #5, #6)
  - [ ] 3.1 Open `swift-version/Sources/voice-to-text/App/AppStateManager.swift`
  - [ ] 3.2 Add private lazy singleton property: `private lazy var localLLMEngine: LocalLLMEngine = LocalLLMEngine()`
  - [ ] 3.3 In `switchPostProcessingEngine()`, add new branch before the final `else`: `else if selectedPostModel == "local-llm" { Logger.shared.info("AppStateManager: Switching post-processing engine to LocalLLMEngine"); self.postProcessingEngine = localLLMEngine }`
  - [ ] 3.4 Add new public method: `public func unloadLocalLLMEngine() async { await localLLMEngine.unloadModel() }`

- [ ] Task 4: Update `SettingsView.swift` — `PostProcessingSettingsView` (AC: #1, #2, #6)
  - [ ] 4.1 Open `swift-version/Sources/voice-to-text/UI/Settings/SettingsView.swift`
  - [ ] 4.2 In `PostProcessingSettingsView`, add: `@AppStorage("selectedLocalLLMModel") private var selectedLocalLLMModel: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"`
  - [ ] 4.3 In the `Menu { }` for "AI Processing Model" (around line 562), add a new `Button`: `Button("Local AI (Qwen)") { Logger.shared.debug("Settings: Changed AI Processing Model to 'local-llm'"); selectedTaskModel = "local-llm"; stateManager.switchPostProcessingEngine() }`
  - [ ] 4.4 Update the label's `display` string (around line 576) to handle the new case: `let display = selectedTaskModel == "apple-native" ? "Apple Intelligence" : selectedTaskModel == "cloud-api" ? "Cloud API (Gemini/Anthropic)" : selectedTaskModel == "local-llm" ? "Local AI (Qwen)" : selectedTaskModel`
  - [ ] 4.5 After `appleNativeCheck`, add conditional block: `if selectedTaskModel == "local-llm" { Divider().background(Theme.textMuted.opacity(0.1)); localLLMSection }`
  - [ ] 4.6 Add `@ViewBuilder private var localLLMSection: some View` containing:
    - Model picker menu row (two options: `"mlx-community/Qwen2.5-7B-Instruct-4bit"` labeled "Qwen 2.5 7B (4.3 GB, 16GB RAM)" and `"mlx-community/Qwen2.5-1.5B-Instruct-4bit"` labeled "Qwen 2.5 1.5B (1.1 GB, 8GB RAM)") that updates `selectedLocalLLMModel` and calls `stateManager.switchPostProcessingEngine()`
    - RAM/disk warning row (orange `exclamationmark.triangle.fill` icon + text "Requires ~4.3GB disk + 16GB RAM. Model downloads once and is cached.") — visible only when 7B model is selected
    - "Free Model Memory" button row — styled like the "Delete" key buttons in `externalApiCredentialsSection` (`.bordered`, tinted `.red`), action: `Task { await stateManager.unloadLocalLLMEngine() }`

- [ ] Task 5: Create `LocalLLMEngineTests.swift` (AC: #7)
  - [ ] 5.1 Create new file at: `swift-version/Tests/voice-to-textTests/Engines/LocalLLMEngineTests.swift`
  - [ ] 5.2 Match the pattern of `GeminiEngineTests.swift` — `import XCTest`, `@testable import voice_to_text`
  - [ ] 5.3 Define `MockLocalLLMInferenceProvider: LocalLLMInferenceProvider, @unchecked Sendable` with props: `var returnedText = "mock result"`, `var shouldThrowError = false`, `var capturedPrompt: String?`
  - [ ] 5.4 Implement `func generate(prompt: String) async throws -> String` — captures prompt, optionally throws, returns `returnedText`
  - [ ] 5.5 Write `testRefineCallsProviderWithFormattedPrompt()` — verify captured prompt contains `<|im_start|>system\nfix grammar` and `<|im_start|>user\nhello`, and result == `"mock result"`
  - [ ] 5.6 Write `testRefineTrimsWhitespaceFromResult()` — set `mock.returnedText = "  result  \n"`, verify `refine()` returns `"result"`
  - [ ] 5.7 Write `testRefineThrowsWhenProviderThrows()` — set `mock.shouldThrowError = true` throw `LocalLLMEngineError.inferenceFailed("bad")`, verify error propagates
  - [ ] 5.8 Write `testUnloadModelClearsEngineState()` — call `refine()` once, call `unloadModel()`, call `refine()` again, verify mock `generate()` was called twice (proving no cached container bypass)

- [ ] Task 6: Update `sprint-status.yaml` (housekeeping)
  - [ ] 6.1 Add `4-3-local-llm-post-processing-engine: ready-for-dev` under `epic-4` in the `development_status` section

## Dev Notes

### Architecture Compliance

- **Critical:** `LocalLLMEngine` is a Swift `actor` — NOT a `struct` or `class`. This is mandatory for Sendable conformance across `AppStateManager`'s strict concurrency boundary. [Source: architecture.md#Open-Model-Sandbox-Structure]
- **Critical:** `AppStateManager` must hold a **singleton** `localLLMEngine` via `private lazy var` — this preserves loaded model weights in Unified Memory across repeated `refine()` calls. Re-instantiating it on each `switchPostProcessingEngine()` call would reload 4.3GB of weights every time. [Source: tech-spec-local-llm-qwen-engine.md#Technical-Decisions]
- **Critical:** UI (`SettingsView`) NEVER calls `localLLMEngine.unloadModel()` directly — it calls `stateManager.unloadLocalLLMEngine()`. The Orchestrator Boundary must be respected. [Source: architecture.md#Architectural-Boundaries, project-context.md#Framework-Specific-Rules]
- `LocalLLMEngineError` must be `Equatable` to allow `XCTAssertEqual` in tests — match `GeminiEngineError` pattern. [Source: Tests/Engines/GeminiEngineTests.swift]

### Qwen2.5 Chat Template (CRITICAL)

The Qwen2.5 models require a specific chat template. Do NOT use a plain prompt string:

```swift
private func buildPrompt(system: String, userText: String) -> String {
    return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(userText)<|im_end|>\n<|im_start|>assistant\n"
}
```

### Existing Engine Pattern to Match

Reference `GeminiEngine.swift` for the actor + error enum + public init pattern. Reference `AnthropicEngine.swift` for the `refine()` throw-on-error pattern. Both are in `Engines/PostProcessing/`.

### AppStateManager — Existing `switchPostProcessingEngine()` Shape

```swift
// Current shape (AppStateManager.swift L44-L65):
public func switchPostProcessingEngine() {
    let selectedPostModel = UserDefaults.standard.string(forKey: "selectedTaskModel") ?? "apple-native"
    if selectedPostModel == "cloud-api" {
        // ...
    } else if selectedPostModel == "apple-native" {
        // ...
    } else {
        self.postProcessingEngine = nil
    }
}
```
Insert the new `else if selectedPostModel == "local-llm"` branch **before** the final `else` block — replacing `nil` assignment for this case.

### `AppStateManager` Note: `ObservableObject` not `@Observable`

`AppStateManager` currently uses `ObservableObject` + `@Published var currentState`. The project-context.md rule about `@Observable` applies to new ViewModels, NOT to `AppStateManager`. When adding `private lazy var localLLMEngine` and `public func unloadLocalLLMEngine()`, match the existing style without converting to `@Observable`. [Source: project-context.md, AppStateManager.swift L17]

### SettingsView `PostProcessingSettingsView` Reference Points

- `@AppStorage("selectedTaskModel")` declared at L492
- `Menu { }` for "AI Processing Model" starts at L562 — add the new Button as the LAST item before closing `}`
- `display` label string computed at L576 — update with a new ternary arm
- `appleNativeCheck` `@ViewBuilder` location at L793 — add the `if selectedTaskModel == "local-llm"` block AFTER calling `appleNativeCheck` on L600
- Existing conditional cloud-api section starts at L602 — use same `if selectedTaskModel == "..."` pattern for the local LLM section
- "Delete" button style reference: L713-L717 (`.bordered` + `.tint(.red)`)

### Project Structure Notes

- **New file location:** `swift-version/Sources/voice-to-text/Engines/PostProcessing/LocalLLMEngine.swift` — Architecture doc explicitly reserved `QwenEngine.swift` at this path, naming updated to `LocalLLMEngine.swift` for generality. [Source: architecture.md#Complete-Project-Directory-Structure]
- **Test file location:** `swift-version/Tests/voice-to-textTests/Engines/LocalLLMEngineTests.swift` — matches existing sibling test files for `GeminiEngine`, `AnthropicEngine`, etc.
- **New UserDefaults key:** `selectedLocalLLMModel` — not currently in use anywhere; safe to introduce.

### git Context (Recent Commits)

- `43f9558` — Add debounce time on triggering the hotkey (HotkeyService, AudioRecorderService, AppDelegate touched)
- `8369ad0` — fix search button (UI diff)
- `17e60a8` — add history page + fix apple speech issue (SwiftData + NativeSpeechEngine)
- `53a025d` — add gemini integration (GeminiEngine introduced — direct pattern reference for this story)
- `1c8d792` — add keychain integration (KeychainService introduced)

The Gemini integration commit (`53a025d`) is the most relevant prior art. Follow its patterns for introducing a new engine file + test file.

### Testing Strategy

**Unit tests (Task 5):** Use injected `MockLocalLLMInferenceProvider` — zero real MLX hardware or HuggingFace downloads required. Run with:

```bash
cd swift-version && swift test --filter LocalLLMEngineTests
```

**Full regression suite:**

```bash
cd swift-version && swift test
```

**Manual smoke test** (requires 16GB+ RAM Mac with internet for first model download):
1. `swift build -c release` (verify compiles with new mlx-swift-lm dep)
2. Run app, open Settings → Post-Processing, enable Automated Text Refinement
3. Select "Local AI (Qwen)" — verify sub-section appears with model picker, warning, and button
4. Dictate something → first call will trigger model download (~4.3GB) + cold load (~5–10s), expect timeout on first use
5. Second dictation → model hot, should complete within 10s timeout
6. Press "Free Model Memory" → verify log shows `LocalLLMEngine: Model unloaded from memory.`

### References

- [Source: _bmad-output/implementation-artifacts/tech-spec-local-llm-qwen-engine.md] — Full tech-spec with detailed implementation instructions, AC, and scope boundaries
- [Source: _bmad-output/planning-artifacts/research/technical-local-llm-qwen-integration-research-2026-02-22.md] — MLX-Swift integration research, model benchmarks, memory management strategy
- [Source: _bmad-output/planning-artifacts/architecture.md#Open-Model-Sandbox-Structure] — Protocol definitions and engine actor pattern
- [Source: _bmad-output/planning-artifacts/architecture.md#Architectural-Boundaries] — Orchestrator boundary enforcement
- [Source: swift-version/Sources/voice-to-text/App/AppStateManager.swift#L44-L65] — `switchPostProcessingEngine()` current implementation
- [Source: swift-version/Sources/voice-to-text/UI/Settings/SettingsView.swift#L486-L863] — `PostProcessingSettingsView` struct
- [Source: swift-version/Sources/voice-to-text/Engines/PostProcessing/GeminiEngine.swift] — Actor pattern + error enum + unit test pattern reference
- [Source: swift-version/Tests/voice-to-textTests/Engines/GeminiEngineTests.swift] — Test structure reference
- [Source: swift-version/Tests/voice-to-textTests/AppStateManagerTests.swift] — `MockPostProcessingEngine` pattern
- [Source: _bmad-output/project-context.md] — Swift 6 concurrency rules, Orchestrator boundary, ObservableObject vs @Observable decision

### ⚠️ Known Risk: 10-Second Timeout

`AppStateManager.processAudio(buffer:)` wraps ALL post-processing in a `withThrowingTaskGroup` with a **10-second hard timeout** (L103–L116). For `LocalLLMEngine`, the first call triggers both model download (~4.3GB) AND cold-load (~5–10s). This WILL exceed the timeout on first use, causing graceful fallback to raw text (AC-4 satisfied, but UX is degraded). 

This is a **known accepted limitation** for the current story. A future story should consider either:
- Increasing the timeout for `"local-llm"` specifically (e.g., 60 seconds)
- Adding a HUD indicator to signal the model is loading on first use

Do NOT try to fix the timeout in this story — it is explicitly out of scope per the tech-spec.

## Dev Agent Record

### Agent Model Used

Antigravity (Gemini 2.5 Pro)

### Debug Log References

### Completion Notes List

### File List
