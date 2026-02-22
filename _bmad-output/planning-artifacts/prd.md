---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
  - step-03-success
  - step-04-journeys
  - step-06-innovation
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
inputDocuments:
  - _bmad-output/brainstorming/brainstorming-session-2026-02-21.md
  - _bmad-output/planning-artifacts/research/technical-llm-integration-research-2026-02-21.md
workflowType: 'prd'
classification:
  projectType: desktop_app
  domain: general
  complexity: low
  projectContext: brownfield
---

# Product Requirements Document - voice-to-text

**Author:** Novian
**Date:** 2026-02-21T19:54:44+07:00

## Executive Summary

VocaGlyph is a multi-tiered, intelligent dictation pipeline. It features a "Dynamic Model Juggler" to route audio and text through specialized models based on the task. It strictly separates raw transcription (using models like Parakeet for high accuracy) from post-processing text refinement (using Apple Intelligence or cloud APIs for grammar and rephrasing). 

### What Makes This Special

VocaGlyph provides an "Open Model Sandbox" that separates transcription from post-processing. It prioritizes absolute accuracy and privacy through local execution while offering frictionless text polish, treating LLMs as swappable, transparent utilities rather than opaque systems.

## Project Classification

| Attribute | Value |
|-----------|-------|
| **Project Type** | Desktop App (macOS native, AppKit + SwiftUI) |
| **Domain** | General / Local AI Tooling |
| **Complexity** | Low |
| **Context** | Brownfield (Adding LLM Post-Processing Pipeline) |
| **Primary User** | Power users wanting transparent, highly-accurate dictation toolkits |

## Success Criteria

### User Success
Users can seamlessly dictate text with high accuracy using Parakeet and have it automatically rephrased or grammar-corrected by Apple Intelligence (or a cloud API) before being pasted into their active application, without needing to manually copy/paste or switch contexts.

### Business Success
The application successfully supports a multi-tiered LLM pipeline without introducing significant latency or user confusion, maintaining its core value proposition of being a fast, private, and frictionless dictation tool.

### Technical Success
- **Routing:** Implementation of a strict `LanguageModel` protocol that abstracts MLX, Apple Intelligence, and API backends.
- **Latency:** Post-processing via Apple Intelligence or APIs adds no more than 1-2 seconds of perceived latency to the dictation loop.
- **Accuracy:** Core transcription relies exclusively on optimized models (like Parakeet) to guarantee baseline text quality before post-processing.
- **Stability:** The app must gracefully handle API timeouts or missing local models by falling back to raw transcription insertion.

### Measurable Outcomes
- `LanguageModel` protocol is implemented and can hot-swap between at least two backends (e.g., Parakeet for transcription, Apple Intelligence for post-processing).
- The settings UI successfully exposes the "Open Model Sandbox" controls.

## Product Scope

### MVP - Minimum Viable Product
- Integration of Parakeet via `mlx-swift` for core transcription.
- Integration of Apple Intelligence (Foundation Models) for default, zero-download post-processing (grammar/rephrasing).
- "Dynamic Model Juggler" architecture allowing separate models for Transcription vs. Post-Processing.
- Settings UI to toggle post-processing on/off and select the engine.

### Growth Features (Post-MVP)
- Integration of custom/API-based LLMs (Gemini, Anthropic, Qwen via Llama.cpp) as alternative post-processing engines in the sandbox.
- Custom prompts for the post-processing engine (e.g., "translate to Spanish", "make this sound professional").

### Vision (Future)
- Fully automated contextual routing (e.g., detecting if the active app is Xcode and automatically applying a code-formatting prompt to the LLM).

## User Journeys

### Journey 1: The Core Dictation Loop (WhisperKit Default)
**Novian wants the fastest, lightest raw dictation.**
1. Presses global hotkey (`⌃Space`) — the minimalist HUD appears.
2. Speaks naturally.
3. Presses hotkey to stop.
4. **VocaGlyph** detects a CoreML model is selected and immediately transcribes the audio locally using the **WhisperKit** engine.
5. The raw text is pasted into the active application within 500ms.

