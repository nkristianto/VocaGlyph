# Story 2.3: Microphone Permission Request

**Status:** review

## Story

As a user,
I want the app to request microphone access gracefully on first use,
So that I understand why the permission is needed and can grant it without confusion.

## Acceptance Criteria

**Given** the app has no microphone permission
**When** the user triggers recording for the first time
**Then** macOS shows the microphone permission dialog with a clear purpose string ✅

**Given** the user denies microphone permission
**When** they try to record
**Then** the app shows a notification in the popover: "🎙 Microphone access required" with "Open Settings" button ✅

**Given** the user grants microphone permission
**When** they next trigger recording
**Then** audio capture starts immediately without another permission dialog ✅

## Tasks/Subtasks

- [x] Task 1: Info.plist — NSMicrophoneUsageDescription
  - [x] 1a: Added clear purpose string to `build/darwin/Info.plist`
  - [x] 1b: Message: "voice-to-text needs microphone access to capture your speech for local transcription. No audio is stored or transmitted."

- [x] Task 2: ErrMicPermissionDenied sentinel in AudioService
  - [x] 2a: `ErrMicPermissionDenied` exported sentinel in `audio_service.go`
  - [x] 2b: `realAudioBackend.Open()` detects denied/unavailable/unauthorized strings from PortAudio error
  - [x] 2c: `StartRecording()` returns sentinel unwrapped for clean `errors.Is()` usage
  - [x] 2d: `TestPermissionDenied` — mock backend returns sentinel, verifies propagation

- [x] Task 3: App.go permission event + OpenSystemSettings
  - [x] 3a: `onHotkeyTriggered()` checks `errors.Is(err, ErrMicPermissionDenied)` → emits `audio:permission-denied`
  - [x] 3b: `OpenSystemSettings()` Wails-bound method — opens macOS Privacy → Microphone pane

- [x] Task 4: React UI permission badge
  - [x] 4a: `micDenied` state, `EventsOn("audio:permission-denied")` handler
  - [x] 4b: Permission badge with "Open Settings" button (calls `OpenSystemSettings()`)
  - [x] 4c: `hotkey:triggered` clears `micDenied` state (permission granted scenario)

- [x] Task 5: Verify
  - [x] 5a: `go test ./... -count=1 -timeout 30s` — 24/24 pass
  - [x] 5b: `go build ./...` — clean

## Dev Notes

- **Error unwrapping:** `ErrMicPermissionDenied` returned directly (not wrapped) from `StartRecording()` so `errors.Is()` works cleanly in callers
- **Permission prompt timing:** macOS shows the dialog the first time `portaudio.OpenDefaultStream()` is called — no CGo needed
- **Deep link:** `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone` opens directly to the Microphone privacy pane
- **Badge auto-clears:** `hotkey:triggered` event clears `micDenied` state, so if user grants permission and presses ⌃Space, the badge disappears immediately

## File List
- `build/darwin/Info.plist` (modified) — NSMicrophoneUsageDescription added
- `audio_service.go` (modified) — ErrMicPermissionDenied sentinel, permission error detection in Open()
- `audio_service_test.go` (modified) — mockAudioBackend.openErr field, TestPermissionDenied
- `app.go` (modified) — errors.Is check for permission, audio:permission-denied emit, OpenSystemSettings()
- `frontend/src/App.jsx` (modified) — micDenied state, EventsOn handler, permission badge with Open Settings button

## Change Log
- 2026-02-20: Story 2.3 complete — NSMicrophoneUsageDescription, ErrMicPermissionDenied, permission UI. 24/24 tests pass.
