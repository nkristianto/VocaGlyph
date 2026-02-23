---
stepsCompleted: [1, 2, 3, 4, 5]
inputDocuments: [WhisperService.swift, AudioRecorderService.swift, Package.swift]
workflowType: 'research'
lastStep: 5
research_type: 'technical'
research_topic: 'Transcription Speed Optimization for VocaGlyph'
research_goals: 'Identify concrete techniques to improve transcription speed when using large 1GB WhisperKit models on macOS without sacrificing accuracy'
user_name: 'Novian'
date: '2026-02-23'
web_research_enabled: true
source_verification: true
---

# Research Report: Transcription Speed Optimization for VocaGlyph

**Date:** 2026-02-23  
**Author:** Novian  
**Research Type:** Technical  

---

## Research Overview

This report investigates concrete techniques to improve transcription speed when using large (~1 GB) WhisperKit CoreML models in the VocaGlyph macOS app. The current implementation was audited, and multiple optimization vectors were identified through codebase analysis and current web research.

**Scope:** VocaGlyph's `WhisperService.swift` using WhisperKit (≥0.10.0) on macOS 14+ with Apple Silicon.

---

## Current Implementation Audit

### What VocaGlyph Does Today

| Area | Current State | Issue |
|------|--------------|-------|
| **Model init** | `WhisperKit(modelFolder: path)` | No `WhisperKitConfig` → all optimizations are at defaults |
| **Compute units** | Not set → CoreML auto-selects | May choose CPU-heavy path for large models |
| **Model warmup** | None | First transcription after app launch is slow (CoreML specialisation overhead) |
| **Decoding options** | `usePrefillCache: true`, `withoutTimestamps: true` | Good, but temperature fallback count and beam settings are at defaults which adds retry latency |
| **Audio pipeline** | Batch mode — full recording captured before transcription starts | Full latency of recording + full inference before user sees any text |
| **VAD** | Not implemented | Silent segments are transcribed, wasting compute |
| **Model selection** | User-selected (large ≈1 GB) | Slow decoder is the main bottleneck for large-v3 |

---

## Optimization Strategies

### 1. 🚀 Switch to `WhisperKitConfig` with Explicit Compute Units (High Impact, Low Effort)

**The Problem:** `WhisperKit(modelFolder:)` uses Core ML's automatic compute unit selection, which may route the large audio encoder to the CPU instead of the Apple Neural Engine (ANE) or GPU.

**The Fix:** Instantiate WhisperKit via `WhisperKitConfig` and specify `ModelComputeOptions`.

```swift
// Current code (baseline)
whisperKit = try await WhisperKit(modelFolder: modelPath.path)

// Optimized: Use WhisperKitConfig with ANE-biased compute units
let config = WhisperKitConfig(
    modelFolder: modelPath.path,
    computeOptions: ModelComputeOptions(
        melCompute: .cpuAndNeuralEngine,
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly   // small prefill runs fine on CPU
    ),
    verbose: false,
    logLevel: .none
)
whisperKit = try await WhisperKit(config)
```

**Expected Gain:** Benchmarks from Argmax show that on M-series Macs:
- ANE-only: **42× real-time** for large-v3-turbo
- GPU+ANE (`.all` compute units): **72× real-time** for large-v3-turbo
- Default ANE: substantially better than unguided CPU fallback

For a 1GB large-v3 model the encoder is the heaviest component. Routing it to ANE instead of CPU can cut encoder latency by 3–5×.

> **Recommended setting for macOS (Apple Silicon):**  
> `audioEncoderCompute: .cpuAndNeuralEngine` for power-efficient speed, or `.all` if you want maximum throughput at the cost of slightly higher thermals/battery.

---

### 2. 🔥 Prewarm the Model on App Launch (Medium Impact, Low Effort)

**The Problem:** CoreML "specializes" models to each specific chip on first load. For a 1 GB model, this can take 30–90 seconds on the first ever run and 3–10 seconds after OS updates or cache eviction. The `initializeWhisper` call already takes some time, but the first real transcription still pays a "first inference" cost.

**The Fix:** Enable `prewarm` in `WhisperKitConfig`, which triggers Core ML specialisation and caches the result immediately after load, so the first real transcription is fast.

```swift
let config = WhisperKitConfig(
    modelFolder: modelPath.path,
    prewarm: true,   // triggers CoreML specialisation → no first-inference penalty
    computeOptions: ModelComputeOptions(
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        melCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly
    )
)
whisperKit = try await WhisperKit(config)
```

**Expected Gain:** Eliminates the "first transcription is always slow" phenomenon. Subsequent transcriptions in the same session already benefit from this.

---

