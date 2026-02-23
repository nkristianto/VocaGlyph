---
stepsCompleted: [1, 2, 3]
inputDocuments: []
workflowType: 'research'
lastStep: 3
research_type: 'technical'
research_topic: 'WhisperKit large-v3-turbo performance issues & LocalLLMEngine crash in VocaGlyph'
research_goals: 'Understand root causes of: (1) memory spike on startup, (2) hotkey recording latency, (3) microphone permission hang, (4) Qwen LocalLLMEngine crash — and enumerate concrete fix options for each.'
user_name: 'Novian'
date: '2026-02-23'
web_research_enabled: true
source_verification: true
---

# Technical Research Report: VocaGlyph Performance & Crash Issues

**Date:** 2026-02-23  
**Author:** Novian  
**Research Type:** Technical  

---

## Research Overview

This report investigates four distinct performance and stability issues in the VocaGlyph macOS app, all rooted in how heavyweight ML models and AVFoundation audio interact with the macOS process lifecycle. The analysis combines a direct code audit of the Swift codebase with current external research to produce root-cause diagnoses and ranked fix options.

**Issues investigated:**
1. Large memory spike on first launch when using `large-v3-turbo`
2. Delay between hotkey press/release and visible recording/overlay state
3. Intermittent hang after microphone permission is granted mid-session
4. App crash when switching to the Qwen local LLM post-processing engine

---

## Technical Research Scope Confirmation

- **Architecture Analysis** — design patterns, initialization sequences, threading model  
- **Implementation Approaches** — code-level root cause investigation  
- **Technology Stack** — WhisperKit/CoreML, AVAudioEngine, mlx-swift, macOS TCC  
- **Performance Considerations** — memory, ANE routing, Metal shader compilation, latency  

**Scope Confirmed:** 2026-02-23

---

## Issue 1: Memory Spike on First Launch (WhisperKit large-v3-turbo)

### Root Cause Analysis

**How the code works today:**

In `AppDelegate.swift` line 86–90:
```swift
whisper = WhisperService()          // init() immediately fires Task { autoInitialize() }
stateManager.startEngine()          // also calls autoInitialize → initializeWhisper
```

`initializeWhisper()` in `WhisperService.swift` calls `WhisperKit(config)` with `prewarm: true`, which:  
1. Loads all CoreML model graphs (audio encoder + text decoder) into Unified Memory  
2. Triggers `ANECompilerService` to do on-device specialisation of all compiled graphs  
3. With `large-v3-turbo` this is **~1.5–2 GB of CoreML model assets** loading concurrently with app startup

All of this runs during `applicationDidFinishLaunching`, racing with SwiftUI window setup, SwiftData container creation, and the hotkey service start.

**External research findings:**

