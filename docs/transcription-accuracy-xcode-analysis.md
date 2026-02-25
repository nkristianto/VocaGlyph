# Analysis Plan: Transcription Accuracy Drop After Xcode Migration

## Background

VocaGlyph is a macOS menu-bar dictation app using WhisperKit (CoreML) and Apple's `SFSpeechRecognizer` for transcription.
After migrating from **SPM-only** (`swift-version/`) to an **Xcode project** (`xcode-project/VocaGlyph/`), the app runs but transcription accuracy dropped significantly.

The codebase is **identical** — the Xcode project consumes `swift-version` as a local SPM package (`VocaGlyphLib`).  
This means the accuracy regression is almost certainly caused by **build configuration differences**, not source code changes.

---

## Root Cause Hypotheses (ranked by likelihood)

### H1 — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` changes async audio pipeline behavior *(Most Likely)*

**Evidence in `project.pbxproj`:**
```
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
SWIFT_APPROACHABLE_CONCURRENCY = YES;
```

`AudioRecorderService` collects audio buffers on a private audio dispatch queue (`bufferQueue`) and assembles them in `stopRecording()`. When `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is applied to the `VocaGlyphLib` module, async functions calling into the audio pipeline may execute on the Main Actor instead of the expected concurrency context.

If the `bufferQueue.sync {}` drain in `stopRecording()` races with Main Actor scheduling, in-flight buffer appends may be **cut short** — resulting in truncated audio being fed to `WhisperKit.transcribe()`. Truncated audio = words missed = apparent accuracy drop.

> **Note:** This flag is NOT set in the SPM build. `swift-tools-version: 5.9` does not set any global actor isolation.

**Diagnostic (Step 2):** Compare `audioArray.count` in `WhisperService.transcribe()` and `data.count` in `AudioRecorderService.stopRecording()` between SPM and Xcode builds for the same speech duration.

---

### H2 — Double WhisperKit instance loading (framework linked twice)

**Evidence in `project.pbxproj`:**
- `WhisperKit` linked directly as top-level framework dependency
- `VocaGlyphLib` also depends on `WhisperKit` internally

Two copies of the WhisperKit runtime may be loaded, causing the model initialized by `WhisperService` to be different from the one performing inference.

**Diagnostic (Step 4):**
```bash
otool -L VocaGlyph.app/Contents/MacOS/VocaGlyph | grep -i whisper
```

**Fix candidate:** Remove the direct top-level `WhisperKit` framework reference — let it be satisfied transitively through `VocaGlyphLib`.

---

### H3 — `GENERATE_INFOPLIST_FILE = YES` overrides external `Info.plist`, losing microphone permission

**Evidence in `project.pbxproj`:**
```
GENERATE_INFOPLIST_FILE = YES;
INFOPLIST_FILE = "../../swift-version/Info.plist";  (set simultaneously at project level)
```

When both are set, the generated plist takes priority. The external `Info.plist` only has `CFBundleIconFile` and `NSAccessibilityUsageDescription`. If `NSMicrophoneUsageDescription` is lost, macOS silently denies audio capture — the `AVAudioEngine` tap installs without error but the buffer contains silence.

**Diagnostic (Step 5):** Open Console.app, filter by `process: tccd`, look for `deny(1) microphone` while recording.

---

### H4 — `MACOSX_DEPLOYMENT_TARGET = 14.6` vs Package.swift `.macOS(.v14)` (14.0)

Certain CoreML dispatch changes for `.cpuAndNeuralEngine` were introduced in macOS 14.x point releases. A higher deployment target may activate different ANE scheduling paths on older OS versions.

---

### H5 — `ENABLE_USER_SELECTED_FILES = readonly` blocks model directory access

WhisperKit stores models in `~/Library/Application Support/VocaGlyph/models/`. A new bundle ID (`com.vocaglyph.app`) may not have an established sandbox container, restricting file access.

---

## Structured Diagnostic Investigation Plan

### ✅ Step 1: Confirm which engine is being used
Add a log to `EngineRouter.swift` to confirm you're testing the **same engine** (Whisper vs Apple Native) in both builds.

### 🔬 Step 2: Measure audio buffer size (addresses H1 + H3)
Add temporary logs:

In `AudioRecorderService.stopRecording()`:
```swift
Logger.shared.info("[DIAG] Audio captured: \(data.count) frames (\(Float(data.count)/16000.0)s)")
```

In `WhisperService.transcribe()`, before the `trimSilence` call:
```swift
Logger.shared.info("[DIAG] Transcribe input: \(audioArray.count) samples (\(Float(audioArray.count)/16000.0)s)")
```

**Compare** these numbers between SPM run vs Xcode run for the same duration of speech. A significantly lower count in the Xcode build confirms H1 or H3.

### 📶 Step 3: Check for silent audio (addresses H3)
In `AudioRecorderService.processBuffer()`:
```swift
let rms = sqrt(slice.map { $0 * $0 }.reduce(0, +) / Float(slice.count))
Logger.shared.debug("[DIAG] Buffer RMS: \(rms)")
```
If RMS is consistently ~0.0 in the Xcode build = microphone permission denied.

### 🔗 Step 4: Check for double WhisperKit loading (addresses H2)
```bash
otool -L <path-to-VocaGlyph.app>/Contents/MacOS/VocaGlyph | grep -i whisper
```

### 📋 Step 5: Check Console for TCC microphone denials (addresses H3)
Open Console.app → filter `process: tccd` → reproduce issue → look for `deny(1) microphone`.

### ⚙️ Step 6: Disable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (addresses H1)
In Xcode Build Settings for the **VocaGlyph target**, delete `SWIFT_DEFAULT_ACTOR_ISOLATION` and `SWIFT_APPROACHABLE_CONCURRENCY`, rebuild, and retest.

---

## Priority Summary

| Rank | Hypothesis | Confidence | Impact |
|------|-----------|-----------|--------|
| 1 | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` disrupts audio buffer pipeline | High | Silent truncation of audio |
| 2 | Double WhisperKit framework loading | Medium | Wrong model instance used |
| 3 | Missing microphone permission (Info.plist merge) | Medium | Zero audio captured |
| 4 | Deployment target CoreML differences | Low | Slower/less accurate ANE dispatch |
| 5 | Sandbox file access to model directory | Low | Model fallback |
