package main

import (
	"context"
	"errors"
	"log"
	"os"
	"os/exec"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// hotkeyStarter is the minimal interface the App needs from HotkeyService.
// Using an interface keeps real CGo goroutines out of unit tests.
type hotkeyStarter interface {
	Start(ctx context.Context, onTrigger func()) error
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
	Start(whisperCh <-chan []float32, onResult func(string))
	IsLoaded() bool
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
	audio         audioStarter    // nil in unit tests; injected by main.go
	audioCtx      context.Context // cancelled when recording stops
	audioCancelFn context.CancelFunc
	whisperCh     chan []float32 // sealed PCM handed to Story 3 transcription
	whisper       whisperRunner  // nil in unit tests; injected by main.go
	output        outputRunner   // nil in unit tests; injected by main.go
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
		whisperCh:  make(chan []float32, 4), // buffered; Story 3 consumes
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

// startup is called by Wails when the runtime is ready.
func (a *App) startup(ctx context.Context) {
	a.mu.Lock()
	a.ctx = ctx
	a.mu.Unlock()
	a.once.Do(func() { close(a.startupCh) })

	// Start global hotkey listener — only if a service has been injected.
	if a.hotkeys != nil {
		hkCtx, cancel := context.WithCancel(ctx)
		a.hotkeyCtx = cancel
		if err := a.hotkeys.Start(hkCtx, a.onHotkeyTriggered); err != nil {
			if errors.Is(err, ErrHotkeyConflict) {
				log.Printf("hotkey: ⌃Space already registered by another app")
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
				log.Printf("whisper: model missing — download ggml-base.en.bin to ~/.voice-to-text/models/")
				runtime.EventsEmit(ctx, "model:missing")
			} else {
				log.Printf("whisper: load error: %v", err)
				runtime.EventsEmit(ctx, "model:missing")
			}
		} else {
			// Start consuming whisperCh in background.
			a.whisper.Start(a.whisperCh, func(text string) {
				a.mu.RLock()
				c := a.ctx
				a.mu.RUnlock()
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

	if a.audio.IsRecording() {
		// Stop recording → seal buffer → queue for transcription
		go func() {
			pcm, err := a.audio.StopRecording()
			if err != nil {
				log.Printf("audio: stop error: %v", err)
				runtime.EventsEmit(ctx, "audio:error")
				return
			}
			if len(pcm) > 0 {
				select {
				case a.whisperCh <- pcm:
					log.Printf("audio: %d samples queued for transcription", len(pcm))
				default:
					log.Printf("audio: whisperCh full — dropping recording")
				}
			}
			runtime.EventsEmit(ctx, "hotkey:triggered") // → processing state in React
		}()
	} else {
		// Start recording
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
	}()
}

// Quit exits the application.
func (a *App) Quit() {
	go func() {
		ctx := a.waitForStartup()
		runtime.Quit(ctx)
	}()
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