### Journey 2: High-Accuracy Dictation (Automatic Parakeet Switch)
**Novian is dictating a complex, technical document and needs the highest possible accuracy.**
1. Opens Settings and selects the "Parakeet (GGUF)" model from the available model list.
2. Presses global hotkey and speaks, using domain-specific technical jargon.
3. **VocaGlyph** detects the GGUF model type and *automatically* routes the audio through the MLX-Swift engine.
4. The transcription, powered by Apple Silicon's Unified Memory, is pasted into the active application.

### Journey 3: The Enhanced Context Pipeline (Apple Intelligence Post-Processing)
**Novian wants to dictate a complex thought and have it polished.**
1. Toggles **"Enable Post-Processing"** to ON in Settings.
2. Selects the engine as "Apple Intelligence" and sets a prompt (e.g., "Fix grammar").
3. Activates hotkey, speaks, stops.
4. VocaGlyph transcribes via the chosen Transcription Model (WhisperKit or MLX automatically).
5. It then passes that text to the macOS 15.1 Foundation Models framework (Apple Intelligence).
6. The polished text is synthetic-pasted into the app.

### Journey 4: The Power User Sandbox (External API Post-Processing)
**Novian wants to translate dictation or use an external API for heavy NLP lifting.**
1. In Settings, changes the "Post-Processing Engine" from Apple Intelligence to a Cloud API (e.g., Gemini or Anthropic).
2. Sets a custom prompt: "Translate whatever I say into professional business Spanish."
3. Activates hotkey, speaks in English.
4. VocaGlyph transcribes the audio locally (via WhisperKit or MLX), and dynamically offloads the post-processing task to the Gemini API.
5. Perfect Spanish is pasted into the email client.

### Journey Requirements Summary

| Capability                         | Required For                                    |
| ---------------------------------- | ----------------------------------------------- |
| **(Existing)** WhisperKit Engine   | Journey 1 (Transcription via CoreML)            |
| MLX-Swift Engine (Parakeet/Alala)  | Journey 2 (Transcription via GGUF)              |
| Automatic Engine Routing Logic     | Journeys 1, 2 (Switches based on model type)    |
| Apple Intelligence macOS 15.1 API  | Journey 3 (Post-Processing Default)             |
| Cloud API Integration (Gemini/Anthropic) | Journey 4 (Post-Processing Alternative)         |
| Post-Processing Selection UI       | Journeys 3, 4                                   |
| **(Existing)** Paste-to-active-app | All Journeys                                    |

## Innovation & Novel Patterns

### Detected Innovation Areas
- **The "Dynamic Model Juggler" Architecture**: A novel approach to local LLM orchestration where the application acts as a smart router. It deliberately decouples the *Transcription Engine* (optimized for speed/accuracy via WhisperKit CoreML or MLX-Swift GGUF models) from the *Post-Processing Engine* (optimized for language logic via Apple Intelligence or Cloud APIs). 
- **The "Open Model Sandbox"**: Reversing the industry trend of opaque, monolithic AI features by exposing the processing pipeline directly to the power user, allowing them to hot-swap local memory-mapped models with Cloud APIs on the fly depending on battery constraints or privacy needs.

### Market Context & Competitive Landscape
Current market leaders (like standard dictation apps or even OS-level tools) either rely solely on closed-source cloud APIs (high latency, low privacy) or single-model local inference (high privacy, low intelligence for complex rephrasing). VocaGlyph pioneers a hybrid edge-compute approach natively on Apple Silicon, offering the best of both worlds without the bloat of an Electron wrapper.

