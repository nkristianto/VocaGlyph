package main

import (
	"context"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App is the main application struct.
// ctx is guarded by mu to avoid a race between startup() and menu callbacks.
type App struct {
	mu  sync.RWMutex
	ctx context.Context
}

// NewApp creates a new App application struct.
func NewApp() *App {
	return &App{}
}

// startup is called by Wails when the app initialises.
// The context is stored under a lock so that menu callbacks that race
// against startup cannot observe a nil ctx.
func (a *App) startup(ctx context.Context) {
	a.mu.Lock()
	a.ctx = ctx
	a.mu.Unlock()
}

// ShowWindow shows the main settings window.
// Safe to call from any goroutine, including menu callbacks.
func (a *App) ShowWindow() {
	a.mu.RLock()
	ctx := a.ctx
	a.mu.RUnlock()
	if ctx == nil {
		return
	}
	runtime.WindowShow(ctx)
}

// Quit exits the application.
// Safe to call from any goroutine, including menu callbacks.
func (a *App) Quit() {
	a.mu.RLock()
	ctx := a.ctx
	a.mu.RUnlock()
	if ctx == nil {
		return
	}
	runtime.Quit(ctx)
}

// GetStatus returns the current app status displayed in the UI.
func (a *App) GetStatus() string {
	return "Ready to dictate"
}
