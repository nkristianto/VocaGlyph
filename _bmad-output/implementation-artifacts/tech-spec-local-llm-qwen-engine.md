---
title: 'Add Local LLM Post-Processing Engine (Qwen via MLX-Swift)'
slug: 'local-llm-qwen-engine'
created: '2026-02-22T18:26:00+07:00'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack:
  - 'Swift 6.0'
  - 'macOS 14+ target'
  - 'mlx-swift-lm (MLXLLM + MLXLMCommon) — NEW dependency'
  - 'XCTest for unit tests'
files_to_modify:
  - 'swift-version/Package.swift'
  - 'swift-version/Sources/voice-to-text/Engines/PostProcessing/LocalLLMEngine.swift [NEW]'
  - 'swift-version/Sources/voice-to-text/App/AppStateManager.swift'
  - 'swift-version/Sources/voice-to-text/UI/Settings/SettingsView.swift'
  - 'swift-version/Tests/voice-to-textTests/Engines/LocalLLMEngineTests.swift [NEW]'
code_patterns:
  - 'All engines are Swift `actor` types conforming to `protocol PostProcessingEngine: Sendable`'
  - '`refine(text:prompt:) async throws -> String` is the single protocol requirement'
  - 'AppStateManager.switchPostProcessingEngine() reads `selectedTaskModel` UserDefaults key'
  - 'Known string values for selectedTaskModel: "apple-native", "cloud-api" → add "local-llm"'
  - 'SettingsView uses @AppStorage("selectedTaskModel") + calls switchPostProcessingEngine() on change'
  - 'PostProcessingSettingsView has a Menu{} dropdown for engine selection — extend it'
  - 'conditional sub-sections shown via `if selectedTaskModel == "cloud-api" { ... }` pattern'
test_patterns:
  - 'XCTest, @testable import voice_to_text'
  - 'Each engine has dedicated test file under Tests/voice-to-textTests/Engines/'
  - 'Error enums are `Equatable` to enable XCTAssertEqual on thrown errors'
  - 'LocalLLMEngine will need mocking: inject a protocol-based MLX dependency for unit tests'
---

# Tech-Spec: Add Local LLM Post-Processing Engine (Qwen via MLX-Swift)

**Created:** 2026-02-22T18:26:00+07:00

---

## Overview

### Problem Statement

VocaGlyph currently has two post-processing paths: **Apple Intelligence** (non-functional: public API unavailable) and **Cloud API / "FBI"** (Gemini/Anthropic — requires internet + API keys). Users with privacy requirements or unreliable internet have no working local post-processing option. A third, fully offline, always-available path is needed.

### Solution

Add `LocalLLMEngine` — a new `actor` conforming to `PostProcessingEngine` — powered by `mlx-swift-lm` (`MLXLLM` + `MLXLMCommon` targets). It downloads and caches `mlx-community/Qwen2.5-7B-Instruct-4bit` (~4.3 GB) on first use from Hugging Face, then runs inference 100% on-device via Apple Silicon's Unified Memory Architecture. The engine is held as a singleton in `AppStateManager` (to avoid repeated model loading), lazy-loads its weights on first call, and exposes an `unloadModel()` method for memory eviction. Settings UI adds a **"Local AI (Qwen)"** option to the existing engine picker, with a model size picker and download status indicator.

### Scope

**In Scope:**
- `LocalLLMEngine.swift` — new `actor` conforming to `PostProcessingEngine`
- `Package.swift` — add `mlx-swift-lm` dependency
- `AppStateManager.swift` — singleton instance, new `"local-llm"` routing case
- `SettingsView.swift` — new "Local AI (Qwen)" menu item + conditional sub-section (model picker, download status, memory usage warning, unload button)
- `LocalLLMEngineTests.swift` — XCTest unit tests

**Out of Scope:**
- Pre-bundling model weights in the app binary
- Streaming token display in the UI (output returned as complete string, matching existing engine API)
- Automatic model eviction timer (unload is manual via Settings button for now)
- Custom model path from disk (always downloads from HuggingFace mlx-community)

---

## Context for Development

### Codebase Patterns

**Critical rules from `project-context.md`:**
- Use `@Observable` macro for ViewModels. **Exception:** `SettingsViewModel` still uses `ObservableObject`/`@Published` — match its existing pattern.
- All inference MUST run in a Swift `actor`, never on `@MainActor`.
- Error types MUST be strongly-typed enums conforming to `LocalizedError`.
- Never swallow errors silently — always throw typed errors for the Orchestrator to handle.
- UI (`UI/`) never touches `Engines/` directly — always goes through `AppStateManager`.

