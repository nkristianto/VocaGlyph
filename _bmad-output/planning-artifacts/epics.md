---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
---

# voice-to-text - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for voice-to-text, decomposing the requirements from the PRD and Architecture into implementable stories.

## Implementation Progress

| Epic | Story | Status |
|------|-------|--------|
| Epic 1 | 1.1 Wails Scaffold & Menu Bar | ✅ done |
| Epic 1 | 1.2 Launch at Login | ✅ done |
| Epic 1 | 1.3 Design System & UI | ✅ done |
| Epic 1 | 7.1 True Menu Bar Agent Mode | ✅ done |
| Epic 1 | 7.2 Settings Panel — Model & Language | ✅ done |
| Epic 2 | 2.1 Global Hotkey Registration | ✅ done |
| Epic 2 | 2.2 Microphone Audio Capture | ✅ done |
| Epic 2 | 2.3 Microphone Permission Request | ✅ done |
| Epic 2 | 2.4 Recording Visual Feedback | ✅ done |
| Epic 3 | 3.1 whisper.cpp CGo Integration | ✅ done |
| Epic 3 | 3.2 Audio-to-Text Transcription | ✅ done |
| Epic 3 | 3.3 Transcription Overlay Display | ✅ done |
| Epic 4 | 4.1 Paste to Active Application | ✅ done |
| Epic 4 | 4.2 Accessibility Permission & Clipboard Fallback | ✅ done |
| Epic 5 | 5.1 Model Selection & Download | ✅ done |
| Epic 5 | 5.2 First-Run Model Detection | ✅ done |
| Epic 5 | 5.3 Model Hot-Swap | ✅ done |
| Epic 6 | 6.1 Settings Persistence | ✅ done |
| Epic 6 | 6.2 Hotkey Reconfiguration | ✅ done |
| Epic 6 | 6.3 Language Selection | ✅ done |
| — | Bug Fixes (quit panic, window drag, min size) | ✅ done |

> **🎉 All epics complete.** Epics 1–6 fully implemented and verified. The app supports hotkey recording, mic capture, whisper transcription (tiny/base/small models), paste to active app, settings persistence, and in-app model download with first-run guided setup.


## Requirements Inventory

### Functional Requirements

FR1: User can start audio recording via a configurable global hotkey
FR2: User can stop audio recording via the same hotkey (toggle) or by releasing (push-to-talk)
FR3: System captures audio from the default macOS microphone
FR4: System provides visual feedback (menu bar icon state change) when recording is active
FR5: System handles microphone permission request gracefully on first use
FR6: System transcribes recorded audio using a locally-installed whisper.cpp model
FR7: System processes transcription entirely on-device with no network calls
FR8: User can select the active Whisper model (tiny, base, small) from settings
FR9: System displays transcribed text in a floating overlay/panel before inserting
FR10: System auto-pastes transcribed text into the currently active application at cursor position
FR11: System copies transcribed text to clipboard as a fallback output method
FR12: System detects paste failure and falls back to clipboard copy automatically
FR13: System shows a brief non-intrusive notification when clipboard fallback is used
FR14: User can browse and select available Whisper model sizes from settings
FR15: System downloads the selected model on first use with progress indication
FR16: System stores models locally and reuses them across sessions
FR17: System detects missing models and prompts user to download before first use
FR18: User can configure the global hotkey binding
FR19: User can select the active Whisper model
FR20: User can select the transcription language
FR21: Settings persist across application restarts
FR22: Settings changes (model, hotkey) take effect immediately without restart
FR23: Application runs as a macOS menu bar app with no Dock icon
FR24: Application can be configured to launch at login
FR25: User can quit the application from the menu bar icon menu
FR26: Application initialises and is ready for dictation within 2 seconds of launch

### NonFunctional Requirements

