# Story 5.1 / 5.2 / 5.3: Model Management

**Status:** done
**Date:** 2026-02-20
**Commit:** 2845788

## Acceptance Criteria

**5.1 — Model Selection & Download**
- ✅ Model picker shows Tiny/Base/Small with status icons (✅/⬇/N%)
- ✅ Clicking a not-downloaded model triggers background HTTP download
- ✅ Progress streamed as `model:download:progress` events → button updates in real-time
- ✅ Download verified via SHA256 and atomically renamed into models dir
- ✅ `SetModel()` guards against selecting a non-downloaded model

**5.2 — First-Run Detection**
- ✅ `startup()` emits `model:missing` when whisper.Load() returns `ErrModelNotFound`
- ✅ Frontend shows `ModelMissingBanner` with download buttons for all 3 models
- ✅ Banner auto-hides and auto-selects model when download completes

**5.3 — Model Hot-Swap**
- ✅ Clicking a downloaded model calls `SetModel()` → `whisper.Reload()` → new model active immediately
- ✅ No app restart required

## New Files
- `model_service.go` — `ModelService`, HTTP download goroutine, SHA256 verify, atomic rename, `GetModelStatuses()`, `DownloadModel()`

## Modified Files
- `app.go` — `modelService` field, `SetModelService()`, `GetModelStatuses()`, `DownloadModel()` Wails-bound, `SetModel()` file-exists guard, `startup()` wires `SetContext()`
- `main.go` — `NewModelService()` injection
- `frontend/wailsjs/go/main/App.js` — `GetModelStatuses`, `DownloadModel` exports
- `frontend/src/App.jsx` — `ModelMissingBanner` component, `SettingsPanel` download status, `modelStatuses` state, `model:*` events, `handleModelDownload()`
- `frontend/src/App.css` — banner + button + status icon styles

## Events emitted by ModelService
| Event | Payload | When |
|-------|---------|------|
| `model:download:progress` | `{name, pct}` | Every % chunk during download |
| `model:download:done` | `{name}` | Download + SHA256 verified |
| `model:download:error` | `{name, err}` | Any failure |

## Change Log
- 2026-02-20: Stories 5.1, 5.2, 5.3 implemented and committed.