**`PostProcessingEngine` protocol** (no changes needed):
```swift
// Domain/Protocols.swift
public protocol PostProcessingEngine: Sendable {
    func refine(text: String, prompt: String) async throws -> String
}
```

**Existing engine pattern** (all engines are `actor` types):
```swift
public actor GeminiEngine: PostProcessingEngine {
    public func refine(text: String, prompt: String) async throws -> String { ... }
}
```

**`AppStateManager.switchPostProcessingEngine()`** currently reads:
- `UserDefaults.standard.string(forKey: "selectedTaskModel")` → `"apple-native"` | `"cloud-api"`
- `UserDefaults.standard.string(forKey: "selectedCloudProvider")` → `"gemini"` | `"anthropic"`

New case to add: `"local-llm"` → assign the singleton `LocalLLMEngine` instance.

**Key AppStateManager constraint:** `LocalLLMEngine` MUST be a **singleton** held on the `AppStateManager` instance (declared as `var localLLMEngine: LocalLLMEngine?`), because the model weights must persist in memory across calls. All other engines can be re-instantiated freely.

**`AppStateManager.processAudio(buffer:)`** already handles post-processing with a 10-second timeout via `withThrowingTaskGroup`. `LocalLLMEngine.refine()` just needs to complete within that window for normal short texts.

**SettingsView post-processing section** (`PostProcessingSettingsView` struct):
- Uses `@AppStorage("selectedTaskModel")` and `@AppStorage("selectedCloudProvider")`
- Menu button calls `stateManager.switchPostProcessingEngine()` on selection
- Conditional sub-sections use `if selectedTaskModel == "cloud-api" { ... }` pattern
- New section: `if selectedTaskModel == "local-llm" { ... }` for model picker + download status

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `Domain/Protocols.swift` | `PostProcessingEngine` protocol definition |
| `Engines/PostProcessing/GeminiEngine.swift` | Reference implementation + error enum pattern |
| `Engines/PostProcessing/AnthropicEngine.swift` | Reference implementation |
| `App/AppStateManager.swift` | `switchPostProcessingEngine()` routing switch |
| `UI/Settings/SettingsView.swift` (L486–863) | `PostProcessingSettingsView` — add Local LLM option |
| `UI/Settings/SettingsViewModel.swift` | Existing ViewModel pattern (Keychain keys only) |
| `Tests/voice-to-textTests/Engines/GeminiEngineTests.swift` | Test pattern reference |
| `Tests/voice-to-textTests/AppStateManagerTests.swift` | `MockPostProcessingEngine` class |
| `_bmad-output/planning-artifacts/research/technical-local-llm-qwen-integration-research-2026-02-22.md` | Full architecture research |

### Technical Decisions

