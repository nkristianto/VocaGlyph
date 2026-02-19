---
stepsCompleted: [step-01-init, step-02-discovery, step-02b-vision, step-02c-executive-summary, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional]
inputDocuments: []
workflowType: 'prd'
briefCount: 0
researchCount: 0
brainstormingCount: 0
projectDocsCount: 0
classification:
  projectType: desktop_app
  domain: Productivity / AI Tooling
  complexity: medium
  projectContext: greenfield
  primaryUsers: Power users (developers, writers, professionals) who want fast, private dictation
  referenceApps: [VoiceInk, ParaSpeech]
  mvpScope:
    core: [menu-bar-icon, global-hotkey, whisper-cpp-inference, model-selection, transcription-overlay, paste-to-active-app, copy-to-clipboard, basic-settings]
    excluded: [ai-text-enhancement, context-aware-modes, personal-dictionary, transcription-history, privacy-mode]
---

# Product Requirements Document - voice-to-text

**Author:** Novian
**Date:** 2026-02-20

---

## Executive Summary

`voice-to-text` is a personal-use macOS menu bar dictation application that delivers fast, private, fully offline speech-to-text transcription powered by `whisper.cpp`. Built with Wails (Go backend + React frontend), it provides a lightweight native binary that outperforms Electron-based alternatives without the steep learning curve of Rust. The user activates recording via a global hotkey, speaks, and the transcribed text is pasted directly into the active application — zero cloud dependency, zero latency from network calls.

The primary user is the developer-author himself: a power user who lives in the keyboard, values privacy by default, and wants a tool he owns and can extend without friction.

### What Makes This Special

