# Bug Fixes: Quit Panic, Clean Shutdown & UX Polish

**Status:** done
**Date:** 2026-02-20
**Scope:** Cross-cutting — app lifecycle, hotkey service, whisper service

---

## Fix 1: ggml-metal ASSERT crash on quit (SIGABRT)

**Root cause:** When `runtime.Quit()` triggered `exit()`, C++ static destructors ran for ggml-metal's `ggml_metal_device`. The Metal GPU residency sets were still non-empty (whisper model never freed), causing `GGML_ASSERT([rsets->data count] == 0)` to fire → SIGABRT.

**Fix:** `app.Quit()` now calls `whisper.Close()` (→ `whisper_free()` via CGo) before `runtime.Quit()`, draining all Metal compute encoders and clearing residency sets before the C++ destructor runs.

**Files changed:**
- `app.go` — `Quit()` calls `a.whisper.Close()` before `runtime.Quit(ctx)`
- `app.go` — Added `Close() error` to the `whisperRunner` interface

---

## Fix 2: Hotkey GCD/NSEvent crash on quit

**Root cause:** `golang.design/x/hotkey` registers an `NSEvent.addGlobalMonitorForEventsMatchingMask` callback block on GCD's main dispatch queue. If this block is still registered when Cocoa tears down GCD's work queue, it crashes in `workq_kernreturn`.

**Fix:** `HotkeyService.Stop()` now:
1. Sets `shuttingDown = true` (goroutine defers skip their own `Unregister()`)
2. Calls `backend.Unregister()` synchronously **while the Cocoa event loop is still alive**
3. Cancels the goroutine's context
4. Waits up to 200ms on `doneCh` for the goroutine to fully exit before returning

`app.Quit()` calls `hs.Stop()` first, before `runtime.Quit()`.

**Files changed:**
- `hotkey_service.go` — `shuttingDown atomic.Bool`, `doneCh chan struct{}`, `Stop()` method, defers close `doneCh`
- `app.go` — `Quit()` calls `hs.Stop()` via type assertion before `runtime.Quit(ctx)`

---

## Fix 3: Window position save panic on quit

**Root cause:** `runtime.WindowGetPosition()` could panic if called after the Wails window started tearing down.

**Fix:** `SaveWindowPosition()` wrapped in `recover()`.

**Files changed:**
- `app.go` — `recover()` in `SaveWindowPosition()`

---

## Fix 4: Window drag (jump to bottom-left on mousedown)

**Root cause:** `window.screenX/Y` returns 0 in Wails' WKWebView. The naive drag implementation moved the window to the wrong origin on every mousedown.

**Fix:** On `mousedown`, call the Wails IPC `WindowGetPosition()` to get the real screen coordinates. A 3px movement threshold prevents a plain click from triggering a move.

**Files changed:**
- `frontend/src/App.jsx` — `useDrag` hook using `WindowGetPosition` IPC; 3px threshold

---

## Fix 5: Minimum window size

**Fix:** Added `MinWidth: 300`, `MinHeight: 380` to `options.App` in `main.go`.

**Files changed:**
- `main.go` — `MinWidth: 300, MinHeight: 380`

---

## Commits

| Hash | Message |
|------|---------|
| `286d3d7` | `fix(quit): free whisper model before exit to prevent ggml-metal ASSERT` |
| `5c239f2` | `fix(quit): Unregister() before cancel in Stop() to prevent GCD workq crash` |
| `ff79fd7` | `fix(quit): doneCh-based wait so Stop() blocks until goroutine exits` |
| `b5e...` | `fix(quit): stop hotkey before runtime.Quit to prevent CGo/Cocoa panic` |