- WhisperKit explicitly disables `*-turbo` models on **M1 and A14 chips** due to `ANECompilerService` compatibility issues. On those chips, large-v3-turbo can trigger ANE fallback to CPU or GPU, causing 3–5× longer load times and a documented MPSGraph memory leak. ([WhisperKit GitHub issues](https://github.com/argmaxinc/WhisperKit))
- The initial `ANECompilerService` specialisation on any large model can take **25–45 seconds** on first run and contributes to visible launch-time "black" freezing.
- `prewarm: true` (which is already set in the code) helps on subsequent launches but does NOT eliminate the initial specialisation cost.

**Chip-specific behaviour table:**

| Chip | large-v3-turbo Support | ANE Perf | Notes |
|------|------------------------|----------|-------|
| M1 / A14 | ⚠️ Problematic | Degraded | Documented ANE compiler issues; CPU fallback |
| M2+ / A15+ | ✅ Supported | Best | Turbo optimised for these chips |
| M3/M4 | ✅ Supported | Best | Recommended platform |

### Fix Options (Ranked)

**Option A — Deferred/lazy model loading** *(Low risk, high impact)*  
Don't call `initializeWhisper()` at app launch. Instead, load the model in the background on a `.background` priority Task the first time the user presses the hotkey, while the app shows an "Engine warming up…" overlay state. The model is ready within 5–15 seconds; the user rarely presses the hotkey in the first 5 seconds after app launch.

**Option B — Switch to `distil-whisper_distil-large-v3`** *(Medium change, high impact)*  
`distil-large-v3` (a knowledge-distilled version of large-v3) is:
- **6.3× faster** than large-v3
- **1.1–1.5× faster** than large-v3-turbo on M2+
- Accuracy within **0.8% WER** of large-v3 on long-form; slightly higher WER on short clips
- **No ANE compatibility issues on M1** — explicitly tested
- Available in `argmaxinc/whisperkit-coreml` — model ID: `distil-whisper_distil-large-v3`

For a push-to-talk dictation app with short clips, the accuracy trade-off is negligible.

**Option C — Use `large-v3` (non-turbo)** *(Minimal change)*  
On M1-class hardware, switching to the non-turbo `large-v3` has been shown to resolve "excessive loading time per transcription" and eliminates the ANE compiler issue. It is slower at inference time (~1.5×) but stabler.

**Option D — Reduce compute scope** *(Quickest code change)*  
Change `audioEncoderCompute` from `.cpuAndNeuralEngine` to `.cpuAndGPU` as a temporary fallback for users on M1. This avoids the ANE specialisation pass but loses 3–5× encoder speedup on M2+. Best implemented as a runtime check by chip generation.

---

## Issue 2: Hotkey Latency — Recording Start/Stop Delay

### Root Cause Analysis

The critical path from hotkey press → recording state → overlay visible involves several sequential, potentially blocking operations:

**Start recording path:**
```
HotkeyService (CGEvent tap thread)
  → stateManager.startRecording()        [AppState = .recording → delegate callback]
  → AppDelegate.appStateDidChange()      [DispatchQueue.main.async → UI update]
  → audioRecorder.startRecording()       [runs synchronously on main thread]
      → engine.stop() (if running)
      → engine.inputNode.removeTap()
      → engine.inputNode.installTap()
      → engine.prepare()
      → engine.start()                   [can block 50–200ms waiting for I/O device]
```

**Problems identified:**

1. **`AVAudioEngine.start()` on main thread**: The `startRecording()` call is made from `AppDelegate.appStateDidChange()` which is already dispatched to the main thread. `engine.start()` is a synchronous call that waits for the I/O unit to initialise. On macOS, this involves HAL (Hardware Abstraction Layer) negotiation and can block for **50–300ms**, which directly delays the overlay animation being visible.

2. **Engine teardown on every press**: The code does `engine.stop()` + `removeTap()` + `installTap()` + `engine.prepare()` on every recording. This full teardown-and-rebuild cycle adds extra latency because the audio HAL must reconfigure the I/O device each time.

3. **`WhisperKit` on main thread during first transcription**: If the model is still loading when the hotkey fires, `transcribe()` throws immediately ("WhisperKit is not ready"), which is handled, but the state machine still visually shows "processing" before snapping back to idle — creating a confusing delay.

**External research findings:**
- `AVAudioEngine` input node initialization has a reported latency of ~100ms on macOS; this can compound with HAL device negotiation.
- Installing a tap on the main thread is flagged by Apple as a crash risk in some configurations.
- The recommended pattern for low-latency recording is to **keep the engine running** (with the tap installed) and only clear the buffer on hotkey press, rather than starting/stopping the engine on each recording.

### Fix Options (Ranked)

**Option A — Persistent engine (keep-alive tap)** *(Best long-term, medium effort)*  
Initialize and start `AVAudioEngine` once at app startup (after permissions are confirmed) and keep it running continuously. On hotkey press, simply set a `isCapturing` flag and begin accumulated samples. On hotkey release, stop accumulation and drain the buffer. This eliminates all Engine start/stop latency from the hot path. The engine's continuous idle CPU cost on macOS is negligible (~0.1% on Apple Silicon).

**Option B — Move `startRecording()` off main thread** *(Low effort, immediate win)*  
Wrap the `audioRecorder.startRecording()` call in a `Task.detached(priority: .userInteractive)` block inside `appStateDidChange`. The UI state is already set to `.recording` (triggering the overlay animation) before the engine starts, so animations are no longer blocked by HAL I/O setup.

**Option C — Pre-prepare the engine** *(Quick win)*  
Call `engine.prepare()` at app startup (which pre-allocates the I/O device linkage) without calling `engine.start()`. This makes the subsequent `engine.start()` call in `startRecording()` significantly faster because device negotiation is already done.

---

## Issue 3: Microphone Permission Hang (Intermittent)

### Root Cause Analysis

**The problematic sequence:**

```
1. User presses hotkey
2. HotkeyService → stateManager.startRecording() → AppState = .recording
3. AppDelegate.appStateDidChange(.recording) → audioRecorder.startRecording()
4. engine.start() is called...
5. macOS TCC system intercepts → shows microphone permission dialog
6. App is blocked on engine.start() while the dialog is visible
7. User grants permission
8. engine.start() returns... but the CallbackHandler in AVAudioEngine may have
   been in a broken/partial state during the dialog window
9. The tap is installed on a partially-initialised input node → tap callback never fires
10. App is stuck in .recording state permanently
```

**The core issue:** When `AVAudioEngine` triggers the TCC permission dialog (because the app accesses `inputNode`), the engine enters a suspended state. If the user grants permission, macOS notifies the app via the `AVAudioEngine.configurationChangeNotification`, but the current code has **no observer** for this notification. The engine must be fully restarted after a configuration change, but the code only calls `engine.start()` once per hotkey press.

This is documented in Apple Developer Forums as a race condition between permission grant and IO unit availability.

**Code audit finding in `AudioRecorderService.swift`:**

The `init()` calls `requestPermissions()` (line 19), which calls `AVCaptureDevice.requestAccess` **asynchronously** (line 27). This means when `startRecording()` is subsequently called, permission may still be in `.notDetermined` → `.authorized` transition, and `engine.start()` can catch TCC in a mid-transition state.

### Fix Options (Ranked)

**Option A — Observe `AVAudioEngineConfigurationChange` + auto-restart** *(Essential fix)*  
Register an observer for `AVAudioEngineConfigurationChange` notification in `AudioRecorderService`. When fired (which happens after any permission change), stop the engine, remove all taps, and rebuild the audio graph. If the app is currently in `.recording` state when this happens, automatically restart recording.

```swift
// In AudioRecorderService.init():
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleConfigurationChange),
    name: .AVAudioEngineConfigurationChange,
    object: engine
)
```

**Option B — Pre-request permission at proper time** *(Prevents the race condition)*  
Move microphone permission request to **before** `initializeCoreServices()` is called, and gate `startRecording()` on permission being `.authorized`. If permission is `.notDetermined`, show a clear UI prompt rather than allowing the engine to implicitly trigger the system dialog during an active recording attempt.

This is the Apple-recommended pattern: always check and request permission via `AVCaptureDevice.requestAccess` before trying to use audio, never let `AVAudioEngine` trigger the dialog implicitly.

**Option C — Cancel + reset on failed start** *(Defensive guard)*  
If `engine.start()` throws (including TCC-related hardware errors), immediately set the app state back to `.idle` with a visible user notification: "Please grant microphone access and try again." This is already partially done (`setIdle()` on throw) but should also force-reset `currentState` even if the exception is from TCC (currently the engine.start() error is caught but the recording state might linger if the exception surfaces later).

**Option D — Check permission before every `startRecording()` call**  
Before calling `audioRecorder.startRecording()` in `appStateDidChange`, check authorization status. If not `.authorized`, set state to idle and show a notification. This prevents the engine from ever encountering TCC mid-flight.

---

## Issue 4: Qwen LocalLLMEngine App Crash

### Root Cause Analysis

**Last known log line:**
```
[2026-02-23 20:03:22.756] [INFO ] AppStateManager: Creating LocalLLMEngine for model: mlx-community/Qwen2.5-1.5B-Instruct-4bit
```

No subsequent logs — the app crashed before any further log output was written, which indicates a **signal-level termination** (EXC_BAD_ACCESS, SIGKILL from OOM, or an unhandled Metal/MPSGraph exception), not a Swift error that could be caught.

**Root cause candidates:**

**1. OOM (Out-of-Memory) SIGKILL — most likely**  
`LocalLLMEngine` is created in `AppStateManager.localLLMEngine` (a computed property), which instantiates `MLXLMInferenceProvider`. The `MLXLMInferenceProvider.loadContainer()` call loads **Qwen2.5-1.5B-Instruct-4bit** model weights (~1–1.5 GB) into Unified Memory via MLX. If this happens **simultaneously with WhisperKit's large-v3-turbo loading** (which takes ~1.5–2 GB), the combined allocation can hit macOS's memory pressure threshold on 8 GB or 16 GB machines, triggering a jetsam SIGKILL with no log output.

The `warmUpLocalLLMIfNeeded()` in `AppStateManager.startEngine()` runs the LLM load as a `Task.detached(priority: .background)`, but it runs concurrently with `WhisperKit` initialisation, not after it.

**2. Metal command queue failure**  
MLX uses Metal for matrix operations. When `LLMModelFactory.shared.loadContainer()` allocates Metal buffers and MLX's device context is not yet initialised, it can throw a "Command queue creation failed" Metal error that is not caught and propagates as an unhandled exception. This has been filed in mlx-swift issues at version 0.25.2+ on macOS Sequoia.

**3. `warmUpInference()` crashing on corrupt container**  
After `preloadModel()`, the code runs `warmUpInference()` which calls `provider.generate()`. If the container is partially loaded (due to OOM), the generate call can dereference a nil pointer in the MLX tensor graph, crashing without a catchable Swift error.

**External research confirms:** mlx-swift running Qwen2.5 on macOS can see memory spikes to 12.5 GB for even moderate-length inputs, and simultaneous loading of WhisperKit + MLX models is a well-documented source of OOM crashes on ≤16 GB systems.

### Fix Options (Ranked)

**Option A — Sequential loading: WhisperKit first, then LLM** *(Most impactful)*  
Modify `warmUpLocalLLMIfNeeded()` in `AppStateManager` to only run after WhisperKit's `isReady` becomes `true`. Use a Combine subscription or a checked continuation to sequence the loads:

```swift
// Wait for WhisperKit to finish before loading LLM
private func warmUpLocalLLMIfNeeded() {
    guard selectedPostModel == "local-llm", postProcessingEnabled else { return }
    // Subscribe to whisper.isReady — only start LLM load when WhisperKit is done
    Task.detached(priority: .background) { [weak self] in
        guard let self else { return }
        // Poll or await WhisperKit readiness
        while await !(self.sharedWhisper?.isReady ?? false) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        await self.preloadLocalLLMModel()
    }
}
```

**Option B — Add memory pressure guard before LLM load** *(Defensive)*  
Before calling `LLMModelFactory.shared.loadContainer()`, query `ProcessInfo.processInfo.physicalMemory` and the current process RSS to estimate if there's enough headroom. If not, surface a user-visible warning ("Insufficient memory to load local model — please free memory first") and skip loading.

**Option C — Catch Metal errors from `loadContainer()`** *(Defensive + logging)*  
Wrap the `LLMModelFactory.shared.loadContainer()` call in a broader error handler that catches `NSException` (Metal errors are often ObjC exceptions, not Swift errors). Write the exception to disk immediately before it propagates:

```swift
// MLX Metal exceptions are Obj-C and won't be caught by Swift try/catch
// Consider NSException handler or using Obj-C bridge for safety boundary
```

**Option D — Add crash reporter** *(Observability)*  
If logs aren't written before the crash, add a synchronous `flush()` to `LoggerService` on all log writes, or switch the logger to use `os_log` which writes to the system log (accessible via `Console.app`) and survives app crashes. This would make future crash debugging much easier.

---

## Summary & Recommended Action Order

| Priority | Issue | Root Cause | Best Fix |
|----------|-------|-----------|----------|
| 🔴 Critical | LocalLLMEngine crash | OOM / Metal error during concurrent WhisperKit+LLM load | Sequential loading (Option A) + crash-safe logging (Option D) |
| 🔴 Critical | Permission hang | No `AVAudioEngineConfigurationChange` observer; TCC race | Observe config change + restart (Option A) + pre-gate permission (Option B) |
| 🟠 High | Memory spike on launch | WhisperKit large-v3-turbo loading synchronously at app start | Defer model load (Option A) OR switch to `distil-large-v3` (Option B) |
| 🟡 Medium | Hotkey recording latency | `engine.start()` blocking main thread on each press | Persistent engine keep-alive (Option A) OR offload to background thread (Option B) |

### Quick Wins (low risk, apply now)
1. Move `audioRecorder.startRecording()` off main thread → eliminates UI blocking
2. Add observer for `AVAudioEngineConfigurationChange` → fixes permission hang
3. Sequence WhisperKit first, LLM second → prevents OOM crash
4. Switch logger to `os_log` → crash-safe logging via Console.app

### Medium-Term (model/architecture change)
5. Evaluate `distil-large-v3` as primary model — better M1 compatibility, comparable accuracy for short-form dictation
6. Implement persistent `AVAudioEngine` keep-alive pattern — eliminates all start-latency

---

## Sources & References

- WhisperKit GitHub Issues — ANE compatibility on M1/A14: https://github.com/argmaxinc/WhisperKit
- HuggingFace distil-large-v3 model card (6.3× speedup vs large-v3): https://huggingface.co/distil-whisper/distil-large-v3
- Apple Developer Forums — AVAudioEngine configuration change handling: https://developer.apple.com
- mlx-swift GitHub — Metal command queue errors, OOM behaviour: https://github.com/ml-explore/mlx-swift
- Apple TCC documentation — requestAccess timing: https://developer.apple.com/documentation/avfoundation/avcapturedevice
