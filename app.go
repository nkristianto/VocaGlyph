package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// hotkeyStarter is the minimal interface the App needs from HotkeyService.
// Using an interface keeps real CGo goroutines out of unit tests.
type hotkeyStarter interface {
	Start(ctx context.Context, combo string, onTrigger func()) error
	Reregister(combo string) error
	Combo() string
	IsRegistered() bool
}

// audioStarter is the minimal interface the App needs from AudioService.
type audioStarter interface {
	StartRecording(ctx context.Context) error
	StopRecording() ([]float32, error)
	IsRecording() bool
}

// whisperRunner is the minimal interface the App needs from WhisperService.
type whisperRunner interface {
	Load() error
	Start(whisperCh <-chan TranscriptionJob, onResult func(string))
	IsLoaded() bool
	Reload(modelPath string) error
	Close() error // must be called before process exit to free Metal GPU resources
}

// outputRunner is the minimal interface the App needs from OutputService.
type outputRunner interface {
	Send(text string, onFallback func())
}

// App is the main application struct.
// ctx is guarded by mu. startupCh is closed once startup() fires so that
// ShowWindow/Quit callers that arrive before Wails is ready can wait.
type App struct {
	mu            sync.RWMutex
	ctx           context.Context
	startupCh     chan struct{}
	once          sync.Once
	loginItems    *LoginItemService
	hotkeys       hotkeyStarter // nil in unit tests; injected by main.go
	hotkeyCtx     context.CancelFunc
	audio         audioStarter // nil in unit tests; injected by main.go
	audioCtx      context.Context
	audioCancelFn context.CancelFunc
	whisperCh     chan TranscriptionJob
	whisper       whisperRunner  // nil in unit tests; injected by main.go
	output        outputRunner   // nil in unit tests; injected by main.go
	config        *ConfigService // nil in unit tests; injected by main.go
	modelService  *ModelService  // nil in unit tests; injected by main.go
	windowVisible bool
	activeContext string // captured text context when recording starts
}

// NewApp creates a new App application struct.
// audio/hotkeys are nil by default — main.go injects them via Set*() before wails.Run().
// This keeps CGo goroutines out of unit tests entirely.
func NewApp() *App {
	svc, err := NewLoginItemService()
	if err != nil {
		log.Printf("warning: failed to create LoginItemService: %v", err)
	}
	return &App{
		startupCh:  make(chan struct{}),
		loginItems: svc,
		whisperCh:  make(chan TranscriptionJob, 4), // buffered; Story 3 consumes
	}
}

// SetHotkeyService injects the hotkey service (called by main.go before wails.Run).
func (a *App) SetHotkeyService(hs hotkeyStarter) { a.hotkeys = hs }

// SetAudioService injects the audio service (called by main.go before wails.Run).
func (a *App) SetAudioService(as audioStarter) { a.audio = as }

// SetWhisperService injects the whisper transcription service (called by main.go before wails.Run).
func (a *App) SetWhisperService(ws whisperRunner) { a.whisper = ws }

// SetOutputService injects the text output service (called by main.go before wails.Run).
func (a *App) SetOutputService(os outputRunner) { a.output = os }

// SetConfigService injects the config persistence service (called by main.go before wails.Run).
func (a *App) SetConfigService(cs *ConfigService) { a.config = cs }

// SetModelService injects the model download/status service (called by main.go before wails.Run).
func (a *App) SetModelService(ms *ModelService) { a.modelService = ms }