1. **Framework:** `mlx-swift-lm` (`MLXLLM` + `MLXLMCommon`) via SPM — Apple-native, UMA-optimized, best Swift API surface.
2. **Default model:** `mlx-community/Qwen2.5-7B-Instruct-4bit` (~4.3 GB, requires 16GB RAM). Selectable smaller option: `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (~1.1 GB, 8GB RAM).
3. **Singleton design:** `AppStateManager` holds one persistent `LocalLLMEngine` instance; `switchPostProcessingEngine()` assigns it (not re-created each time).
4. **Qwen2.5 chat template:** Use `<|im_start|>` / `<|im_end|>` format for system+user prompt construction.
5. **`unloadModel()` method:** Public method on `LocalLLMEngine` that nils out the loaded model container, freeing memory.
6. **New UserDefaults keys introduced:** `selectedLocalLLMModel` (`String`, default: `"mlx-community/Qwen2.5-7B-Instruct-4bit"`).

---

## Implementation Plan

### Tasks

**Task 1: Add `mlx-swift-lm` SPM dependency**
- **File:** `swift-version/Package.swift`
- **Action:** Add to `dependencies` array:
  ```swift
  .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main")
  ```
- **Action:** Add to the `voice-to-text` executable target's `dependencies`:
  ```swift
  .product(name: "MLXLLM", package: "mlx-swift-lm"),
  .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
  ```

---

**Task 2: Create `LocalLLMEngine.swift`**
- **File:** `swift-version/Sources/voice-to-text/Engines/PostProcessing/LocalLLMEngine.swift` [NEW]
- **Action:** Create `public actor LocalLLMEngine: PostProcessingEngine` with:
  - `import MLXLLM`, `import MLXLMCommon`
  - Private stored property: `var loadedContainer: ModelContainer?`
  - `public init(modelId: String = "mlx-community/Qwen2.5-7B-Instruct-4bit")`
  - `public func refine(text: String, prompt: String) async throws -> String` — calls `ensureModelLoaded()`, builds Qwen2.5 chat template, calls `MLXLMCommon.generate()`, returns trimmed string
  - `public func unloadModel()` — sets `loadedContainer = nil`, logs eviction
  - `private func ensureModelLoaded() async throws -> ModelContainer` — lazy load via `loadModelContainer(configuration:)`
  - `private func buildPrompt(system: String, userText: String) -> String` — Qwen2.5 chat template (`<|im_start|>system\n...<|im_end|>\n<|im_start|>user\n...<|im_end|>\n<|im_start|>assistant\n`)
- **Error enum:** `public enum LocalLLMEngineError: LocalizedError, Equatable` with cases:
  - `modelLoadFailed(String)`
  - `inferenceFailed(String)`
  - `insufficientMemory`

---

**Task 3: Update `AppStateManager.swift`**
- **File:** `swift-version/Sources/voice-to-text/App/AppStateManager.swift`
- **Action 3a:** Add singleton property to `AppStateManager`:
  ```swift
  private lazy var localLLMEngine: LocalLLMEngine = LocalLLMEngine()
  ```
- **Action 3b:** In `switchPostProcessingEngine()`, add new `else if` branch before the final `else`:
  ```swift
  } else if selectedPostModel == "local-llm" {
      Logger.shared.info("AppStateManager: Switching post-processing engine to LocalLLMEngine")
      self.postProcessingEngine = localLLMEngine
  }
  ```
- **Action 3c:** Add `public func unloadLocalLLMEngine()` helper that calls `await localLLMEngine.unloadModel()` — to be invoked from Settings UI when the user presses "Free Memory".

---

**Task 4: Update `SettingsView.swift` — `PostProcessingSettingsView`**
- **File:** `swift-version/Sources/voice-to-text/UI/Settings/SettingsView.swift`
- **Action 4a:** Add new `@AppStorage` var to `PostProcessingSettingsView`:
  ```swift
  @AppStorage("selectedLocalLLMModel") private var selectedLocalLLMModel: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"
  ```
- **Action 4b:** In the `Menu { }` for "AI Processing Model" (around line 562), add a new `Button`:
  ```swift
  Button("Local AI (Qwen)") {
      Logger.shared.debug("Settings: Changed AI Processing Model to 'local-llm'")
      selectedTaskModel = "local-llm"
      stateManager.switchPostProcessingEngine()
  }
  ```
- **Action 4c:** Update the label's `display` string computation (around line 576) to handle the new case:
  ```swift
  let display = selectedTaskModel == "apple-native" ? "Apple Intelligence"
      : selectedTaskModel == "cloud-api" ? "Cloud API (Gemini/Anthropic)"
      : selectedTaskModel == "local-llm" ? "Local AI (Qwen)"
      : selectedTaskModel
  ```
- **Action 4d:** Add a new `@ViewBuilder private var localLLMSection: some View` block and call it conditionally after `appleNativeCheck`:
  ```swift
  if selectedTaskModel == "local-llm" {
      Divider().background(Theme.textMuted.opacity(0.1))
      localLLMSection
  }
  ```
- **Contents of `localLLMSection`:**
  - **Model picker row:** Menu with two options — `"mlx-community/Qwen2.5-7B-Instruct-4bit"` (label: "Qwen 2.5 7B (4.3 GB, 16GB RAM)") and `"mlx-community/Qwen2.5-1.5B-Instruct-4bit"` (label: "Qwen 2.5 1.5B (1.1 GB, 8GB RAM)") — bound to `$selectedLocalLLMModel` and calls `stateManager.switchPostProcessingEngine()` on change.
  - **RAM warning row:** `HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text("Requires ~4.3GB disk + 16GB RAM. Model downloads once and is cached.") }` (show only when 7B selected)
  - **Unload button row:** `Button("Free Model Memory") { Task { await stateManager.unloadLocalLLMEngine() } }` — styled like the "Delete" button in `externalApiCredentialsSection`, tinted `.red`

---

**Task 5: Create `LocalLLMEngineTests.swift`**
- **File:** `swift-version/Tests/voice-to-textTests/Engines/LocalLLMEngineTests.swift` [NEW]
- **Pattern:** Match `GeminiEngineTests.swift` (XCTest class, `@testable import voice_to_text`)
- **Testing approach:** Since MLX model loading requires real hardware + downloaded models (unsuitable for unit tests), inject a protocol-based seam. Define a `LocalLLMInferenceProvider` protocol with a single method `generate(prompt: String) async throws -> String`. `LocalLLMEngine` takes an optional injected provider; tests inject a `MockLocalLLMInferenceProvider`.
- **Test cases:**
  1. `testRefineCallsProviderWithFormattedPrompt()` — Given a mock provider that returns "ok", when `refine(text: "hello", prompt: "fix grammar")` is called, then the provider receives a prompt containing `<|im_start|>system\nfix grammar` and `<|im_start|>user\nhello`, and the engine returns "ok".
  2. `testRefineTrimsWhitespaceFromResult()` — Given provider returns `"  result  \n"`, then `refine()` returns `"result"`.
  3. `testRefineThrowsWhenProviderThrows()` — Given provider throws `LocalLLMEngineError.inferenceFailed("bad")`, then `refine()` propagates the error.
  4. `testUnloadModelClearsState()` — Call `unloadModel()` then verify a subsequent `refine()` call re-loads (mock provider is called again, not a cached container).

---

### Acceptance Criteria

**AC-1: Engine Routing**
- **Given** the user selects "Local AI (Qwen)" in Settings
- **When** `AppStateManager.switchPostProcessingEngine()` is called
- **Then** `AppStateManager.postProcessingEngine` is the singleton `LocalLLMEngine` instance (same object reference on repeated calls)

**AC-2: Post-Processing with Local LLM**
- **Given** `enablePostProcessing = true` and `selectedTaskModel = "local-llm"` in UserDefaults
- **When** audio is recorded and transcribed
- **Then** `LocalLLMEngine.refine(text:prompt:)` is called with the raw transcription text and the user's custom prompt, and the refined text is pasted to the active app

**AC-3: Graceful Fallback on Error**
- **Given** `LocalLLMEngine.refine()` throws any error (model load failure, inference error, timeout)
- **When** `AppStateManager.processAudio(buffer:)` is running
- **Then** the raw transcription text is pasted (not refined text), and the error is logged — no crash

**AC-4: Settings UI — New Option Visible**
- **Given** the user opens Settings → Post-Processing tab and enables post-processing
- **When** they open the "AI Processing Model" dropdown
- **Then** "Local AI (Qwen)" is listed as a third option alongside "Apple Intelligence" and "Cloud API"

**AC-5: Settings UI — Model Picker and Warning**
- **Given** the user selects "Local AI (Qwen)"
- **When** the conditional sub-section appears
- **Then** a model picker offers `Qwen 2.5 7B` (default) and `Qwen 2.5 1.5B`, a RAM/disk warning is shown for the 7B model, and a "Free Model Memory" button is present

**AC-6: Memory Unload**
- **Given** the user presses "Free Model Memory" in Settings
- **When** the button action fires
- **Then** `AppStateManager.unloadLocalLLMEngine()` is called, which calls `LocalLLMEngine.unloadModel()`, which sets the internal model container to nil (verified by log entry: "LocalLLMEngine: Model unloaded from memory.")

**AC-7: Unit Tests Pass**
- **Given** the new `LocalLLMEngineTests.swift` is present
- **When** `swift test` is run in `swift-version/`
- **Then** all 4 test cases pass without requiring real MLX model weights

---

## Additional Context

### Dependencies

- **NEW:** `mlx-swift-lm` (`https://github.com/ml-explore/mlx-swift-lm`, branch: `main`)
  - Transitively adds: `mlx-swift`, `Hub`, `Jinja`
  - Products used: `MLXLLM`, `MLXLMCommon`