### Validation Approach
- **Technical Validation**: Benchmark TTFT (Time-to-First-Token) and overall memory pressure when rapidly switching between the `WhisperService` and an MLX-Swift `LanguageModel` implementation.
- **User Validation**: Test if the latency introduced by the Apple Intelligence post-processing step (Journey 3) breaks the user's workflow compared to the instant raw dictation (Journey 1).

### Risk Mitigation
- **Risk**: The "Model Juggler" introduces too much latency or RAM overhead.
- **Mitigation**: Implement aggressive model unloading/eviction in memory, and ensure Journey 1 (WhisperKit purely) remains the default, guaranteed-fast fallback if the post-processing pipeline times out.

## Desktop App Specific Requirements

### Project-Type Overview
VocaGlyph is a native macOS desktop application designed to run persistently in the background (Accessory mode) with ultra-low resource utilization. It relies entirely on local execution and synthetic OS events rather than cloud services or user-facing windows.

### Technical Architecture Considerations

- **Platform Support**: Exclusively macOS 14+ / Apple Silicon (M-series) due to the heavy reliance on unified memory for MLX, `WhisperKit` CoreML optimization, and `macOS 15.1 Foundation Models`.
- **System Integration**: 
  - Requires **Accessibility Permissions** to use `CGEvent` for global hotkey registration and synthetic keyboard pasting into the active application.
  - Requires **Microphone Permissions** via `AVFoundation`.
- **Offline Capabilities**: 100% functional offline for CoreML and MLX transcription. Apple Intelligence varies based on OS-level model availability. Cloud APIs (Journey 4) naturally require a connection.
- **Update Strategy**: standard manual app updates or via Sparkle (if distributed outside the Mac App Store), though initial MVP is local/manual build.

### Implementation Considerations
- **Memory Management**: Critical. `WhisperService` (CoreML) and `LanguageModel` (MLX/GGUF) must run isolated in `actors` on background threads to prevent main thread blocking. Aggressive model eviction is required when toggling between engines.
- **UI Paradigm**: No traditional Dock icon or main window. Interactions occur via an `NSStatusItem` (Menu Bar), a floating `NSPanel` (for the recording HUD), and a SwiftUI-based Settings Window.

## Project Scoping & Phased Development

### MVP Strategy & Philosophy
**MVP Approach:** *Experience-first MVP.* The core value is frictionless, private dictation. We must prove that local AI (via MLX and CoreML) can rival cloud speed without the privacy tradeoff, and that Apple Intelligence can add intelligent polish without breaking the user flow.
**Resource Requirements:** Solo developer (Novian) with heavy reliance on existing Swift packages (`mlx-swift`, `WhisperKit`) to accelerate development.

### MVP Feature Set (Phase 1)
**Core User Journeys Supported:**
- Journey 1: Core Dictation (WhisperKit) -> Paste
- Journey 2: High-Accuracy Dictation (Parakeet/MLX) -> Paste
- Journey 3: Pipeline Dictation (Transcription + Apple Intelligence Polish) -> Paste

**Must-Have Capabilities:**
- Global hotkey listener and OS-level synthetic pasting (`CGEvent`).
- Minimalist floating recording HUD (AppKit/SwiftUI).
- `WhisperService` implementation for `WhisperKit` CoreML models (existing).
- `LanguageModel` protocol and `MLXService` implementation for Parakeet (GGUF).
- Foundation Models integration for basic post-processing (grammar/rephrasing).
- Settings View to toggle post-processing on/off and select the transcription model.

### Post-MVP Features
**Phase 2 (Growth - The Sandbox):**
- Implementation of the Cloud API backend (Journey 4) to support Gemini and Anthropic.
- Custom user-defined prompts for the post-processing step (e.g., translation, summarization).
- Visual feedback in the HUD indicating which engine is currently processing.

**Phase 3 (Expansion):**
- Automated Contextual Routing (detecting the active app and applying a specific prompt, like formatting code for Xcode vs writing prose for Mail).

