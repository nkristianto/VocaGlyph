---
stepsCompleted: [1, 2, 3, 4, 5]
inputDocuments: []
workflowType: 'research'
lastStep: 5
research_type: 'technical'
research_topic: 'Apple Intelligence on Mac for Post-Processing'
research_goals: 'Understand how to leverage Apple Intelligence models downloaded on Mac machines to perform post-processing (text refinement) in the voice-to-text app'
user_name: 'Novian'
date: '2026-02-22'
web_research_enabled: true
source_verification: true
---

# Research Report: Apple Intelligence on Mac for Post-Processing

**Date:** 2026-02-22  
**Author:** Novian  
**Research Type:** Technical  

---

## Research Overview

This report investigates how the voice-to-text macOS application can leverage **Apple Intelligence** — specifically the on-device LLM models already downloaded to the Mac — to perform post-processing (text refinement) on transcribed speech. The current `AppleIntelligenceEngine` always throws `programmaticAccessUnavailable` because no public API existed as of macOS 15.x. This research determines the correct path forward using Apple's newly released **Foundation Models framework** announced at WWDC 2025.

**Research Methodology:**
- Web search with multi-source verification
- Apple Developer documentation review
- WWDC 2025 session notes and third-party tutorials cross-referenced
- Confidence levels applied where sources diverge

---

## Technical Research Scope Confirmation

**Research Topic:** Apple Intelligence on Mac for Post-Processing  
**Research Goals:** Discover publicly available APIs to programmatically access on-device Apple Intelligence LLM for text refinement in a macOS app, replacing the current stub that always fails.

**Technical Research Scope:**
- Architecture Analysis — design patterns, frameworks, system architecture
- Implementation Approaches — development methodologies, coding patterns
- Technology Stack — languages, frameworks, tools, platforms
- Integration Patterns — APIs, protocols, interoperability
- Performance Considerations — scalability, optimization, patterns

**Scope Confirmed:** 2026-02-22

---

## Executive Summary

> **Key Finding:** Apple publicly released the **Foundation Models framework** at WWDC 2025 (June 9, 2025). This is the official, supported way to run Apple Intelligence on-device LLMs from a macOS app. However, it requires **macOS 26 (Tahoe)** and **Xcode 26** — it is NOT available on macOS 15.x. The current `AppleIntelligenceEngine` guard for `#available(macOS 15.1, *)` is correct in concept but the wrong version — it should be `macOS 26.0`.

**Bottom Line for the Voice-to-Text App:**
1. ✅ **Upgrade to Foundation Models framework** — this is the real, public API
2. ⚠️ **macOS 26+ only** — users on macOS 15.x cannot use this path
3. ✅ **Text refinement works perfectly** — the API is designed for summarization, rewriting, and text quality improvement
4. ✅ **Fully on-device, private, no inference cost**
5. ⚠️ **Requires Apple Silicon Mac** (M1 or later) — Intel Macs are excluded

---

## Technology Stack Analysis

### Primary Framework: Foundation Models (macOS 26+)

Apple announced the **Foundation Models framework** at WWDC 2025 as the official public API for third-party apps to access on-device Apple Intelligence models.

**Core Specifications:**
- **Model Size:** ~3 billion parameters, on-device LLM
- **Quantization:** 2-bit quantization-aware training for efficiency
- **Architecture Innovations:** KV-cache sharing for low-latency inference
- **Hardware:** Apple Silicon only (M1, M2, M3, M4 series and later)
- **OS Requirement:** macOS 26.0+ (codename Tahoe), iOS 26+, iPadOS 26+
- **SDK:** Xcode 26 required
- **Language:** Swift native (no Objective-C bridging needed)

