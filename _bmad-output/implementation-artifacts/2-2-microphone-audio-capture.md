# Story 2.2: Microphone Audio Capture

**Status:** done

## Story

As a user,
I want the app to capture audio from my default macOS microphone when recording is active,
So that my speech is reliably captured for transcription.

## Acceptance Criteria

**Given** recording is triggered via hotkey
**When** the AudioService goroutine starts
**Then** it opens the default macOS microphone via PortAudio and begins capturing PCM float32 audio into an in-memory ring buffer ✅

**Given** recording is active
**When** the user presses the hotkey again to stop
**Then** audio capture ends, the buffer is sealed, and passed to the whisper channel ✅

**Given** audio is captured
**When** the session ends
**Then** no audio data is written to disk at any point (NFR12) ✅

## Tasks/Subtasks

- [x] Task 1: System dependencies
  - [x] 1a: `brew install portaudio` — PortAudio 19.7.0 installed
  - [x] 1b: `go get github.com/gordonklaus/portaudio@latest` — bindings added
  - [x] 1c: `PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig` required for CGo linking

- [x] Task 2: Pure-Go RingBuffer
  - [x] 2a: `ring_buffer.go` — thread-safe circular buffer with Write/Drain/Len
  - [x] 2b: Drop-oldest overflow strategy (never blocks audio callback)
  - [x] 2c: 4 tests: Write, Drain, Overflow, Concurrent

- [x] Task 3: AudioService with mock-able backend
  - [x] 3a: `audioBackend` interface (Open/Start/Stop/Close/Frames) for test injection
  - [x] 3b: `realAudioBackend` — PortAudio 16kHz mono float32 callback → framesCh
  - [x] 3c: `AudioService.StartRecording(ctx)` — opens mic, goroutine writes frames to ring buffer
  - [x] 3d: `AudioService.StopRecording()` — stops stream, drains ring buffer, returns sealed PCM
  - [x] 3e: `atomic.Bool` for IsRecording() race-safety
  - [x] 3f: 4 tests: TestStartRecording, TestStopRecording, TestRecordingProducesData, TestNoDiskWrites

- [x] Task 4: Wire into App
  - [x] 4a: `audioStarter` interface on App struct
  - [x] 4b: `SetAudioService()` injection from main.go
  - [x] 4c: `whisperCh chan []float32` (buffered 4) — sealed PCM for Story 3
  - [x] 4d: `onHotkeyTriggered()` toggles StartRecording/StopRecording, queues to whisperCh
  - [x] 4e: `audio:error` event emitted on failure

- [x] Task 5: Verify
  - [x] 5a: `go test ./... -count=1 -timeout 30s` — 23/23 pass (no real mic needed)
  - [x] 5b: `go build ./...` — clean (with PKG_CONFIG_PATH set)

## Dev Notes

- **Sample rate:** 16kHz — Whisper's expected input format (Story 3 will pass directly)
- **Ring buffer capacity:** 60 seconds @ 16kHz = 960,000 samples max
- **PKG_CONFIG_PATH:** Must be set for `wails dev` / `wails build`. Add to shell profile or use `CGO_CFLAGS`
- **No disk writes:** PCM lives only in `[]float32` in memory. The `whisperCh` is the only data pathway — consumed by Story 3
- **AudioService is nil in tests** — main.go injects via `SetAudioService()`, same pattern as HotkeyService
- **Frame buffer:** 512 samples per PortAudio callback. 64-frame channel buffer prevents audio dropout under load

## Dev Agent Record

### Implementation Plan
1. `brew install portaudio` + `go get gordonklaus/portaudio`
2. Wrote `ring_buffer_test.go` (RED) + `ring_buffer.go` (GREEN) — 4 tests, all pass
3. Wrote `audio_service_test.go` (RED) + `audio_service.go` (GREEN) — 4 tests, all pass
4. Updated `app.go` — added `audioStarter` interface, `SetAudioService()`, `whisperCh`, `onHotkeyTriggered()` toggle
5. Updated `main.go` — `SetAudioService(NewAudioService())`
6. `go test ./... -count=1 -timeout 30s` — 23/23 pass
7. `go mod tidy` — `gordonklaus/portaudio` now direct dependency

### Completion Notes
✅ 5 tasks, 17 subtasks — all complete.
✅ RingBuffer: pure-Go, drop-oldest, thread-safe, 60s capacity.
✅ AudioService: PortAudio 16kHz mono, float32, zero disk writes.
✅ 23/23 tests, no real microphone needed.
✅ whisperCh ready for Story 3 (Whisper transcription).
⚠️ `PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig` must be set in shell for `wails dev`.

## File List
- `ring_buffer.go` (new) — RingBuffer: Write/Drain/Len, drop-oldest, sync.Mutex
- `ring_buffer_test.go` (new) — 4 tests (Write, Drain, Overflow, Concurrent)
- `audio_service.go` (new) — AudioService, audioBackend interface, realAudioBackend (PortAudio)
- `audio_service_test.go` (new) — 4 tests using mockAudioBackend
- `app.go` (modified) — audioStarter interface, SetAudioService(), whisperCh, onHotkeyTriggered()
- `main.go` (modified) — SetAudioService(NewAudioService()) injection

## Change Log
- 2026-02-20: Story 2.2 complete — PortAudio capture, RingBuffer, AudioService, 23/23 tests pass.