### Risk Mitigation Strategy
- **Technical Risks:** MLX integration causing memory spikes or blocking the main thread. *Mitigation:* Strict isolation using Swift `actors` and prioritizing the existing `WhisperKit` implementation as the stable default.
- **Market Risks:** Apple Intelligence limits API usage or introduces too much latency. *Mitigation:* The core app functions perfectly offline with 0 latency using just the transcription engine. Apple Intelligence is strictly an opt-in *enhancement*, not a dependency.
- **Resource Risks:** Solo developer bandwidth constraints. *Mitigation:* Push all Cloud API integrations (OAuth, API key management, networking code) to Phase 2 to drastically simplify the MVP scope.

## Functional Requirements

### 1. Global Activation & Feedback
- **FR1:** Users can start and stop dictation globally via a customizable hotkey.
- **FR2:** Users receive visual feedback indicating the current system state (Listening, Processing, Inactive).
- **FR3:** Users can manually cancel an active dictation session via the visual interface.
- **FR4:** Users receive visual feedback identifying the currently active processing engine.

### 2. Audio Capture & Transcription
- **FR5:** System captures voice input while dictation is active.
- **FR6:** System converts spoken audio to text locally using a designated high-efficiency model (e.g., CoreML).
- **FR7:** System converts spoken audio to text locally using a designated high-accuracy model (e.g., GGUF).

### 3. Engine Orchestration & Post-Processing
- **FR8:** Users can enable or disable automated text post-processing.
- **FR9:** System can refine transcribed text using native OS intelligence frameworks (e.g., Apple Intelligence).
- **FR10:** System can refine transcribed text using user-selected local open models (e.g., Qwen) for offline processing.
- **FR11:** System can refine transcribed text using configured external cloud APIs.
- **FR12:** Users can define custom instructions (prompts) that govern how post-processing modifies the text.
- **FR13:** System outputs raw transcription if the post-processing engine fails or times out.

### 4. Text Output
- **FR14:** System inserts final processed text directly into the previously focused application at the cursor position.

### 5. Application Configuration
- **FR15:** Users can access application settings via a persistent system menu.
- **FR16:** Users can select their active transcription model from available local models.
- **FR17:** Users can select their active post-processing engine.
- **FR18:** Users can securely store API credentials for cloud-based engines.
- **FR19:** Users can configure the application to launch automatically on system startup.

## Non-Functional Requirements

### Performance & Latency
- **NFR1 (Startup):** The application must be ready to receive audio within 100ms of the global hotkey being pressed, ensuring the user's first spoken word is never truncated.
- **NFR2 (Raw Transcription latency):** The Time-to-First-Token (TTFT) for local MLX or CoreML transcription must not exceed 500ms on an Apple M1 base model.
- **NFR3 (Pipeline Latency):** When post-processing is enabled (via Apple Intelligence or local Qwen), the total perceived latency from the end of speech to pasting text must not exceed 1.5 seconds under normal system load.
- **NFR4 (Memory Footprint):** The background process (when inactive) must consume less than 100MB of RAM. Models must be aggressively evicted from active memory when not in use for >5 minutes to prevent system bloat.

### Security & Privacy
- **NFR5 (Local First):** Core transcription (WhisperKit/MLX) and local post-processing (Apple Intelligence/Qwen) must execute 100% on-device with zero network requests. The application must function completely with macOS Wi-Fi disabled.
- **NFR6 (Ephemeral Data):** Audio recordings must be held only in volatile memory (RAM) during processing and immediately destroyed after transcription. No audio files are ever written to disk.
- **NFR7 (API Key Storage):** External API keys (for Gemini/Anthropic) must be stored securely in the macOS Keychain, never in plaintext configuration files.

### Reliability
- **NFR8 (Graceful Degradation):** If a Cloud API takes longer than 2000ms to respond for post-processing, the system must automatically abort the network request and immediately paste the raw transcribed text instead, preventing UX lockup.
