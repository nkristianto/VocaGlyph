package main

import (
	"context"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App is the main application struct.
// ctx is guarded by mu. startupCh is closed once startup() fires so that
// ShowWindow/Quit callers that arrive before Wails is ready can wait.
type App struct {
	mu        sync.RWMutex
	ctx       context.Context
	startupCh chan struct{}
	once      sync.Once
}

// NewApp creates a new App application struct.
func NewApp() *App {
	return &App{
		startupCh: make(chan struct{}),
	}
}

// startup is called by Wails when the runtime is ready.
// It stores the context and closes startupCh so any goroutine blocked
// in ShowWindow or Quit is unblocked.
func (a *App) startup(ctx context.Context) {
	a.mu.Lock()
	a.ctx = ctx
	a.mu.Unlock()
	a.once.Do(func() { close(a.startupCh) })
}

// waitForStartup blocks until Wails has initialised (startup() has been called).
func (a *App) waitForStartup() context.Context {
	<-a.startupCh
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.ctx
}

// ShowWindow shows the main settings window.
// If Wails hasn't initialised yet it waits up to the lifetime of the app.
// Must be called from a goroutine so it doesn't block the systray main thread.
func (a *App) ShowWindow() {
	go func() {
		ctx := a.waitForStartup()
		runtime.WindowShow(ctx)
	}()
}

// Quit exits the application.
// Must be called from a goroutine so it doesn't block the systray main thread.
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
