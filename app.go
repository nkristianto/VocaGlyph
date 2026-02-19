package main

import (
	"context"
	"errors"
	"log"
	"os"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// hotkeyStarter is the minimal interface the App needs from HotkeyService.
// Using an interface keeps real CGo goroutines out of unit tests.
type hotkeyStarter interface {
	Start(ctx context.Context, onTrigger func()) error
	IsRegistered() bool
}

// App is the main application struct.
// ctx is guarded by mu. startupCh is closed once startup() fires so that
// ShowWindow/Quit callers that arrive before Wails is ready can wait.
type App struct {
	mu         sync.RWMutex
	ctx        context.Context
	startupCh  chan struct{}
	once       sync.Once
	loginItems *LoginItemService
	hotkeys    hotkeyStarter // nil in unit tests; real HotkeyService in production
	hotkeyCtx  context.CancelFunc
}

// NewApp creates a new App application struct.
// hotkeys is intentionally nil — main.go injects a real HotkeyService
// via SetHotkeyService() before calling wails.Run(), keeping CGo goroutines
// out of unit tests entirely.
func NewApp() *App {
	svc, err := NewLoginItemService()
	if err != nil {
		log.Printf("warning: failed to create LoginItemService: %v", err)
	}
	return &App{
		startupCh:  make(chan struct{}),
		loginItems: svc,
		// hotkeys: nil — injected by main.go via SetHotkeyService()
	}
}

// SetHotkeyService injects the hotkey service (called by main.go before wails.Run).
func (a *App) SetHotkeyService(hs hotkeyStarter) {
	a.hotkeys = hs
}

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
		if err := a.hotkeys.Start(hkCtx, func() {
			a.mu.RLock()
			defer a.mu.RUnlock()
			runtime.EventsEmit(a.ctx, "hotkey:triggered")
		}); err != nil {
			if errors.Is(err, ErrHotkeyConflict) {
				log.Printf("hotkey: ⌃Space is already registered by another app — using app menu only")
				runtime.EventsEmit(ctx, "hotkey:conflict")
			} else {
				log.Printf("hotkey: failed to register: %v", err)
			}
		}
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

// GetHotkeyStatus returns the current hotkey registration status.
func (a *App) GetHotkeyStatus() string {
	if a.hotkeys.IsRegistered() {
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
