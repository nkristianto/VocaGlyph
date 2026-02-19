package main

import (
	"context"
	"testing"
	"time"
)

func TestNewApp(t *testing.T) {
	app := NewApp()
	if app == nil {
		t.Fatal("NewApp() returned nil")
	}
	if app.startupCh == nil {
		t.Fatal("NewApp() startupCh must not be nil")
	}
}

func TestGetStatus(t *testing.T) {
	tests := []struct {
		name     string
		expected string
	}{
		{
			name:     "returns ready to dictate",
			expected: "Ready to dictate",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app := NewApp()
			got := app.GetStatus()
			if got != tt.expected {
				t.Errorf("GetStatus() = %q, want %q", got, tt.expected)
			}
		})
	}
}

// TestStartupUnblocksWaiters verifies that calling startup() causes
// waitForStartup() calls that were blocked to unblock and return the ctx.
func TestStartupUnblocksWaiters(t *testing.T) {
	app := NewApp()
	ctx := context.Background()

	done := make(chan context.Context, 1)
	go func() {
		done <- app.waitForStartup()
	}()

	// Give the goroutine a moment to block on startupCh
	time.Sleep(20 * time.Millisecond)

	app.startup(ctx)

	select {
	case got := <-done:
		if got != ctx {
			t.Errorf("waitForStartup() returned wrong context: got %v, want %v", got, ctx)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("waitForStartup() did not unblock after startup()")
	}
}

// TestStartupIsIdempotent verifies startup() can be called multiple times
// without panic (e.g. app restart scenario).
func TestStartupIsIdempotent(t *testing.T) {
	app := NewApp()
	ctx := context.Background()
	app.startup(ctx)
	// Second call must not panic or deadlock (once.Do is idempotent)
	app.startup(ctx)
}

// TestShowWindowBeforeStartupNoOps verifies ShowWindow before startup
// does not panic — it launches a goroutine that waits rather than no-oping.
// We just confirm it returns immediately (doesn't block the caller).
func TestShowWindowBeforeStartupNoOps(t *testing.T) {
	app := NewApp()
	done := make(chan struct{})
	go func() {
		app.ShowWindow() // must not block the caller goroutine
		close(done)
	}()
	select {
	case <-done:
		// ShowWindow returned immediately as expected
	case <-time.After(100 * time.Millisecond):
		t.Fatal("ShowWindow() blocked the caller goroutine unexpectedly")
	}
}

// TestQuitBeforeStartupNoOps verifies Quit before startup does not block caller.
func TestQuitBeforeStartupNoOps(t *testing.T) {
	app := NewApp()
	done := make(chan struct{})
	go func() {
		app.Quit() // must not block the caller goroutine
		close(done)
	}()
	select {
	case <-done:
		// Quit returned immediately as expected
	case <-time.After(100 * time.Millisecond):
		t.Fatal("Quit() blocked the caller goroutine unexpectedly")
	}
}
