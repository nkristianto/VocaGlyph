# Technical Research: Local LLM Model Loading Strategies for VocaGlyph
**Date:** 2026-02-22 | **Project:** voice-to-text (VocaGlyph) | **Author:** Novian

---

## Executive Summary

VocaGlyph currently uses a **lazy-load on first transcription** strategy for its local MLX LLM post-processing model. This causes the first dictation session to be significantly delayed (5–30 seconds depending on model size) while the model loads into Unified Memory. This document evaluates four strategies to improve this experience, with concrete trade-offs and a final recommendation.

---

## Current State Analysis

### How it works today

```
User presses hotkey
    → transcription runs
    → if post-processing enabled and model not loaded:
        → loadContainer() called inline (5–30s blocking perception)
    → result pasted
```

**Relevant code:**
- `LocalLLMEngine.swift` → `MLXLMInferenceProvider.generate()` calls `LLMModelFactory.shared.loadContainer()` if `cachedContainer == nil`
- `AppStateManager.swift` → `switchPostProcessingEngine()` sets `postProcessingEngine = localLLMEngine` but **does not pre-warm** it
- `startEngine()` in `AppStateManager` is called at app launch — this is the entry point where warm-up could be triggered

### The problem

`LLMModelFactory.shared.loadContainer()` does two things:
1. Downloads model weights from HuggingFace (if not on disk) — **network I/O**, slow
2. Loads model weights into Metal/Unified Memory — **CPU+GPU intensive**, 2–15s

Both happen inline during the first call to `generate()`, causing the perceived "hang" on first use.

---

## Strategy Comparison

### Strategy 1: Eager Warm-up at App Launch (Recommended ✅)

**What:** When the app starts and `selectedTaskModel == "local-llm"`, immediately fire a background `Task` to call `preloadModel()`. The model is in memory by the time the user first presses the hotkey.

**How it fits your codebase:**
```swift
// AppStateManager.startEngine() — add this:
func startEngine() {
    // ... existing engine setup ...
    switchPostProcessingEngine()
    
    // NEW: warm up local LLM in background if it's the selected engine
    if UserDefaults.standard.string(forKey: "selectedTaskModel") == "local-llm" {
        let modelId = UserDefaults.standard.string(forKey: "selectedLocalLLMModel") 
                      ?? "mlx-community/Qwen2.5-7B-Instruct-4bit"
        if isModelDownloadedOnDisk(modelId: modelId) {
            Task.detached(priority: .background) {
                await self.preloadLocalLLMModel()
            }
        }
    }
}
```

**Key constraint:** Only warm-up if model is **already on disk**. Do NOT trigger a network download on app launch — that creates a poor experience for users on slow/metered connections.

**Pros:**
- ✅ Zero perceived latency on first hotkey press
- ✅ Your `preloadModel()` API already exists in `LocalLLMEngine`
- ✅ Minimal code change (3–5 lines in `startEngine()`)
- ✅ Task runs at `.background` priority — won't compete with UI or transcription

**Cons:**
- ❌ Consumes ~300MB–4GB of Unified Memory at launch (depends on model selection)
- ❌ If user rarely uses local LLM, memory is wasted

**Memory impact by model:**
| Model | Approx. RAM Usage |
|---|---|
| Qwen 3 0.6B (4-bit) | ~300–400 MB |
| Qwen 2.5 7B (4-bit) | ~4–5 GB |
| Small (Whisper) | N/A (different) |

---

### Strategy 2: Deferred Warm-up After First Transcription Session

**What:** Don't preload at launch. Instead, trigger preloading immediately after a successful transcription — before the user presses the hotkey a second time.

**How:**
```swift
// In AppStateManager.processAudio(), after pasting result:
Task.detached(priority: .background) {
    if !self.isModelWarmed {
        await self.preloadLocalLLMModel()
        self.isModelWarmed = true
    }
}
```

**Pros:**
- ✅ Only warms up if user is actively using the app
- ✅ Second dictation is fast; only first is slow
- ✅ App launch time unaffected

**Cons:**
- ❌ First session still slow — this is the original problem
- ❌ The warm-up after transcription competes with the next recording session

**Verdict:** This is better than current behavior for power users but doesn't fix the root problem.

---

### Strategy 3: Predictive Warm-up Based on Time of Day / Usage Pattern

**What:** Learn when the user typically uses the app and pre-warm the model proactively. For example, warm up at 9:00 AM if the user always starts recording around 9:10 AM.