// startup is called by Wails when the runtime is ready.
func (a *App) startup(ctx context.Context) {
	a.mu.Lock()
	a.ctx = ctx
	a.mu.Unlock()
	a.once.Do(func() { close(a.startupCh) })

	// Restore last window position (if saved).
	if a.config != nil {
		if cfg := a.config.Load(); cfg.WindowX != 0 || cfg.WindowY != 0 {
			runtime.WindowSetPosition(ctx, cfg.WindowX, cfg.WindowY)
		}
	}

	// Give the model service the runtime context for event emission.
	if a.modelService != nil {
		a.modelService.SetContext(ctx)
	}

	// Launch systray icon (mic) in menu bar after Wails/Cocoa is running.
	// HideFromDock() is called inside onSystrayReady on the Cocoa thread.
	go StartSystray(a)

	// Proactively trigger the macOS Accessibility permissions dialog
	// if it hasn't been granted yet (prevents spamming the user on every hotkey press).
	PromptAccessibility()

	// Start global hotkey listener — only if a service has been injected.
	if a.hotkeys != nil {
		hkCtx, cancel := context.WithCancel(ctx)
		a.hotkeyCtx = cancel
		combo := "ctrl+space"
		if a.config != nil {
			combo = a.config.Load().Hotkey
		}
		if err := a.hotkeys.Start(hkCtx, combo, a.onHotkeyTriggered); err != nil {
			if errors.Is(err, ErrHotkeyConflict) {
				log.Printf("hotkey: %s already registered by another app", combo)
				runtime.EventsEmit(ctx, "hotkey:conflict")
			} else {
				log.Printf("hotkey: failed to register: %v", err)
			}
		}
	}

	// Load whisper model — only if a service has been injected.
	if a.whisper != nil {
		if err := a.whisper.Load(); err != nil {
			if errors.Is(err, ErrModelNotFound) {
				log.Printf("whisper: model missing — download a model to ~/.voice-to-text/models/")
				runtime.EventsEmit(ctx, "model:missing")
			} else {
				log.Printf("whisper: load error: %v", err)
				runtime.EventsEmit(ctx, "model:missing")
			}
		}
		// Always start the consumer goroutine — it skips PCM buffers when the
		// model is not yet loaded (!s.loaded), so it is safe to call even on the
		// first-run path where Load() returned ErrModelNotFound. After the user
		// downloads a model and SetModel() calls Reload(), the goroutine will
		// automatically start transcribing because s.loaded becomes true.
		a.whisper.Start(a.whisperCh, func(text string) {
			a.mu.RLock()
			c := a.ctx
			a.mu.RUnlock()
			SetSysTrayState(0) // Return to Idle
			// Emit result to UI first so the overlay appears immediately.
			runtime.EventsEmit(c, "transcription:result", text)
			// Then attempt to paste; fall back to clipboard if needed.
			if a.output != nil {
				a.output.Send(text, func() {
					runtime.EventsEmit(c, "paste:fallback")
				})
			}
		})
	}
}

// onHotkeyTriggered is called from the hotkey goroutine on each ⌃Space press.
// Toggles recording: idle→start, recording→stop.
func (a *App) onHotkeyTriggered() {
	a.mu.RLock()
	ctx := a.ctx
	a.mu.RUnlock()

	if a.audio == nil {
		runtime.EventsEmit(ctx, "hotkey:triggered")
		return
	}

	// If no model is loaded yet, show the download banner instead of starting
	// a recording that will silently produce no transcription output.
	if a.whisper != nil && !a.whisper.IsLoaded() {
		log.Printf("hotkey: blocked — whisper model not loaded")
		runtime.EventsEmit(ctx, "model:missing")
		return
	}

	if a.audio.IsRecording() {
		// Capture the saved context from when recording started.
		// We append a strong instruction to the end of the context to suppress
		// common filler words (um, uh, ah) from the transcription.
		promptCtx := a.activeContext
		suppressInstruction := " Here is a clean, grammatically correct transcript without filler words or stutters:"
		if promptCtx != "" {
			promptCtx = promptCtx + suppressInstruction
		} else {
			promptCtx = suppressInstruction
		}

		// Stop recording → seal buffer → queue for transcription
		go func() {
			pcm, err := a.audio.StopRecording()
			if err != nil {
				log.Printf("audio: stop error: %v", err)
				SetSysTrayState(0) // error = back to idle
				runtime.EventsEmit(ctx, "audio:error")
				return
			}
			SetSysTrayState(2) // Processing state
			if len(pcm) > 0 {
				select {
				case a.whisperCh <- TranscriptionJob{PCM: pcm, Prompt: promptCtx}:
					log.Printf("audio: %d samples queued for transcription (context captured: %d chars)", len(pcm), len(promptCtx))
				default:
					log.Printf("audio: whisperCh full — dropping recording")
				}
			}
			runtime.EventsEmit(ctx, "hotkey:triggered") // → processing state in React
		}()
	} else {
		// Start recording

		// Capture UI text context right BEFORE recording starts, when the target
		// app is guaranteed to be in focus and the cursor is exactly where the
		// user is about to dictate.
		a.activeContext = captureContextText()

		recordCtx, cancel := context.WithCancel(ctx)
		a.audioCancelFn = cancel
		if err := a.audio.StartRecording(recordCtx); err != nil {
			cancel()
			if errors.Is(err, ErrMicPermissionDenied) {
				log.Printf("audio: microphone permission denied")
				runtime.EventsEmit(ctx, "audio:permission-denied")
			} else {
				log.Printf("audio: start error: %v", err)
				runtime.EventsEmit(ctx, "audio:error")
			}
			return
		}
		SetSysTrayState(1)                          // Recording state
		runtime.EventsEmit(ctx, "hotkey:triggered") // → recording state in React
	}
}

