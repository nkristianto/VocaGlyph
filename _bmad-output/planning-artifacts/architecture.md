---
stepsCompleted: [step-01-init, step-02-context]
inputDocuments: [_bmad-output/planning-artifacts/prd.md]
workflowType: 'architecture'
project_name: 'voice-to-text'
user_name: 'Novian'
date: '2026-02-20'
---

# Architecture Decision Document — voice-to-text

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

---

## Project Context Analysis

### Requirements Overview

**Functional Requirements (FR1–FR26):**
26 FRs across 6 capability areas: Recording & Audio Capture, Transcription, Text Output, Model Management, Settings & Configuration, Application Lifecycle. Well-scoped for a single-user personal MVP.

**Non-Functional Requirements driving architecture:**
- **< 500ms transcription latency** → whisper.cpp must run in a background goroutine; audio pipeline must be zero-copy
- **< 200MB RAM** → model loaded once and reused; no Electron-style overhead
- **100% offline** → no network code in the runtime hot path
- **Audio never written to disk** → in-memory buffer pipeline only
- **Accessibility API for paste** → macOS-native CGo bridge or `osascript` required

**Scale & Complexity:**
- Primary domain: macOS Native Desktop / Local AI Inference
- Complexity level: Medium
- No multi-tenancy, no cloud, no auth, no database — single-user binary
- Estimated architectural components: ~6 (Audio, Whisper, IPC/Wails, UI, Settings, OS Integration)

### Technical Constraints & Dependencies

| Constraint | Implication |
|-----------|-------------|
| Wails (Go + WebKit) | Go backend communicates with React frontend via Wails runtime IPC |
| whisper.cpp | Requires CGo bridge or subprocess; CGo eliminates latency vs subprocess |
| macOS Accessibility API | Required for paste-to-active-app; CGo or `osascript` fallback |
| Global hotkey (system-wide) | Requires CGo or a Go library (e.g. `robotgo`, `keybd_event`) |
| Apple Silicon primary | Enable `GGML_METAL=1` in whisper.cpp build for GPU acceleration |

### Cross-Cutting Concerns Identified

- **Concurrency**: Audio capture, whisper inference, UI updates — separate goroutines with clean channels; never block Wails UI thread
- **Permission management**: Microphone + Accessibility must be requested gracefully with fallback messaging
- **Error handling**: Paste failure → clipboard fallback must be deterministic
- **Settings hot-reload**: Model swap and hotkey rebind must not require restart

---

## Technology Stack & Starter

### Primary Technology Domain

macOS Native Desktop App with Local AI Inference — Go backend + React frontend via Wails framework.

### Initialization Command

```bash
# Install Wails CLI
go install github.com/wailsapp/wails/v2/cmd/wails@latest

# Scaffold project
wails init -n voice-to-text -t react
```

### Architectural Decisions from Stack

| Layer | Decision | Rationale |
|-------|----------|-----------|
| **App Framework** | Wails v2 | Lean native binary; uses macOS WebKit (not Chromium); Go backend, React frontend |
| **Backend Language** | Go 1.22+ | Strong concurrency primitives, simple CGo interface, large standard library |
| **Frontend** | React + Vite | Wails default template; fast HMR; familiar JS ecosystem |
| **Whisper Integration** | `github.com/ggerganov/whisper.cpp` Go bindings (CGo) | Official bindings; best latency; Core ML support on Apple Silicon |
| **Whisper Acceleration** | Core ML (`-DWHISPER_COREML=1`) + Metal | Offloads to Apple Neural Engine; critical for < 500ms target |
| **Audio Capture** | `github.com/gordonklaus/portaudio` (Go bindings) | Cross-platform audio I/O; battle-tested; supports PortAudio on macOS |
| **Global Hotkey** | `github.com/micmonay/keybd_event` or `robotgo` | System-wide hotkey without CGo complexity; evaluate both |
| **Paste-to-App** | `osascript` subprocess → CGo Accessibility API fallback | `osascript` is simpler; CGo AX API for precision; detect failure and fallback to clipboard |
| **Settings Storage** | JSON file in `~/Library/Application Support/voice-to-text/` | Simple, transparent, no database needed for a single-user tool |
| **Model Storage** | `~/Library/Application Support/voice-to-text/models/` | Standard macOS app data location; survives app updates |

---

## Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    macOS Menu Bar App                    │
│                                                          │
│  ┌──────────────┐    ┌─────────────────────────────┐    │
│  │  React UI    │◄──►│      Wails IPC Bridge        │    │
│  │  (WebKit)    │    │  (Go methods → JS bindings)  │    │
│  └──────────────┘    └──────────────┬───────────────┘    │
│                                     │                    │
│         ┌───────────────────────────┼──────────────┐    │
│         │                           │              │    │
│  ┌──────▼──────┐  ┌─────────────────▼──┐  ┌───────▼──┐ │
│  │  Hotkey     │  │   Audio Service    │  │ Settings  │ │
│  │  Manager   │  │  (PortAudio/CGo)   │  │  Service  │ │
│  │  (robotgo) │  └─────────┬──────────┘  └──────────┘ │
│  └─────────────┘           │                           │
│                    ┌───────▼──────────┐                 │
│                    │  Whisper Service │                 │
│                    │  (CGo bindings   │                 │
│                    │   + Core ML)     │                 │
│                    └───────┬──────────┘                 │
│                            │                            │
│                    ┌───────▼──────────┐                 │
│                    │  Output Service  │                 │
│                    │  (osascript /    │                 │
│                    │   Clipboard CGo) │                 │
│                    └──────────────────┘                 │
└─────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **Wails IPC Bridge** | Exposes Go methods to React; handles bidirectional events; never blocks |
| **Hotkey Manager** | Registers/deregisters system-wide hotkeys; sends `RecordStart`/`RecordStop` events via channel |
| **Audio Service** | Captures PCM audio from default microphone into an in-memory ring buffer; no disk I/O |
| **Whisper Service** | Loads `.ggml` model once at startup; accepts audio buffer; returns transcription string |
| **Output Service** | Attempts `osascript` paste; on failure copies to clipboard and emits notification event to UI |
| **Settings Service** | Reads/writes JSON config; notifies subscribers on change (model reload, hotkey re-register) |
| **React UI** | Displays recording state, transcription overlay, settings panel; renders inside Wails WebView |

