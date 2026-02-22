# VocaGlyph

> A native macOS dictation app that transcribes your voice and pastes the result anywhere — instantly, privately, and with optional AI refinement.

VocaGlyph lives in your menu bar. Press a hotkey, speak, release — and your words appear in whatever app has focus.

---

## Features

### 🎙️ Voice-to-Text Transcription

VocaGlyph supports two transcription backends that can be switched without restarting the app:

| Engine | Description |
|---|---|
| **Apple Native Speech** | Uses macOS 15+ on-device speech recognition. Zero setup, instant results. |
| **WhisperKit (OpenAI Whisper)** | Local CoreML models from `argmaxinc/whisperkit-coreml`. Higher accuracy, larger models. |

**Supported Whisper model variants** include standard OpenAI Whisper sizes (e.g. `large-v3`, `large-v3_turbo`) and `distil-whisper` variants. Models are downloaded and managed directly from the Settings window.

All transcription is done entirely on-device — no audio is ever sent to the cloud.

---

### ⌨️ Configurable Global Hotkey

Trigger dictation from any app using a system-wide hotkey. Available presets:

- `⌃ ⇧ C` (default)
- `⌥ Space`
- `⌘ ⇧ Space`
- `⌃ Space`

Hold the hotkey to record, release to transcribe. A debounce guard prevents accidental double-triggers.

---

### 📋 Smart Output

After transcription completes, VocaGlyph:

1. **Copies** the result to the system clipboard.
2. **Simulates Cmd+V** via CGEvent to paste directly into the focused app (requires Accessibility permission).
3. **Plays a subtle sound** (`Pop`) to confirm success.

Optionally, **filler word removal** strips common conversational words (`um`, `uh`, `ah`, `like`, `you know`) before pasting.

---

### 🌐 Multi-Language Dictation

Choose a primary language in Settings or let Whisper auto-detect from audio:

- Auto-Detect (default)
- English (US)
- Spanish (ES)
- French (FR)
- German (DE)
- Indonesian (ID)

---

### 🤖 AI Post-Processing *(Experimental)*

After transcription, an optional AI pass can fix grammar, punctuation, and capitalization before pasting. Three engine options are available:

#### Apple Intelligence (macOS 26+ / Tahoe)
Uses the on-device Foundation Models framework (~3B parameter model). Fully private, no network required, no cold-start — the OS keeps the model loaded.

> **Requirements:** Apple Silicon Mac (M1+), macOS 26 (Tahoe), Apple Intelligence enabled in System Settings.

#### Local AI (MLX / Qwen)
Runs an open-source LLM locally via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift). The default model is `mlx-community/Qwen2.5-7B-Instruct-4bit`. Models are downloaded from HuggingFace and cached in `~/.VocaGlyph/models/`.

- **Background warm-up**: The model is preloaded into Unified Memory on launch so your first dictation has no delay.
- **Memory management**: Free model memory or delete downloaded files directly from Settings.
- Supports any Qwen-style chat model (including thinking models — `<think>` blocks are automatically stripped).

#### Cloud API
Sends transcription text to a cloud AI provider for refinement. Supported providers:

| Provider | Model |
|---|---|
| **Google Gemini** | Gemini API |
| **Anthropic Claude** | Claude API |

API keys are stored securely in the **macOS Keychain** — never in plaintext or `UserDefaults`.

#### Custom Prompt
All three post-processing engines accept a configurable system prompt so you can tailor the refinement behaviour (e.g. "Fix grammar only", "Translate to formal English", "Return bullet points").

#### Safety Guardrails
Post-processing output is validated before use:
- **Refusal detection** — if the model refuses to respond, the raw transcription is used instead.
- **Hallucination gate** — output that is 3× longer than the input is discarded.
- **Silence detection** — known Whisper phantom phrases (e.g. "Thank you for watching", `[BLANK_AUDIO]`) are silently dropped, producing no output.

---

### 📜 Transcription History

Every successful dictation is persisted locally using **SwiftData**. The History tab in Settings lets you browse and review past transcriptions. Items older than **30 days** are automatically cleaned up.

---

### 🖥️ Recording Overlay HUD

A floating overlay panel appears on screen while recording and processing, giving clear visual feedback of the current state:

| State | Menu Bar Icon |
|---|---|
| Idle | App icon |
| Initializing | `gearshape.fill` (yellow) |
| Recording | `waveform.circle.fill` (red) |
| Processing | `hourglass.circle.fill` (orange) |

---

### ⚙️ Settings Window

A full-featured native macOS settings window with four tabs:

- **General** — hotkey, language, auto-punctuation, filler word removal, launch at login, debug logging.
- **Model** — download, switch, and delete Whisper models with per-model download progress.
- **Post-Processing** — enable/disable AI refinement, choose engine, manage API keys, set custom prompt.
- **History** — browse and search past transcriptions.

---

### 🔒 Privacy & Permissions

VocaGlyph requests only the permissions it needs:

| Permission | Purpose |
|---|---|
| **Microphone** | Capture audio for transcription |
| **Accessibility** | Simulate Cmd+V to paste text |
| **Speech Recognition** (Apple Native) | Use on-device Speech framework |

An onboarding flow walks new users through granting each permission before the app initialises.

---

### 🚀 System Integration

- **Menu bar app** — no Dock icon, no Cmd+Tab entry.
- **Launch at Login** — register/unregister via `SMAppService` directly from Settings with a single toggle.
- **Debug Logging** — a structured log file is written to disk when enabled, and can be revealed in Finder from Settings.

---

## Requirements

| Component | Minimum |
|---|---|
| macOS | 15.0 (Sequoia) |
| Apple Silicon | Recommended (required for Apple Intelligence & Local AI) |
| Xcode | 16+ (Xcode 26 for Apple Intelligence engine) |

---

## Architecture Overview

```
VocaGlyph/
├── App/
│   ├── AppDelegate.swift        # Menu bar, window setup, service wiring
│   └── AppStateManager.swift    # Central state machine (idle → recording → processing)
├── Engines/
│   ├── Transcription/
│   │   ├── NativeSpeechEngine   # macOS Speech framework
│   │   ├── WhisperService       # WhisperKit CoreML wrapper
│   │   └── EngineRouter         # Hot-swappable engine dispatch
│   └── PostProcessing/
│       ├── AppleIntelligenceEngine  # Foundation Models (macOS 26+)
│       ├── LocalLLMEngine           # MLX on-device LLM
│       ├── GeminiEngine             # Google Gemini API
│       └── AnthropicEngine          # Anthropic Claude API
├── Services/
│   ├── AudioRecorderService     # AVAudioEngine capture
│   ├── HotkeyService            # CGEvent global hotkey tap
│   ├── OutputService            # Clipboard + CGEvent paste
│   ├── KeychainService          # Secure API key storage
│   ├── PermissionsService       # Permission checks
│   └── LoggerService            # Unified file logger
├── UI/
│   ├── Settings/                # SwiftUI settings window
│   └── HUD/                     # Floating recording overlay
└── Domain/
    ├── Protocols.swift          # TranscriptionEngine, PostProcessingEngine
    └── TranscriptionItem.swift  # SwiftData model for history
```