// waitForStartup blocks until Wails has initialised (startup() has been called).
func (a *App) waitForStartup() context.Context {
	<-a.startupCh
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.ctx
}

// ShowWindow shows the main settings window.
func (a *App) ShowWindow() {
	go func() {
		ctx := a.waitForStartup()
		runtime.WindowShow(ctx)
		a.mu.Lock()
		a.windowVisible = true
		a.mu.Unlock()
	}()
}

// ToggleWindow shows the window if hidden, or hides it if visible.
func (a *App) ToggleWindow() {
	go func() {
		ctx := a.waitForStartup()
		a.mu.Lock()
		if a.windowVisible {
			runtime.WindowHide(ctx)
			a.windowVisible = false
		} else {
			runtime.WindowShow(ctx)
			a.windowVisible = true
		}
		a.mu.Unlock()
	}()
}

// Quit exits the application.
func (a *App) Quit() {
	go func() {
		ctx := a.waitForStartup()
		// 1. Stop the hotkey service first — calls backend.Unregister() while the
		//    Cocoa event loop is still alive, then waits for the goroutine to exit.
		if hs, ok := a.hotkeys.(*HotkeyService); ok {
			hs.Stop()
		}
		// 2. Free the whisper model and Metal GPU resources BEFORE the Go runtime
		//    calls exit(). If we don't, ggml-metal's C++ static destructor asserts
		//    that residency sets are empty, crashing with SIGABRT.
		if a.whisper != nil {
			log.Printf("quit: closing whisper model to release Metal bindings...")
			if err := a.whisper.Close(); err != nil {
				log.Printf("quit: whisper.Close() error: %v", err)
			}
		}
		// Wait briefly to ensure CGo memory is fully reclaimed by ggml-metal queue.
		<-(time.After(100 * time.Millisecond))
		runtime.Quit(ctx)
	}()
}

// SaveWindowPosition persists the current window X/Y to config so it can be
// restored on the next launch. Called from OnBeforeClose in main.go.
func (a *App) SaveWindowPosition() {
	if a.config == nil {
		return
	}
	a.mu.RLock()
	ctx := a.ctx
	a.mu.RUnlock()
	if ctx == nil {
		return
	}
	// runtime.WindowGetPosition can panic if the window is hidden or the Wails
	// runtime is already tearing down — recover() keeps the quit clean.
	defer func() {
		if r := recover(); r != nil {
			log.Printf("config: recovered panic in SaveWindowPosition: %v", r)
		}
	}()
	x, y := runtime.WindowGetPosition(ctx)
	cfg := a.config.Load()
	cfg.WindowX = x
	cfg.WindowY = y
	if err := a.config.Save(cfg); err != nil {
		log.Printf("config: failed to save window position: %v", err)
	}
}

// GetConfig returns the current persisted configuration.
func (a *App) GetConfig() Config {
	if a.config == nil {
		return defaultConfig()
	}
	return a.config.Load()
}