The pragmatic technology choice is the differentiator: Wails + Go sits at the optimal intersection of performance (lean native binary, no Chromium runtime), developer productivity (Go's simplicity and strong standard library), and full-stack control (whisper.cpp integrated directly in Go via CGo or subprocess). Where existing tools like VoiceInk are excellent but opaque, and Electron-based tools are transparent but bloated, this project represents a personally-owned, auditable, and extensible alternative on a stack that feels just right.

## Project Classification

| Attribute | Value |
|-----------|-------|
| **Project Type** | Desktop App (macOS native, Wails) |
| **Domain** | Personal Productivity / Local AI Tooling |
| **Complexity** | Medium |
| **Context** | Greenfield |
| **Primary User** | Solo developer (personal tool, potential open-source sharing) |
| **Reference Apps** | VoiceInk, ParaSpeech |
| **Tech Stack** | Wails v2, Go 1.22+, whisper.cpp (Metal GPU via CGo), React/Vite, PortAudio |
| **OS Integration** | Global hotkey via CGo `CGEventTap`; paste via `osascript`; clipboard via `pbcopy` |
| **Storage** | Models + config at `~/.voice-to-text/`; launch-at-login via launchd plist |

---

## Success Criteria

### User Success

The primary user (author) considers the product successful when the core dictation loop works end-to-end: activate recording via a global hotkey, speak, stop, and see the transcribed text appear in the active application or clipboard — without manual intervention. Integration with a local AI model for transcription is the minimum bar. No distribution, onboarding, or retention metrics apply at this stage.

### Business Success

Not applicable — this is a personal tool with no commercial intent for the MVP. Success is measured entirely by personal utility and daily replaceability of existing tools (VoiceInk, ParaSpeech).

### Technical Success

| Metric | Target |
|--------|--------|
| **Transcription latency** | < 500ms from end of utterance to text appearing on screen |
| **Memory footprint** | < 200MB RAM during active use |
| **Transcription accuracy** | 90–95% for everyday English speech |
| **App startup** | < 2 seconds to ready state (menu bar icon visible and hotkey active) |
| **Offline operation** | 100% — zero network calls at runtime |

### Measurable Outcomes

- User can dictate and have text inserted into any macOS app within 500ms of stopping speech
- App runs stably for an extended session without memory leaks or crashes
- whisper.cpp model (base or small) produces ≥90% accuracy on conversational English

---

## Product Scope

### MVP — Minimum Viable Product

- macOS menu bar icon (persistent, launches on login)
- Global hotkey to start/stop recording
- whisper.cpp local inference (model: tiny, base, or small — user-selectable)
- Real-time or near-real-time transcription display (overlay/panel)
- Auto-paste transcribed text into the active application
- Copy to clipboard as fallback
- Basic settings: hotkey configuration, model selection, language selection

### Growth Features (Post-MVP)

- Transcription history log (menu bar accessible)
- AI text enhancement (grammar correction, tone polish via local LLM)
- Per-app context modes (different settings per active application)
- Personal dictionary / custom word replacements
- Auto-send (press Enter after paste)

### Vision (Future)

- Privacy mode (no history persistence)
- Multi-language model support beyond English
- Voice commands for app control
- Open-source release with community model support

---

## User Journeys

### Journey 1 — Core Dictation Loop (Happy Path)

**Novian is coding and wants to dictate a code comment or compose a Slack message.**

1. Presses global hotkey (`⌃Space` by default) — menu bar icon pulses to indicate recording active
2. Speaks naturally for a few seconds
3. Presses hotkey again (or releases, if push-to-talk mode) to stop recording
4. whisper.cpp processes audio locally — transcribed text appears within 500ms
5. Text is auto-pasted at cursor position in the active application
6. Work continues without touching the mouse

**Capabilities revealed:** Global hotkey registration, audio capture pipeline, VAD or manual stop trigger, whisper.cpp inference, paste-to-active-app via Accessibility API

---

### Journey 2 — First-Time Model Setup

**Novian installs the app — no Whisper model is present yet.**

1. Launches app — detects no model downloaded
2. Settings panel appears: select model size (tiny / base / small)
3. Model downloads with progress indicator
4. Model verified; app signals readiness via menu bar icon
5. First dictation works immediately

**Capabilities revealed:** First-run detection, model download/management UI, local model storage, progress feedback

---

### Journey 3 — Changing Settings Mid-Use

**Novian wants to switch the active model or rebind the hotkey.**

1. Clicks menu bar icon → opens Settings
2. Selects a different model (downloads if not cached)
3. Updates hotkey binding
4. Saves — changes apply immediately, no restart required

**Capabilities revealed:** Settings persistence, hot-swap model loading, runtime hotkey re-registration

---

### Journey 4 — Clipboard Fallback (Edge Case)

**Novian dictates while in an app that blocks Accessibility API paste (e.g., a password field).**

1. Dictation completes — paste attempt is blocked or fails silently
2. App detects failure, copies text to clipboard, shows brief non-intrusive notification
3. User manually pastes with `⌘V`

**Capabilities revealed:** Paste failure detection, clipboard fallback, status notification

---

### Journey Requirements Summary

| Capability | Required For |
|-----------|-------------|
| Global hotkey registration (system-wide) | Journeys 1, 3, 4 |
| Audio capture (microphone) | Journeys 1, 2 |
| whisper.cpp local inference | Journey 1 |
| Model download + local storage management | Journey 2 |
| Paste-to-active-app (Accessibility API) | Journeys 1, 4 |
| Clipboard copy fallback | Journey 4 |
| Non-intrusive system notification | Journey 4 |
| Settings persistence across sessions | Journey 3 |
| Menu bar icon with status indicator | All journeys |

---

## Functional Requirements

### Recording & Audio Capture

- FR1: User can start audio recording via a configurable global hotkey
- FR2: User can stop audio recording via the same hotkey (toggle) or by releasing (push-to-talk)
- FR3: System captures audio from the default macOS microphone
- FR4: System provides visual feedback (menu bar icon state change) when recording is active
- FR5: System handles microphone permission request gracefully on first use

### Transcription

- FR6: System transcribes recorded audio using a locally-installed whisper.cpp model
- FR7: System processes transcription entirely on-device with no network calls
- FR8: User can select the active Whisper model (tiny, base, small) from settings
- FR9: System displays transcribed text in a floating overlay/panel before inserting

### Text Output

- FR10: System auto-pastes transcribed text into the currently active application at cursor position
- FR11: System copies transcribed text to clipboard as a fallback output method
- FR12: System detects paste failure and falls back to clipboard copy automatically
- FR13: System shows a brief non-intrusive notification when clipboard fallback is used

### Model Management

- FR14: User can browse and select available Whisper model sizes from settings
- FR15: System downloads the selected model on first use with progress indication
- FR16: System stores models locally and reuses them across sessions
- FR17: System detects missing models and prompts user to download before first use

### Settings & Configuration

- FR18: User can configure the global hotkey binding
- FR19: User can select the active Whisper model
- FR20: User can select the transcription language
- FR21: Settings persist across application restarts
- FR22: Settings changes (model, hotkey) take effect immediately without restart

### Application Lifecycle

- FR23: Application runs as a macOS menu bar app with no Dock icon (`mac.ActivationPolicyAccessory` + `getlantern/systray` for NSStatusItem)
- FR24: Application can be configured to launch at login (launchd plist via `LoginItemService`)
- FR25: User can quit the application from the systray icon menu or via ⌘Q shortcut
- FR26: Application initialises and is ready for dictation within 2 seconds of launch

> [!NOTE]
> Story 7 (combined Menu Bar Shell + Settings Panel) implements FR23 (true menu bar agent mode — previously only partially implemented) and partial FR19/FR20/FR21.

---

## Non-Functional Requirements

### Performance

- Transcription latency: < 500ms from end of utterance to text appearing on screen (using base or small model on Apple Silicon)
- App startup time: < 2 seconds from launch to hotkey-ready state
- Audio capture latency: < 50ms buffering to avoid clipping the start of speech
- whisper.cpp inference must not block the UI thread; run in background goroutine

### Resource Usage

- Memory footprint: < 200MB RAM during active transcription session
- CPU usage during idle (no recording): < 1% average
- Model files stored in user's Application Support directory; no temp file leaks on crash

### Reliability

- App must not crash on extended use sessions (minimum 4-hour continuous background run)
- Hotkey must remain registered even after other apps register overlapping shortcuts (graceful conflict handling)
- Audio capture must recover cleanly if microphone is disconnected and reconnected

### Privacy & Security

- Zero network calls at runtime — all inference is fully local
- Audio data is never written to disk; processed in-memory only
- No analytics, telemetry, or crash reporting to external services
- App requests only the minimum macOS permissions: Microphone, Accessibility (for paste)

### Compatibility

- Minimum macOS: 13 Ventura
- Apple Silicon (M-series) primary target; Intel compatibility best-effort
- Wails framework version: latest stable at development start
- whisper.cpp models: `.bin` format, compatible with standard whisper.cpp releases