**Implementation:** Requires tracking usage timestamps in UserDefaults, scheduling `BGAppRefreshTask`/`NSBackgroundActivityScheduler`, and triggering warm-up.

**Pros:**
- ✅ Highly intelligent — near-zero wait time
- ✅ Memory freed during non-working hours

**Cons:**
- ❌ **Complex to implement correctly** — scheduling is unreliable on macOS menu bar apps
- ❌ Requires significant new infra (usage tracking, scheduler, etc.)
- ❌ On macOS, `BGProcessingTask` (iOS) has no direct equivalent — `NSBackgroundActivityScheduler` is best-effort and often delayed by the OS
- ❌ Cold start problem still exists for new users or irregular usage

**Verdict:** Interesting but overengineered for this app's current scale. Not recommended now.

---

### Strategy 4: Warm-up Token / Dummy Inference at Launch

**What:** After loading the model container, run a trivial inference pass (e.g., `"Hello"` → discarded) to ensure Metal shaders are compiled and the compute graph is warm. Used in production LLM apps (LM Studio, Ollama) to reduce first-token latency.

**How:**
```swift
// After preloadModel() completes:
private func warmUpInference() async {
    _ = try? await provider.generate(
        prompt: "<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n",
        modelId: modelId
    )
    Logger.shared.info("LocalLLMEngine: Inference warm-up complete")
}
```

**Pros:**
- ✅ Eliminates Metal shader JIT compilation delay on first real inference
- ✅ First-token latency on real use reduced by 1–3 seconds

**Cons:**
- ❌ Adds 2–5 extra seconds to startup sequence (the warm inference)
- ❌ Only meaningful if model is already loaded — i.e., this is an enhancement on top of Strategy 1

**Verdict:** Use this as a **complement to Strategy 1**, not a standalone solution.

---

## Final Recommendation

### Implement Strategy 1 + Strategy 4 together

| Phase | Action | When |
|---|---|---|
| **App launch** | Check if `selectedTaskModel == "local-llm"` AND model is on disk | `startEngine()` |
| **Background Task (priority: .background)** | Call `preloadLocalLLMModel()` silently | ~5s after launch |
| **After model loaded** | Optional: run 1 dummy inference to warm Metal shaders | Same background Task |
| **User presses hotkey** | Model already in memory → instant post-processing | Any time after warm-up |

### UI Considerations

- Add a subtle status indicator in the menu bar or settings showing `⏳ Loading model…` / `✅ Model ready` during background warm-up
- This manages user expectation — if they press hotkey before warm-up completes, they still see progress rather than a mystery hang
- Your existing `@Published var localLLMDownloadProgress` can drive this — just show it in the HUD or status bar

### Memory Management

- Keep existing `unloadModel()` (Free RAM button) — users with tight RAM can manually evict
- Consider auto-unload after **30 minutes of inactivity**: use `Timer` or `DispatchSourceTimer` to track last use timestamp; evict if idle too long

---

## Implementation Complexity & Effort Estimate

| Strategy | Effort | Risk | Payoff |
|---|---|---|---|
| Strategy 1 (eager warm-up) | **Low** (~30 min) | Low | High |
| Strategy 4 (Metal warm-up) | **Low** (~15 min) | Low | Medium |
| Strategy 2 (deferred) | Low (10 min) | Low | Low |
| Strategy 3 (predictive) | High (2–3 days) | Medium | High |
| Auto-unload on inactivity | Medium (1–2h) | Low | Medium |

---

## Alternative: Apple Foundation Models (macOS 26+)

For a future improvement, **Apple's Foundation Models framework** (announced at WWDC 2025, available macOS 26+) provides on-device LLM inference with:
- System-managed model loading (no user downloads)
- Shared model across all apps — zero RAM cost if another app already loaded it
- `LanguageModelSession` with built-in reuse and warm caching

This would completely eliminate the loading delay problem for users on macOS 26+ with compatible Apple Silicon. Worth exploring as a parallel track alongside the MLX strategy.

---

## Sources

1. mlx-swift `LLMModelFactory` API — [github.com/ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
2. Apple on-device ML performance guidelines — developer.apple.com
3. Background task scheduling on macOS — `NSBackgroundActivityScheduler` docs
4. LLM warm-up patterns from LM Studio and Ollama — community research
5. Apple Foundation Models (macOS 26) — WWDC 2025 session notes