NFR1: Transcription latency < 500ms from end of utterance to text appearing on screen (base/small model on Apple Silicon)
NFR2: App startup time < 2 seconds from launch to hotkey-ready state
NFR3: Audio capture latency < 50ms buffering to avoid clipping the start of speech
NFR4: whisper.cpp inference must not block the UI thread; run in background goroutine
NFR5: Memory footprint < 200MB RAM during active transcription session
NFR6: CPU usage during idle (no recording) < 1% average
NFR7: Model files stored in Application Support directory; no temp file leaks on crash
NFR8: App must not crash on extended sessions (minimum 4-hour continuous background run)
NFR9: Hotkey must remain registered after other apps register overlapping shortcuts (graceful conflict handling)
NFR10: Audio capture must recover cleanly if microphone is disconnected and reconnected
NFR11: Zero network calls at runtime — all inference fully local
NFR12: Audio data is never written to disk; processed in-memory only
NFR13: No analytics, telemetry, or crash reporting to external services
NFR14: App requests only minimum macOS permissions: Microphone, Accessibility
NFR15: Minimum macOS 13 Ventura
NFR16: Apple Silicon (M-series) primary target; Intel best-effort
NFR17: whisper.cpp models in .bin format, compatible with standard whisper.cpp releases

### Additional Requirements

- **Starter/Scaffold**: `wails init -n voice-to-text -t react` — must be the first implementation story
- **CGo Build**: whisper.cpp Go bindings require CGo; build with `CGO_ENABLED=1 GGML_METAL=1`
- **Core ML**: whisper.cpp must be built with `-DWHISPER_COREML=1` for Apple Neural Engine acceleration (critical for NFR1)
- **Audio Library**: PortAudio Go bindings (`github.com/gordonklaus/portaudio`) for cross-platform audio I/O
- **Hotkey Library**: `github.com/micmonay/keybd_event` or `robotgo` — evaluate at implementation
- **Paste Strategy**: osascript subprocess as primary; clipboard CGo as fallback (deterministic error detection required)
- **Settings Path**: `~/Library/Application Support/voice-to-text/config.json`
- **Model Path**: `~/Library/Application Support/voice-to-text/models/<name>.bin`
- **Goroutine Model**: 4 goroutines minimum: HotkeyManager, AudioService, WhisperService, OutputService — communicate via typed channels
- **Distribution**: Direct .app download or Homebrew cask — App Store excluded due to Accessibility + Microphone sandbox conflicts
- **macOS Permissions**: Microphone (first recording), Accessibility (first paste) — graceful first-run request flows required

### FR Coverage Map

| FR | Epic | Brief |
|----|------|-------|
| FR1 | Epic 2 | Global hotkey starts recording |
| FR2 | Epic 2 | Hotkey stops recording |
| FR3 | Epic 2 | Microphone audio capture |
| FR4 | Epic 2 | Menu bar visual feedback during recording |
| FR5 | Epic 2 | Microphone permission request |
| FR6 | Epic 3 | whisper.cpp transcription |
| FR7 | Epic 3 | Fully offline / no network calls |
| FR8 | Epic 3 | Model selection in settings |
| FR9 | Epic 3 | Transcription overlay display |
| FR10 | Epic 4 | Paste to active app |
| FR11 | Epic 4 | Clipboard fallback |
| FR12 | Epic 4 | Paste failure detection |
| FR13 | Epic 4 | Clipboard fallback notification |
| FR14 | Epic 5 | Model browse & select |
| FR15 | Epic 5 | Model download with progress |
| FR16 | Epic 5 | Local model storage & reuse |
| FR17 | Epic 5 | Missing model detection |
| FR18 | Epic 6 | Hotkey binding config |
| FR19 | Epic 6 | Model selection config |
| FR20 | Epic 6 | Language selection config |
| FR21 | Epic 6 | Settings persistence |
| FR22 | Epic 6 | Hot-reload on settings change |
| FR23 | Epic 1 | Menu bar app, no Dock icon |
| FR24 | Epic 1 | Launch at login |
| FR25 | Epic 1 | Quit from menu bar |
| FR26 | Epic 1 | < 2s startup ready state |

## Epic List

### Epic 1: App Foundation, Shell & Design System
User can launch the app to the macOS menu bar, see it running as a persistent icon, quit it, and configure it to launch at login. The Wails project is scaffolded, the goroutine skeleton is in place, and the UI implements the approved design system.
**FRs covered:** FR23, FR24, FR25, FR26
**Additional:** Wails scaffold, goroutine skeleton, settings JSON structure, design system from approved mockups
**Design:** UI mockups generated (Menu Bar Dropdown, Recording Overlay, Settings Panel) — full design doc to be provided by user