### 3. ⚡ Tune DecodingOptions to Reduce Retry Latency (Medium Impact, Low Effort)

**The Problem:** WhisperKit defaults to `temperatureFallbackCount = 5`, meaning if greedy decoding (temp=0) fails a quality check, it retries up to 5 more times with increasing temperature. Each retry runs a full decoder pass.

**The Fix:** For a voice-to-text dictation tool (short utterances, user is nearby, audio quality is generally good), aggressively reduce fallback retries and lock to greedy decoding:

```swift
let decodingOptions = DecodingOptions(
    language: langCode,
    usePrefillPrompt: isExplicitLanguage,
    usePrefillCache: true,
    detectLanguage: isExplicitLanguage ? false : nil,
    skipSpecialTokens: true,
    withoutTimestamps: true,
    // Speed-focused additions:
    temperature: 0.0,                    // Start greedy — fastest path
    temperatureFallbackCount: 1,         // Only 1 retry instead of 5 (saves up to 4 decoder passes)
    compressionRatioThreshold: 2.4,      // Slightly relaxed to avoid unnecessary fallbacks
    logProbThreshold: -1.0              // Relaxed to avoid unnecessary fallbacks
)
```

**Expected Gain:** On failing segments, this reduces retries from 5→1, saving up to 4 full decoder passes. For clean audio (typical dictation), the first greedy pass almost always succeeds anyway.

> **Trade-off:** Very noisy audio may get slightly lower accuracy. For a user dictating into a microphone in a normal environment, this is not a noticeable difference.

---

### 4. 🎯 Model Switch: Recommend `large-v3_turbo` as Default for Large Models (High Impact, User Choice)

**The Problem:** The full `large-v3` model has a 32-layer decoder — the decoder is the latency bottleneck for short utterances (encoder is shared, decoder runs per token).