- **Model download:** Handled transparently by the `Hub` package on first `refine()` call. Cached to `~/Library/Caches/huggingface/`.

### Testing Strategy

**Unit tests** (Task 5): Via injected `MockLocalLLMInferenceProvider` — no real MLX required. Run with:
```bash
cd swift-version && swift test --filter LocalLLMEngineTests
```

**Full test suite** (verify no regressions):
```bash
cd swift-version && swift test
```

**Manual verification** (requires real Mac with 16GB+ RAM):
1. Build and run the app: `make build-app` (or `swift build -c release`)
2. Open Settings → Post-Processing tab → enable "Automated Text Refinement"
3. Select "Local AI (Qwen)" from the AI Processing Model dropdown
4. Verify the "Local AI (Qwen)" sub-section appears with model picker and RAM warning
5. Press the global shortcut and dictate something → verify the text is refined by Qwen (first use will trigger model download, expected to take time)
6. Press "Free Model Memory" → verify the log shows "LocalLLMEngine: Model unloaded from memory."

### Notes

- The 10-second timeout in `AppStateManager.processAudio(buffer:)` is shared with all post-processing engines. For the first call (cold model load), the local LLM will very likely exceed this. Consider increasing the timeout to 30 seconds specifically for `"local-llm"` in a future iteration, or showing a loading indicator.
- `AppStateManager` currently uses `ObservableObject` + `@Published`, not `@Observable` — match this pattern for any new properties added to it.
- `LocalLLMEngine` must be declared `public` (matching existing engine visibility modifiers).