### Epic 2: Voice Capture & Recording
User can press a global hotkey to start and stop recording from their microphone, with clear visual feedback in the menu bar — the core interaction pattern works end-to-end before transcription.
**FRs covered:** FR1, FR2, FR3, FR4, FR5

### Epic 3: Local Speech Transcription
User can dictate and receive transcribed text via whisper.cpp running fully on-device with Core ML acceleration. The full dictation loop ends with text output.
**FRs covered:** FR6, FR7, FR8, FR9
**Additional:** CGo whisper.cpp bindings, Core ML build (-DWHISPER_COREML=1), goroutine isolation for inference

### Epic 4: Text Output & Paste Integration
Transcribed text lands automatically in the active app at cursor position. Paste failures fall back to clipboard gracefully with a brief notification.
**FRs covered:** FR10, FR11, FR12, FR13

### Epic 5: Model Management
User can select, download, and switch Whisper models. First-run experience guides the user through setup and detects missing models.
**FRs covered:** FR14, FR15, FR16, FR17

### Epic 6: Settings & Configuration
User can fully configure hotkey, model, and language. Changes apply immediately without restart. All settings persist across sessions.
**FRs covered:** FR18, FR19, FR20, FR21, FR22

---

## Epic 1: App Foundation, Shell & Design System

User can launch the app to the macOS menu bar, see it running as a persistent icon, quit it, and configure it to launch at login. The Wails project is scaffolded, the goroutine skeleton is established, and the UI implements the approved design system.

### Story 1.1: Wails Project Scaffold & Menu Bar Shell

As a developer,
I want a Wails v2 + React project initialised with a functioning macOS menu bar icon and no Dock presence,
So that the app shell exists and all future features have a stable foundation to plug into.

**Acceptance Criteria:**

**Given** the project is not yet created
**When** `wails init -n voice-to-text -t react` is run
**Then** a working Wails project is created with a Go backend and React frontend

**Given** the app is built and launched
**When** it starts
**Then** a microphone icon appears in the macOS menu bar and no Dock icon appears (`LSUIElement=1` in `Info.plist`)

**Given** the menu bar icon is visible
**When** the user clicks it
**Then** a dropdown popover appears with "voice-to-text" label, status text, and menu items including "Settings" and "Quit"

**Given** the app is running
**When** the user selects "Quit" from the menu
**Then** the app exits cleanly and the menu bar icon disappears

---

### Story 1.2: Launch at Login Toggle

As a user,
I want to configure the app to launch automatically at macOS login,
So that the dictation tool is always available without manually starting it.

**Acceptance Criteria:**

**Given** the Settings panel is open
**When** the user toggles "Launch at login" on
**Then** the app registers itself as a login item using macOS SMLoginItemSetEnabled or launchd

**Given** "Launch at login" is enabled and the user logs out then back in
**When** macOS loads the user session
**Then** voice-to-text appears in the menu bar automatically

**Given** the user toggles "Launch at login" off
**When** they next log in
**Then** the app does not auto-launch

---

### Story 1.3: Design System & UI Components

As a developer,
I want the React frontend to implement the approved dark glassmorphism design system,
So that all future screens and components are consistent with the design mockups.

**Acceptance Criteria:**

