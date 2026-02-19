package main

import (
	"context"
	"testing"
)

func TestNewApp(t *testing.T) {
	app := NewApp()
	if app == nil {
		t.Fatal("NewApp() returned nil")
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

// TestStartupIsIdempotent verifies startup() can be called and the app
// remains in a valid state (no panic, no data race).
// We can't call Wails runtime methods in tests (no running runtime),
// but we verify startup sets internal state without panic.
func TestStartupIsIdempotent(t *testing.T) {
	app := NewApp()
	ctx := context.Background()

	// Calling startup should not panic
	app.startup(ctx)

	// Calling it again (e.g. app restart scenario) should also not panic
	ctx2 := context.WithValue(ctx, struct{}{}, "v2")
	app.startup(ctx2)
}

// TestShowWindowBeforeStartupNoOps verifies calling ShowWindow before
// startup() is safe (no nil pointer panic).
func TestShowWindowBeforeStartupNoOps(t *testing.T) {
	app := NewApp()
	// Must not panic — ctx is nil at this point
	app.ShowWindow()
}

// TestQuitBeforeStartupNoOps verifies calling Quit before startup() is safe.
func TestQuitBeforeStartupNoOps(t *testing.T) {
	app := NewApp()
	// Must not panic — ctx is nil at this point
	app.Quit()
}
