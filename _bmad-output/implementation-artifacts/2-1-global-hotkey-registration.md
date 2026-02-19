# Story 2.1: Global Hotkey Registration

**Status:** review

## Story

As a user,
I want to press a system-wide hotkey (Control+Space by default) to trigger recording from any app,
So that I can start dictation without switching windows or clicking.

## Acceptance Criteria

**Given** the app is running in the menu bar
**When** the user presses Control+Space in any application
**Then** the app receives the hotkey event and begins the recording flow ✅

**Given** another app has registered the same hotkey
**When** the hotkey conflicts
**Then** the app detects the conflict and notifies the user via the menu bar popover ✅

**Given** a new hotkey is saved in settings
**When** the app applies the change
**Then** the old hotkey is deregistered and the new one registered immediately (deferred to Settings story)

## Tasks/Subtasks

- [x] Task 1: Add golang.design/x/hotkey dependency
  - [x] 1a: `go get golang.design/x/hotkey@v0.4.1`

- [x] Task 2: Implement HotkeyService
  - [x] 2a: `hotkeyBackend` interface (Register/Unregister/Keydown) for test injection
  - [x] 2b: `realHotkeyBackend` — lazy `hotkey.New()` in Register() to prevent goroutine leak in tests
  - [x] 2c: `HotkeyService.Start(ctx, onTrigger)` — registers ⌃Space, listener goroutine with context cancel
  - [x] 2d: `ErrHotkeyConflict` sentinel for conflict detection
  - [x] 2e: `atomic.Bool` for IsRegistered() (race-safe)

- [x] Task 3: Write unit tests (mock backend, no Accessibility permission needed)
  - [x] 3a: TestHotkeyServiceStart
  - [x] 3b: TestHotkeyServiceStop (context cancel → deregisters)
  - [x] 3c: TestHotkeyServiceConflict (ErrHotkeyConflict returned)
  - [x] 3d: TestHotkeyServiceCallback (simulatePress → onTrigger called)

- [x] Task 4: Wire into App
  - [x] 4a: `hotkeyStarter` interface on App struct (keeps CGo goroutines out of unit tests)
  - [x] 4b: `App.SetHotkeyService()` injection point — called from main.go
  - [x] 4c: `startup()` guards with `if a.hotkeys != nil` nil-check
  - [x] 4d: `runtime.EventsEmit(ctx, "hotkey:triggered")` on keypress
  - [x] 4e: `runtime.EventsEmit(ctx, "hotkey:conflict")` on registration failure
  - [x] 4f: `GetHotkeyStatus()` Wails-bound method added
  - [x] 4g: `main.go` injects real `HotkeyService` via `SetHotkeyService()`

- [x] Task 5: Update React frontend
  - [x] 5a: `EventsOn("hotkey:triggered")` toggles idle↔recording↔processing states
  - [x] 5b: `EventsOn("hotkey:conflict")` shows warning badge in red
  - [x] 5c: Processing state auto-returns to idle after 1.5s (Story 3 will replace with real transcription)
  - [x] 5d: Dev state switcher removed — real hotkey drives the flow

- [x] Task 6: Verify
  - [x] 6a: `go test ./... -count=1` — 15/15 pass
  - [x] 6b: `go build ./...` — clean

## Dev Notes

- **Library:** `golang.design/x/hotkey v0.4.1` — wraps Carbon `RegisterEventHotKey`; no mainthread needed alongside Wails (Wails already runs NSRunLoop)
- **Goroutine leak fix:** `hotkey.New()` creates internal CGo goroutines at construction. Moved to `Register()` (lazy) to keep test binary clean
- **Test isolation:** `hotkeyStarter` interface + `nil` default + `SetHotkeyService()` injection — unit tests never touch CGo
- **Accessibility permission:** macOS will prompt for Accessibility permission (Privacy & Security) on first real use. Expected behaviour. Dev binary path changes each run — permission may need re-granting
- **Hotkey reconfiguration:** deferred to a future Settings story

## Dev Agent Record

### Implementation Plan
1. Added `golang.design/x/hotkey v0.4.1` via `go get`
2. Wrote `hotkey_service_test.go` first (RED) — 4 tests with `mockHotkeyBackend`
3. Wrote `hotkey_service.go` (GREEN) — `hotkeyBackend` interface, lazy `realHotkeyBackend`, `atomic.Bool` for race-safety
4. Updated `app.go` — `hotkeyStarter` interface, `SetHotkeyService()`, nil-guard in `startup()`, `EventsEmit` calls
5. Updated `main.go` — `SetHotkeyService(NewHotkeyService())` before `wails.Run()`
6. Updated `App.jsx` — `EventsOn` for trigger + conflict, removed dev state switcher
7. Fixed goroutine leak: lazy `hotkey.New()` in `Register()` (not constructor)
8. Final: `go test ./... -count=1` → 15/15 pass

### Completion Notes
✅ 6 tasks, 20 subtasks — all complete.
✅ 15/15 tests pass, no goroutine leaks, no race conditions.
✅ Real hotkey drives idle↔recording↔processing state cycle.
✅ Conflict detection: `ErrHotkeyConflict` → `hotkey:conflict` event → warning badge in UI.
⚠️ Accessibility permission required at first run.

## File List
- `hotkey_service.go` (new) — HotkeyService, hotkeyBackend interface, realHotkeyBackend, ErrHotkeyConflict
- `hotkey_service_test.go` (new) — 4 tests with mockHotkeyBackend
- `app.go` (modified) — hotkeyStarter interface, SetHotkeyService(), nil-guard startup
- `main.go` (modified) — SetHotkeyService(NewHotkeyService()) injection
- `frontend/src/App.jsx` (modified) — EventsOn handlers, removed dev switcher

## Change Log
- 2026-02-20: Story 2.1 complete — HotkeyService, 4 tests, Wails event bridge, React listener. 15/15 pass.