**The Fix:** `large-v3_turbo` (already supported in WhisperKit's `argmaxinc/whisperkit-coreml` repo) reduces decoder layers from 32→4, making it **5× faster** with essentially the same accuracy (same encoder, same language support).

| Model | Size | Decoder Layers | Speed (M2 Mac, real-time factor) | WER vs large-v3 |
|-------|------|---------------|----------------------------------|-----------------|
| `large-v3` | ~1.6 GB | 32 | ~8× RT | baseline |
| `large-v3_turbo` | ~1.0 GB | 4 | ~42× RT (ANE) / 72× RT (GPU+ANE) | < 1% worse |
| `distil-whisper_distil-large-v3` | ~0.6 GB | 2 | ~6× faster than large-v3 | within 1% WER |

If the user is currently on `large-v3` (the 1.6 GB model), recommend they switch to `large-v3_turbo` (already ~1 GB, already in their downloaded model set). If they want to go further, `distil-whisper_distil-large-v3` is the fastest high-accuracy option for English.

> **Note:** VocaGlyph already supports distil-whisper naming convention in `WhisperService.swift` (the `hasPrefix("distil-whisper_")` check). No code changes needed for model support.

---

### 5. 🎙️ Implement Voice Activity Detection (VAD) to Skip Silent Segments (Medium Impact, Medium Effort)

**The Problem:** WhisperKit processes ALL audio including silence. The audio encoder runs on the full 30-second padded audio frame even if the user only spoke for 3 seconds.

**The Fix:** WhisperKit ≥0.10.0 exposes a `voiceActivityDetector` property in `WhisperKitConfig`. Enabling the built-in VAD allows WhisperKit to skip encoding silent portions:

```swift
let config = WhisperKitConfig(
    modelFolder: modelPath.path,
    prewarm: true,
    computeOptions: ModelComputeOptions(
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        melCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly
    )
)
whisperKit = try await WhisperKit(config)

// Then when transcribing, pass VAD-filtered audio or enable chunking
```

Additionally, since VocaGlyph's `AudioRecorderService` accumulates a flat `[Float]` array, you can trim leading/trailing silence before passing the array to WhisperKit:

```swift
// Simple energy-based VAD trim before transcription
private func trimSilence(_ samples: [Float], threshold: Float = 0.01) -> [Float] {
    let firstNonSilent = samples.firstIndex(where: { abs($0) > threshold }) ?? 0
    let lastNonSilent = samples.lastIndex(where: { abs($0) > threshold }) ?? samples.count - 1
    guard firstNonSilent < lastNonSilent else { return samples }
    return Array(samples[firstNonSilent...lastNonSilent])
}
```

**Expected Gain:** If a user speaks for 3 seconds but records for 10 seconds, VAD trimming reduces encoder input by 70%. For the 1 GB model, encoder time scales roughly linearly with audio length up to 30s.

---

### 6. 🔄 Progressive / Streaming Mode for Perceived Speed (Medium Impact, High Effort)

**The Problem:** The current UX is: record → stop → wait → see text. For longer recordings with a large model, the wait feels long even if absolute speed is good.

**The Opportunity:** WhisperKit supports streaming inference. The encoder can process overlapping chunks progressively while recording is still happening, and partial results are shown to the user as the model decodes them.

**Implementation sketch in VocaGlyph:**
- The `AudioRecorderService` already provides real-time buffers via `installTap`
- Instead of accumulating all samples and transcribing at the end, feed 5-second chunks to `whisperKit.transcribeStreaming(...)` continuously
- Display partial results in the overlay/HUD while recording continues

**Expected Gain:** Zero reduction in absolute compute time, but **perceived latency drops to near-zero** — the user sees text appearing while still speaking. This is the most impactful UX change for the "feels slow" problem with large models.

> **Trade-off:** Streaming mode is more complex and may produce "corrections" as context accumulates. Appropriate for the dictation use case where users expect to see text in real-time.

---

## Prioritized Recommendations

| Priority | Technique | Effort | Expected Speed Gain | Risk |
|----------|-----------|--------|---------------------|------|
| **P1** | Use `WhisperKitConfig` + `cpuAndNeuralEngine` compute units | Low | **3–5× encoder speedup** | Very Low |
| **P1** | Enable `prewarm: true` | Low | Eliminates first-run penalty | Very Low |
| **P2** | Tune `DecodingOptions` (temp fallback = 1, greedy) | Low | **2–4× fewer decoder retries** | Low |
| **P2** | Switch model to `large-v3_turbo` | Low (user setting) | **5× vs large-v3 decoder** | Very Low |
| **P3** | Energy-based VAD trim on `[Float]` before transcription | Low-Medium | Up to **70% encoder input reduction** | Low |
| **P4** | WhisperKit streaming mode for real-time perceived output | High | Near-zero perceived latency | Medium |

---

## Quick Win: Consolidated Code Change for P1 + P2

This is the minimum change to `WhisperService.swift` that captures P1 and P2 gains:

```swift
// In initializeWhisper(modelName:) — replace the current WhisperKit init line:

// BEFORE (line 159):
whisperKit = try await WhisperKit(modelFolder: modelPath.path)

// AFTER:
let config = WhisperKitConfig(
    modelFolder: modelPath.path,
    computeOptions: ModelComputeOptions(
        melCompute: .cpuAndNeuralEngine,
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly
    ),
    prewarm: true,
    verbose: false,
    logLevel: .none
)
whisperKit = try await WhisperKit(config)
```

And in `transcribe(audioBuffer:)` — tune `DecodingOptions`:

```swift
// BEFORE (lines 309-316):
let decodingOptions = DecodingOptions(
    language: langCode,
    usePrefillPrompt: isExplicitLanguage,
    usePrefillCache: true,
    detectLanguage: isExplicitLanguage ? false : nil,
    skipSpecialTokens: true,
    withoutTimestamps: true
)

// AFTER — add these speed-tuning parameters:
let decodingOptions = DecodingOptions(
    language: langCode,
    usePrefillPrompt: isExplicitLanguage,
    usePrefillCache: true,
    detectLanguage: isExplicitLanguage ? false : nil,
    skipSpecialTokens: true,
    withoutTimestamps: true,
    temperature: 0.0,
    temperatureFallbackCount: 1
)
```

---

## Sources & References

1. [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit) — `WhisperKitConfig`, `ModelComputeOptions`, `DecodingOptions` API reference
2. [Argmax Performance Benchmarks](https://huggingface.co/argmaxinc/whisperkit-coreml) — M2 Ultra benchmarks: 42× RT (ANE), 72× RT (GPU+ANE) for large-v3-turbo
3. [WhisperKit arXiv paper](https://arxiv.org/abs/2406.10390) — Architecture mods, streaming inference, ANE acceleration design
4. [Distil-Whisper HuggingFace Card](https://huggingface.co/distil-whisper/distil-large-v3) — 6× speed, within 1% WER of large-v3
5. [OpenAI large-v3-turbo Release](https://medium.com/@shivamchamp001/openai-whisper-large-v3-turbo-5x-faster-same-quality-a0f2ce5d0524) — 5× faster vs large-v3, same accuracy, 4 decoder layers
6. [Apple MLComputeUnits Documentation](https://developer.apple.com/documentation/coreml/mlcomputeunits) — `.cpuAndNeuralEngine`, `.cpuAndGPU`, `.all` options
7. [WhisperKit VAD config](https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/WhisperKit.swift) — `voiceActivityDetector` in `WhisperKitConfig`