// SetModel switches the active Whisper model, reloads it, and persists the change.
func (a *App) SetModel(model string) error {
	if a.config == nil || a.whisper == nil {
		return nil
	}
	var modelPath string
	if a.modelService != nil {
		modelPath = a.modelService.ModelPath(model)
	} else {
		// No ModelService — look up registry directly for correct filename.
		for _, m := range modelRegistry {
			if m.Name == model {
				home, _ := os.UserHomeDir()
				modelPath = filepath.Join(home, ".voice-to-text", "models", m.FileName)
				break
			}
		}
		if modelPath == "" {
			home, _ := os.UserHomeDir()
			modelPath = home + "/.voice-to-text/models/ggml-" + model + ".en.bin"
		}
	}
	// Check that the file exists before attempting to reload — return a
	// user-friendly error so the frontend can show a download prompt.
	if _, err := os.Stat(modelPath); os.IsNotExist(err) {
		return fmt.Errorf("model %q is not downloaded — click the download button first", model)
	}
	if err := a.whisper.Reload(modelPath); err != nil {
		return err
	}
	cfg := a.config.Load()
	cfg.Model = model
	return a.config.Save(cfg)
}

// GetModelStatuses returns the download status of each known model.
// Values: "downloaded", "not_downloaded", or "downloading:N" (N = 0-100).
func (a *App) GetModelStatuses() map[string]string {
	if a.modelService == nil {
		return map[string]string{}
	}
	return a.modelService.GetModelStatuses()
}

// DownloadModel starts a background download of the named model.
// Progress is streamed via "model:download:progress", "model:download:done",
// and "model:download:error" Wails events.
func (a *App) DownloadModel(name string) error {
	if a.modelService == nil {
		return fmt.Errorf("model service not available")
	}
	return a.modelService.DownloadModel(name)
}

// SetLanguage updates the transcription language and persists the change.
// The new language takes effect on the next model Reload or recording session.
func (a *App) SetLanguage(lang string) error {
	if a.config == nil {
		return nil
	}
	cfg := a.config.Load()
	cfg.Language = lang
	return a.config.Save(cfg)
}

// GetHotkey returns the current hotkey combo string (e.g. "ctrl+space").
func (a *App) GetHotkey() string {
	if a.hotkeys != nil {
		return a.hotkeys.Combo()
	}
	if a.config != nil {
		return a.config.Load().Hotkey
	}
	return "ctrl+space"
}

// SetHotkey changes the global hotkey to the given combo string.
// The change takes effect immediately (live re-register) and is persisted.
// Emits "hotkey:conflict" event and returns an error if the key is taken.
func (a *App) SetHotkey(combo string) error {
	if a.hotkeys == nil {
		return nil
	}
	if err := a.hotkeys.Reregister(combo); err != nil {
		a.mu.RLock()
		c := a.ctx
		a.mu.RUnlock()
		if c != nil {
			runtime.EventsEmit(c, "hotkey:conflict")
		}
		return err
	}
	if a.config != nil {
		cfg := a.config.Load()
		cfg.Hotkey = combo
		return a.config.Save(cfg)
	}
	return nil
}

// GetStatus returns the current app status displayed in the UI.
func (a *App) GetStatus() string {
	return "Ready to dictate"
}

// OpenSystemSettings opens the macOS Privacy & Security → Microphone pane.
// Exposed to the frontend via Wails JS binding so the permission badge can deep-link.
func (a *App) OpenSystemSettings() error {
	return exec.Command("open",
		"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
	).Run()
}

// GetHotkeyStatus returns the current hotkey registration status.
func (a *App) GetHotkeyStatus() string {
	if a.hotkeys != nil && a.hotkeys.IsRegistered() {
		return "registered"
	}
	return "unregistered"
}

// GetLaunchAtLogin reports whether the app is registered as a login item.
func (a *App) GetLaunchAtLogin() bool {
	if a.loginItems == nil {
		return false
	}
	return a.loginItems.IsEnabled()
}

// SetLaunchAtLogin enables or disables the launch-at-login login item.
func (a *App) SetLaunchAtLogin(enabled bool) error {
	if a.loginItems == nil {
		return nil
	}
	if enabled {
		execPath, err := os.Executable()
		if err != nil {
			return err
		}
		return a.loginItems.Enable(execPath)
	}
	return a.loginItems.Disable()
}