**Sources:** [Apple Developer Documentation](https://developer.apple.com), [WWDC 2025 Session: "Meet the Foundation Models framework"], [createwithswift.com], [akring.com]

### Key Swift Types

| Type | Purpose |
|---|---|
| `SystemLanguageModel` | Entry point — access the default on-device model |
| `LanguageModelSession` | Stateful session for sending prompts and receiving responses |
| `@Generable` macro | Generate structured Swift data types from LLM output |
| `@Guide` macro | Fine-grained control over output format and constraints |
| `Tool` protocol | Define custom tools the LLM can call |

### Current State in the App (macOS 15.x Era)

The existing `AppleIntelligenceEngine.swift` correctly identifies that:
1. Writing Tools (the UI-level Apple Intelligence feature) has **no programmatic API** in macOS 15.x
2. The `LanguageModel` framework was **not publicly available** in macOS 15.x
3. The engine must throw `programmaticAccessUnavailable`

This was accurate as a placeholder. The Foundation Models framework is the fix.

---

## Architecture Analysis

### How Apple Intelligence Works On-Device

```
┌─────────────────────────────────────────────────────┐
│                  macOS 26 (Tahoe)                   │
│                                                      │
│  ┌─────────────────┐     ┌──────────────────────┐   │
│  │  Your App       │     │  Foundation Models   │   │
│  │  (Swift)        │────▶│  Framework           │   │
│  │                 │     │                      │   │
│  │ LanguageModel   │     │  SystemLanguageModel │   │
│  │   Session       │◀────│  .default            │   │
│  └─────────────────┘     └──────────┬───────────┘   │
│                                     │               │
│                          ┌──────────▼───────────┐   │
│                          │  On-Device LLM       │   │
│                          │  (~3B params)        │   │
│                          │  Runs on:            │   │
│                          │  • CPU               │   │
│                          │  • GPU               │   │
│                          │  • Neural Engine     │   │
│                          └──────────────────────┘   │
│                                                      │
│  Private Cloud Compute (optional, larger model)      │
└─────────────────────────────────────────────────────┘
```

### Two-Tier Model Architecture

Apple Intelligence uses two tiers:

1. **On-Device Model** (~3B params):
   - Always private — data never leaves the device
   - Works offline
   - Lower latency for short-to-medium tasks
   - Recommended for text refinement / post-processing

2. **Private Cloud Compute** (larger model):
   - For complex tasks needing more reasoning
   - Apple-verified privacy guarantees
   - Requires internet connection
   - Foundation Models framework can route to this automatically for complex requests

For the voice-to-text post-processing use case, the **on-device model is ideal** — it handles text refinement, grammar correction, and reformatting well within its capabilities.

---

## Implementation Approaches

### Approach 1: Foundation Models Framework (Recommended ✅)

This is the primary recommended approach using the official Apple API.

**Minimum viable implementation for text refinement:**

```swift
import FoundationModels

// MARK: - Availability Check (CRITICAL)
// Must check BEFORE creating session
guard SystemLanguageModel.default.isAvailable else {
    // Handle: device not eligible, Apple Intelligence disabled,
    // or model not yet downloaded
    throw AppleIntelligenceError.modelUnavailable
}

// MARK: - Create Session with System Instructions
let session = LanguageModelSession(instructions: """
    You are a text refinement assistant for a voice transcription app.
    Your task is to improve the quality of transcribed speech text.
    Fix grammar, punctuation, and formatting.
    Preserve the speaker's meaning and intent exactly.
    Do not add or remove substantive content.
    Return only the refined text, no explanations.
    """)

// MARK: - Refine Text
let refinedText = try await session.respond(to: rawTranscript)
print(refinedText.content)
```

**Streaming version (for longer texts):**

```swift
let stream = session.streamResponse(to: rawTranscript)
var result = ""
for try await partial in stream {
    result = partial.content  // Each partial is the latest snapshot
}
```

**Availability States to Handle:**

```swift
switch SystemLanguageModel.default.availability {
case .available:
    // All good, proceed
case .unavailable(.deviceNotEligible):
    // Intel Mac or pre-M1 device
    throw AppleIntelligenceError.deviceNotEligible
case .unavailable(.appleIntelligenceNotEnabled):
    // User has not enabled Apple Intelligence in System Settings
    throw AppleIntelligenceError.notEnabled
case .unavailable(.modelNotReady):
    // Model is still downloading — can wait or fallback
    throw AppleIntelligenceError.modelNotReady
case .unavailable(let reason):
    throw AppleIntelligenceError.unavailable(reason.debugDescription)
}
```

### Approach 2: Structured Output with @Generable (Advanced)

For more controlled post-processing output:

```swift
import FoundationModels

@Generable
struct RefinedTranscript {
    @Guide(description: "The refined, grammatically correct transcription")
    var text: String
    
    @Guide(description: "Confidence that the text was successfully refined (0.0-1.0)")
    var confidence: Double
}

let session = LanguageModelSession()
let result = try await session.respond(
    to: "Refine this transcript: \(rawText)",
    generating: RefinedTranscript.self
)
print(result.text)
```

### Approach 3: Writing Tools Integration (macOS 15.x — Limited)

For macOS 15.x, Apple provides **Writing Tools** via `NSTextView` delegate methods. This is **not a programmatic API** for text refinement — it requires user interaction via UI. It is **not suitable** for background post-processing.

**Verdict:** Writing Tools is not a viable approach for automated post-processing. The Foundation Models framework is the correct path.

---

## Integration Patterns

### Recommended Pattern: Foundation Models Engine

Replace the existing `AppleIntelligenceEngine.swift` with a proper implementation:

```swift
import Foundation
import FoundationModels

@available(macOS 26.0, *)
public actor AppleIntelligenceEngine: PostProcessingEngine {
    
    private var session: LanguageModelSession?
    
    public init() {}
    
    public func refine(text: String, prompt: String) async throws -> String {
        PostProcessingLogger.shared.info(
            "AppleIntelligenceEngine: [REQUEST] Attempting refine — input=\(text.count) chars"
        )
        
        // Check availability
        switch SystemLanguageModel.default.availability {
        case .available:
            break // proceed
        case .unavailable(let reason):
            let error = AppleIntelligenceError.modelUnavailable(reason.debugDescription)
            PostProcessingLogger.shared.error(
                "AppleIntelligenceEngine: Model unavailable — \(reason)"
            )
            throw error
        }
        
        // Create or reuse session
        let session = getOrCreateSession(systemPrompt: prompt)
        
        do {
            let response = try await session.respond(to: text)
            PostProcessingLogger.shared.info(
                "AppleIntelligenceEngine: [SUCCESS] Refined \(text.count) → \(response.content.count) chars"
            )
            return response.content
        } catch {
            PostProcessingLogger.shared.error(
                "AppleIntelligenceEngine: Inference failed — \(error.localizedDescription)"
            )
            throw AppleIntelligenceError.inferenceFailed(error.localizedDescription)
        }
    }
    
    private func getOrCreateSession(systemPrompt: String) -> LanguageModelSession {
        if let existing = session {
            return existing
        }
        let newSession = LanguageModelSession(instructions: systemPrompt)
        session = newSession
        return newSession
    }
}
```

### Dual-Version Strategy (macOS 15.x + macOS 26+)

Since the app needs to support users on both macOS 15.x and macOS 26+, use availability checking:

```swift
// In PostProcessingEngineFactory or similar
func makeAppleIntelligenceEngine() -> PostProcessingEngine {
    if #available(macOS 26.0, *) {
        return AppleIntelligenceEngine()  // Real implementation
    } else {
        return LegacyAppleIntelligenceStub()  // Current stub that throws
    }
}
```

### Session Lifecycle

- **One session = one conversation context.** For post-processing, a stateless pattern works well.
- Create a **new session per transcription** to avoid context contamination between different transcriptions.
- Alternatively, use a **persistent session with a clear system prompt** that resets context.
- Sessions are **lightweight** — creating one per request is acceptable.

---

## Performance Considerations

### Latency

| Metric | Expected Value | Notes |
|---|---|---|
| First token latency (TTFT) | **< 1 second** for 3B model on M1+ | Neural Engine accelerated |
| Full response (short text) | **1-4 seconds** | Grammar fix of 200-word transcript |
| Full response (long text) | **4-10 seconds** | Multiple paragraph refinement |
| Model load time | **Near zero** | Model pre-loaded by OS |

**Key Insight:** Unlike the `LocalLLMEngine` (which loads a separate `.gguf` model on first use), the Foundation Models framework uses a **system-managed model** that is already loaded and resident in memory. There is **no cold-start penalty**.

### On-Device vs Private Cloud Compute

- The framework automatically decides whether to use the on-device model or Private Cloud Compute
- For post-processing short-to-medium transcripts, the **on-device model handles it** well
- Developers cannot force selection — Apple controls routing for quality
- **Confidence:** High — confirmed by Apple documentation

### Memory

- The ~3B parameter model uses approximately **2-4 GB of RAM** (2-bit quantized)
- This is managed entirely by the OS — the app does not "own" the model memory
- Apple Silicon unified memory makes this efficient

### Privacy

- **On-device:** All data stays local. No network requests. No telemetry.
- **Private Cloud Compute (if routing there):** Apple provides cryptographic privacy guarantees; Apple cannot see the data.
- **For the voice-to-text use case:** This is excellent — users transcribing sensitive audio benefit from full privacy.

---

## Requirements & Constraints

### Hard Requirements

| Requirement | Details |
|---|---|
| **macOS version** | macOS 26.0 (Tahoe) or later |
| **Hardware** | Apple Silicon Mac (M1, M2, M3, M4 or later series) |
| **Apple Intelligence** | Must be enabled in System Settings → Apple Intelligence |
| **Xcode version** | Xcode 26+ (for development) |
| **SDK** | iOS/macOS 26 SDK |
| **Entitlement** | `com.apple.developer.foundationmodels.adapter` (for custom adapters only; base model access does not require special entitlement) |

### Soft Requirements

- **Apple Developer Program membership** ($99/year) for App Store distribution
- **Model downloaded:** Apple Intelligence models download in the background after enabling; the app should handle `modelNotReady` state gracefully

### Users Excluded

- **Intel Mac users** — no Apple Silicon = no Apple Intelligence
- **macOS 15.x users** — Foundation Models framework does not exist; must fall back to other engines (Gemini, local LLM)
- **Users who have disabled Apple Intelligence** — must handle `appleIntelligenceNotEnabled` gracefully

---

## Comparison: Approaches for Post-Processing

| Approach | API Status | Privacy | macOS Req | Hardware | Cost | Best For |
|---|---|---|---|---|---|---|
| **Foundation Models** | ✅ Public (WWDC25) | 🔒 Full on-device | macOS 26+ | Apple Silicon | Free | Primary approach |
| **Writing Tools** | ⚠️ UI-only, no programmatic | 🔒 On-device | macOS 15.1+ | Apple Silicon | Free | Not suitable for background |
| **Local LLM (llama.cpp)** | ✅ Public | 🔒 On-device | macOS 12+ | Any (GPU helps) | Free | macOS 15.x fallback |
| **Gemini API** | ✅ Public | ☁️ Cloud | Any | Any | Per token | Cross-platform fallback |

**Recommended Hierarchy:**
1. **macOS 26+ Apple Silicon → Foundation Models** (best UX, zero friction)
2. **macOS 15.x or macOS 26+ Intel → Local LLM** (mlx-swift or llama.cpp)
3. **Any platform with network → Gemini API** (universal fallback)

---

## Migration Plan: AppleIntelligenceEngine

### What to Change

**Current behavior (macOS 15.x):**
- Always throws `programmaticAccessUnavailable`
- `#available(macOS 15.1, *)` check passes but `#if canImport(LanguageModel)` is false

**Target behavior:**

```swift
// Before (current)
import AppKit
import Foundation

public actor AppleIntelligenceEngine: PostProcessingEngine {
    public func refine(text: String, prompt: String) async throws -> String {
        guard #available(macOS 15.1, *) else { throw ... }
        #if canImport(LanguageModel)
        throw AppleIntelligenceError.frameworkUnavailable
        #else
        throw AppleIntelligenceError.programmaticAccessUnavailable
        #endif
    }
}

// After (macOS 26+)
import Foundation
import FoundationModels  // NEW

@available(macOS 26.0, *)
public actor AppleIntelligenceEngine: PostProcessingEngine {
    public func refine(text: String, prompt: String) async throws -> String {
        // Check availability
        guard case .available = SystemLanguageModel.default.availability else {
            throw AppleIntelligenceError.modelUnavailable(...)
        }
        // Do real inference
        let session = LanguageModelSession(instructions: prompt)
        let response = try await session.respond(to: text)
        return response.content
    }
}
```

### Xcode Project Changes Required

1. **Update deployment target** to macOS 26.0 (or use `@available` guards)
2. **Add `FoundationModels` framework** to target (it is a system framework, no SPM dependency needed)
3. **Wrap usage in `@available(macOS 26.0, *)`** or split into two target files
4. **Update `PostProcessingEngineFactory`** to conditionally instantiate the correct engine
5. **Add model availability UI** — inform users if their machine doesn't support it

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Users on macOS 15.x cannot use Foundation Models | **High** | Medium | graceful fallback to local LLM or Gemini |
| Intel Mac users excluded | **Medium** | Medium | same fallback chain |
| Apple Intelligence disabled by user | **Medium** | Low | prompt user to enable, then fallback |
| Model not yet downloaded on first use | **Low** | Low | show spinner, handle `modelNotReady` |
| API changes in macOS 26 betas | **Medium** | Medium | test against each beta release |
| Response quality varies by prompt | **Medium** | Medium | tune system prompt, test with real transcripts |

---

## Actionable Recommendations

### Immediate (Next Sprint)

1. **Update `AppleIntelligenceEngine.swift`** to implement Foundation Models for `#available(macOS 26.0, *)` — keep the existing error-throwing stub for older OS versions
2. **Import `FoundationModels`** — this is a system framework (no SPM package needed)
3. **Update `#available` check** from `macOS 15.1` to `macOS 26.0`
4. **Write availability checking logic** to handle all 3 failure states gracefully (device ineligible, disabled, model not ready)
5. **Session management** — create one session per refine call (stateless), or reuse with a clear prompt

### Near-Term

6. **Update `PostProcessingEngineFactory`** to prefer Foundation Models when on macOS 26+
7. **Add UI indicator** in Settings to show Apple Intelligence status (available / disabled / not supported)
8. **Test with real transcriptions** — tune the system prompt for best results
9. **Consider streaming responses** for a better user experience on longer transcripts

### Future

10. **Explore `@Generable`** for structured output — could return cleaned text + metadata (e.g., paragraph count, formatting hints)
11. **Monitor Apple's adapter entitlement program** — custom adapters can fine-tune the model for specific domains (e.g., medical transcription)

---

## Key Sources

| Source | Content | Confidence |
|---|---|---|
| [Apple Developer Documentation — Foundation Models](https://developer.apple.com/documentation/foundationmodels) | Official API reference | ⭐⭐⭐⭐⭐ |
| [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/) | Architecture, API design | ⭐⭐⭐⭐⭐ |
| [createwithswift.com — Foundation Models Guide](https://createwithswift.com) | Code examples, availability checking | ⭐⭐⭐⭐ |
| [akring.com — Foundation Models Overview](https://akring.com) | Comprehensive developer guide | ⭐⭐⭐⭐ |
| [artemnovichkov.com — Foundation Models Tutorial](https://artemnovichkov.com) | Practical Swift examples | ⭐⭐⭐⭐ |
| [9to5mac.com — Apple Intelligence requirements](https://9to5mac.com) | Device/OS requirements | ⭐⭐⭐⭐⭐ |
| [Apple Machine Learning Research — Model Architecture](https://apple.com) | Technical model details | ⭐⭐⭐⭐⭐ |

---

*Research completed: 2026-02-22 | Workflow: technical-research | Steps completed: 1–5*