**Given** the design mockups (Menu Bar Dropdown, Recording Overlay, Settings Panel)
**When** the React frontend is implemented
**Then** the menu bar popover matches the dark glass design with Inter font, red accent (#f20d0d), and rounded components

**Given** the app is running
**When** the popover opens
**Then** it renders with semi-transparent blurred dark background, correct typography, and spacing matching the mockups

**Given** a design token change is needed
**When** the CSS variable is updated
**Then** all components reflect the change consistently

---

## Epic 2: Voice Capture & Recording

User can press a global hotkey to start and stop recording from their microphone, with clear menu bar visual feedback.

### Story 2.1: Global Hotkey Registration

As a user,
I want to press a system-wide hotkey (Control+Space by default) to trigger recording from any app,
So that I can start dictation without switching windows or clicking.

**Acceptance Criteria:**

**Given** the app is running in the menu bar
**When** the user presses Control+Space in any application
**Then** the app receives the hotkey event and begins the recording flow

**Given** another app has registered the same hotkey
**When** the hotkey conflicts
**Then** the app detects the conflict, notifies the user via the menu bar popover, and prompts them to choose an alternative

**Given** a new hotkey is saved in settings
**When** the app applies the change
**Then** the old hotkey is deregistered and the new one is registered system-wide immediately

---

### Story 2.2: Microphone Audio Capture

As a user,
I want the app to capture audio from my default macOS microphone when recording is active,
So that my speech is reliably captured for transcription.

**Acceptance Criteria:**

**Given** recording is triggered via hotkey
**When** the AudioService goroutine starts
**Then** it opens the default macOS microphone via PortAudio and begins capturing PCM float32 audio into an in-memory ring buffer

**Given** recording is active
**When** the user presses the hotkey again to stop
**Then** audio capture ends, the buffer is sealed, and passed to the whisper channel

**Given** audio is captured
**When** the session ends
**Then** no audio data is written to disk at any point (NFR12)

---

### Story 2.3: Microphone Permission Request

As a user,
I want the app to request microphone access gracefully on first use,
So that I understand why the permission is needed and can grant it without confusion.

**Acceptance Criteria:**

**Given** the app has no microphone permission
**When** the user triggers recording for the first time
**Then** macOS shows the microphone permission dialog with a clear purpose string

**Given** the user denies microphone permission
**When** they try to record
**Then** the app shows a notification in the popover: "Microphone access required — open System Settings to enable"

**Given** the user grants microphone permission
**When** they next trigger recording
**Then** audio capture starts immediately without another permission dialog

---

### Story 2.4: Recording Visual Feedback

As a user,
I want the menu bar icon to change state and a recording HUD to appear when recording is active,
So that I always know when the app is capturing my voice.

**Acceptance Criteria:**

**Given** the user starts recording
**When** the AudioService begins capture
**Then** the menu bar icon changes to a pulsing red indicator and a floating HUD pill appears near the top of the screen

**Given** the HUD is visible
**When** recording is active
**Then** the HUD shows a pulsing red dot, animated waveform, "Recording..." label, and an elapsed time counter

**Given** the user stops recording
**When** audio capture ends
**Then** the HUD disappears and the menu bar icon returns to its idle state

---

## Epic 3: Local Speech Transcription

User can dictate and receive transcribed text via whisper.cpp running fully on-device with Core ML acceleration.

### Story 3.1: whisper.cpp CGo Integration & Model Loading

As a developer,
I want the Go backend to load a Whisper model via CGo bindings and have it ready for inference,
So that transcription can proceed with minimal latency when audio is available.

**Acceptance Criteria:**

**Given** a .bin model file exists in the models directory
**When** the app starts
**Then** the WhisperService goroutine loads the model into memory via whisper.cpp CGo bindings

**Given** the app is built
**When** the Go binary links against libwhisper.a
**Then** it compiles successfully with CGO_ENABLED=1 and GGML_METAL=1 for Core ML support

**Given** no model file exists at startup
**When** the app initialises
**Then** the WhisperService enters a waiting-for-model state and notifies the UI to prompt model download — it does not crash

---

### Story 3.2: Audio-to-Text Transcription

As a user,
I want my recorded audio to be transcribed to text within 500ms of stopping speech,
So that dictation feels instant and does not break my workflow.

**Acceptance Criteria:**

**Given** a sealed audio buffer arrives on the whisper channel
**When** the WhisperService processes it
**Then** whisper_full() runs on a background goroutine (not the Wails UI thread) and returns a transcription string

**Given** the model is loaded with Core ML enabled
**When** transcription runs on Apple Silicon
**Then** it completes in under 500ms for utterances up to 15 seconds on the base model (NFR1)

**Given** transcription completes
**When** the result is sent on the result channel
**Then** the OutputService receives it and the UI emits a transcription-ready event with the text

---

### Story 3.3: Transcription Overlay Display

As a user,
I want to briefly see the transcribed text in a floating overlay before it is inserted,
So that I can confirm the transcription before it lands in my active app.

**Acceptance Criteria:**

**Given** a transcription result is ready
**When** the result event fires
**Then** a semi-transparent floating overlay panel appears showing the transcribed text

**Given** the overlay is shown
**When** 1.5 seconds pass or the insert begins
**Then** the overlay fades out automatically

**Given** the overlay is displayed
**When** the text is too long to fit in one line
**Then** the overlay truncates with an ellipsis

---

## Epic 4: Text Output & Paste Integration

Transcribed text lands automatically in the active application at cursor position. Paste failures fall back to clipboard gracefully.

### Story 4.1: Paste to Active Application

As a user,
I want transcribed text to be automatically inserted at my cursor position in whatever app I was using,
So that I never have to manually paste.

**Acceptance Criteria:**

**Given** a transcription result is available
**When** the OutputService runs
**Then** it executes osascript to keystroke the text into the frontmost app

**Given** the paste completes successfully
**When** text is inserted
**Then** the cursor advances to after the inserted text in the target application

**Given** the text contains special characters (quotes, backslashes)
**When** the osascript command is built
**Then** special characters are escaped correctly to prevent injection issues

---

### Story 4.2: Accessibility Permission & Clipboard Fallback

As a user,
I want the app to gracefully handle paste failures and Accessibility permission denial so my transcribed text is never silently lost.

**Acceptance Criteria:**

**Given** the app has no Accessibility permission
**When** the first paste is attempted
**Then** macOS shows the Accessibility permission dialog; if denied, the app copies text to clipboard and notifies the user

**Given** the osascript paste command fails
**When** the OutputService detects failure
**Then** it falls back to copying text to clipboard

**Given** clipboard fallback is used
**When** the text is copied
**Then** a brief notification appears: "Copied to clipboard — paste with Command+V" (FR13)

---

## Epic 5: Model Management

User can select, download, and switch Whisper models. First-run experience is smooth.

### Story 5.1: Model Selection & Download

As a user,
I want to browse available Whisper model sizes and download the one I want,
So that I can choose the right balance of speed and accuracy for my hardware.

**Acceptance Criteria:**

**Given** the Settings panel is open
**When** the user navigates to the "Model" section
**Then** they see options for Tiny (75MB), Base (140MB), and Small (450MB) with download status indicators (FR14)

**Given** a model is not yet downloaded
**When** the user selects it and initiates download
**Then** the model is fetched from the official whisper.cpp model repository with a progress indicator (FR15)

**Given** a model finishes downloading
**When** verified successfully
**Then** it is saved to the models directory and becomes available for selection (FR16)

---

### Story 5.2: First-Run Model Detection & Guided Setup

As a user,
I want the app to detect that no model is installed on first launch and guide me to download one,
So that I never encounter a confusing error mid-dictation.

**Acceptance Criteria:**

**Given** no model file exists in the models directory
**When** the app launches for the first time
**Then** the menu bar popover opens automatically showing a prompt to download a model (FR17)

**Given** the first-run prompt is shown
**When** the user dismisses it without downloading
**Then** the app enters a no-model state and shows a warning when recording is attempted

**Given** a model is downloaded via first-run flow
**When** download completes
**Then** the app transitions to ready state and recording becomes available immediately

---

### Story 5.3: Model Hot-Swap

As a user,
I want to switch between downloaded models without restarting the app,
So that I can adjust accuracy and speed tradeoffs instantly.

**Acceptance Criteria:**

**Given** multiple models are downloaded
**When** the user selects a different model in Settings and saves
**Then** the WhisperService unloads the current model and loads the new one within 3 seconds

**Given** a model swap is in progress
**When** the user attempts to record
**Then** recording is queued or the user is notified that a model swap is in progress

**Given** the swap completes successfully
**When** the next dictation runs
**Then** it uses the newly selected model

---

## Epic 6: Settings & Configuration

User can fully configure hotkey, model, and language. Settings persist and changes apply immediately without restart.

### Story 6.1: Settings Persistence

As a user,
I want my settings to be saved and restored across app restarts,
So that I never have to reconfigure the app.

**Acceptance Criteria:**

**Given** the user changes any setting and saves
**When** the app is quit and relaunched
**Then** all settings are restored from ~/Library/Application Support/voice-to-text/config.json (FR21)

**Given** the config file does not exist on first run
**When** the app starts
**Then** it creates the file with defaults: hotkey=ctrl+space, model=base, language=en, launchAtLogin=false

**Given** the config file is corrupted
**When** the app starts
**Then** it logs the error, resets to defaults, and overwrites with a valid config

---

### Story 6.2: Hotkey Reconfiguration

As a user,
I want to change the global recording hotkey to any combination I prefer,
So that I can avoid conflicts with other apps.

**Acceptance Criteria:**

**Given** the Settings panel is open
**When** the user clicks the hotkey field and presses a new key combination
**Then** the field displays the captured combination (e.g., Option+Space)

**Given** a new hotkey is saved
**When** the settings are applied
**Then** the old hotkey is deregistered and the new one registers system-wide immediately (FR22, FR18)

**Given** the user presses a reserved OS hotkey
**When** registration fails
**Then** the app notifies the user and reverts to the previous valid hotkey

---

### Story 6.3: Language Selection

As a user,
I want to select the transcription language for whisper.cpp,
So that my dictation is accurately transcribed in my preferred language.

**Acceptance Criteria:**

**Given** the Settings panel is open
**When** the user opens the Language dropdown
**Then** a list of supported whisper.cpp languages is shown with English as default (FR20)

**Given** the user selects a different language and saves
**When** the next transcription runs
**Then** whisper.cpp is invoked with the updated language parameter

**Given** the user selects "Auto"
**When** a transcription runs
**Then** whisper.cpp detects the spoken language automatically

---

## Story 7: Menu Bar Shell Completion + Settings Panel (Combined)

_This story addresses two gaps discovered during implementation: (1) the app still shows in the Dock and starts with the window visible instead of true menu bar agent behaviour; (2) there is no settings UI or config persistence despite the epics calling for it. These are delivered together as a single implementation slice._

**FRs covered:** FR23 (no Dock icon), FR19 (model selection), FR20 (language selection), FR21 (settings persist), Story 6.1 prefix

---

### Story 7.1: True macOS Menu Bar Agent Mode

As a user,
I want the app to live exclusively in the macOS menu bar with a mic icon and no Dock presence,
So that it behaves like a native menu bar utility and doesn't clutter my workspace.

**Acceptance Criteria:**

**Given** the app is launched
**When** it initialises
**Then** no Dock icon appears (`LSUIElement` pattern via `mac.ActivationPolicyAccessory`) and the window starts hidden

**Given** the app is running
**When** the user looks at the right side of their menu bar
**Then** a microphone icon (template PNG, adapts to light/dark mode) is visible

**Given** the systray icon is visible
**When** the user clicks it
**Then** the popover window appears at the current mouse position (show/hide toggle)

**Given** the popover window is open
**When** the user clicks elsewhere or the window loses focus
**Then** the window hides cleanly without quitting the app

**Given** the user right-clicks or uses the systray menu
**When** they select "Quit"
**Then** the app exits cleanly and the menu bar icon disappears

---

### Story 7.2: Settings Panel — Model & Language

As a user,
I want to select the active Whisper model size and transcription language from the popover settings section,
So that I can tune accuracy versus speed and dictate in my preferred language.

**Acceptance Criteria:**

**Given** the popover is open
**When** the user looks at the Settings section
**Then** they see a 3-tab model picker: Tiny · Base · Small, with the current active model highlighted

**Given** the user taps a different model tab
**When** that model's `.bin` file exists locally
**Then** WhisperService reloads with the new model immediately (no restart required)

**Given** the user taps a model that is not yet downloaded
**When** the tab is selected
**Then** a "Not downloaded" indicator is shown and recording is disabled until a valid model is active

**Given** the popover settings section is visible
**When** the user opens the Language dropdown
**Then** they can choose from: Auto, English, Spanish, French, German, Japanese

**Given** the user changes the language
**When** the change is saved
**Then** the next transcription uses that language parameter via `ctx.SetLanguage()`

**Given** the user changes any setting
**When** the change occurs
**Then** it is persisted to `~/Library/Application Support/voice-to-text/config.json` immediately

**Given** the app restarts after a settings change
**When** it initialises
**Then** all previous settings are restored from `config.json`

---