---

## Goroutine & Concurrency Model

```
Main Goroutine (Wails runtime)
│
├── HotkeyManager goroutine
│     └── sends → recordChan (chan RecordEvent)
│
├── AudioService goroutine
│     ├── reads ← recordChan
│     ├── captures PCM to audioBuffer ([]float32)
│     └── sends → whisperChan (chan AudioBuffer)
│
├── WhisperService goroutine
│     ├── reads ← whisperChan
│     ├── runs inference (blocking CGo — isolated goroutine)
│     └── sends → resultChan (chan TranscriptionResult)
│
└── OutputService goroutine
      ├── reads ← resultChan
      ├── attempts paste via osascript subprocess
      └── on failure → clipboard + Wails EventEmit("notification")
```

**Rules:**
- Whisper CGo inference runs in its own goroutine — never on the Wails event loop
- All inter-component communication via typed Go channels (buffered, size 1)
- UI updates only via `runtime.EventsEmit()` — never direct state mutation from goroutines

---

## Data Flow: Core Dictation Loop

```
[User presses hotkey]
       │
       ▼
HotkeyManager → recordChan ← AudioService starts capture
                                    │
                              [PCM ring buffer fills]
                                    │
[User releases hotkey]             │
       │                           │
       ▼                           ▼
HotkeyManager → recordChan    AudioBuffer sealed
                                    │
                                    ▼
                            WhisperService.Transcribe(buf)
                            [CGo → libwhisper.a → Core ML]
                                    │
                              TranscriptionResult
                                    │
                                    ▼
                            OutputService.Paste(text)
                            [osascript: keystroke text]
                                    │
                            ┌───────┴────────┐
                            │ success        │ failure
                            ▼                ▼
                       [text in app]   [clipboard + notification]
```

---

## OS Integration Details

### Global Hotkey
- **Library**: `github.com/micmonay/keybd_event` (evaluate) or use `CGEventTap` via CGo
- **Default binding**: `⌃Space` (configurable)
- **Conflict handling**: If hotkey registration fails, notify user via settings UI and suggest alternative

### Paste-to-Active-App
```go
// Primary: osascript (no CGo dependency)
cmd := exec.Command("osascript", "-e",
    fmt.Sprintf(`tell application "System Events" to keystroke "%s"`, text))
err := cmd.Run()
if err != nil {
    // Fallback: clipboard
    clipboard.WriteAll(text)
    runtime.EventsEmit(ctx, "notification", "Copied to clipboard")
}
```

### macOS Permissions Required
| Permission | When Requested | Purpose |
|-----------|----------------|---------|
| Microphone | First recording attempt | Audio capture |
| Accessibility | First paste attempt | `osascript` keystroke injection |

---

## Settings Schema

```json
{
  "hotkey": "ctrl+space",
  "model": "base",
  "language": "en",
  "launchAtLogin": false,
  "outputMode": "paste"
}
```

Stored at: `~/Library/Application Support/voice-to-text/config.json`
Models stored at: `~/Library/Application Support/voice-to-text/models/<name>.bin`

---

## Build & Deployment

```bash
# Development
wails dev

# Production build (macOS only — no cross-compile with CGo)
CGO_ENABLED=1 GGML_METAL=1 wails build -platform darwin/arm64

# Optional: code sign for Gatekeeper
codesign --deep --force --sign "Developer ID Application: ..." voice-to-text.app
```

**Distribution**: Direct `.app` download or Homebrew cask — App Store excluded (Accessibility + Microphone entitlements conflict with sandbox).

---

## Key Architectural Decisions Summary (ADRs)

| # | Decision | Alternatives Rejected | Reason |
|---|----------|----------------------|--------|
| ADR-1 | Wails v2 over Electron | Electron | Chromium bloat; 200MB+ baseline RAM |
| ADR-2 | Wails v2 over Tauri | Tauri | Go > Rust for learning curve |
| ADR-3 | whisper.cpp CGo bindings | subprocess `whisper-cli` | subprocess adds ~50ms IPC overhead per inference |
| ADR-4 | Core ML acceleration | CPU-only | Mandatory for < 500ms on base model |
| ADR-5 | `osascript` paste | AX API CGo | Simpler; no additional CGo complexity; fallback if needed |
| ADR-6 | JSON config file | SQLite, plist | Simplest; human-readable; no ORM needed |
| ADR-7 | PortAudio for audio | AVFoundation CGo | PortAudio has Go bindings; AVFoundation would need full CGo bridge |
