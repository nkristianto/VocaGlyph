package main

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

// mockHotkeyBackend simulates hotkey registration without touching macOS APIs.
type mockHotkeyBackend struct {
	registered   atomic.Bool
	conflictMode bool          // if true, Register() returns an error
	keydownCh    chan struct{} // caller can send to simulate a keypress
}

func newMockBackend() *mockHotkeyBackend {
	return &mockHotkeyBackend{keydownCh: make(chan struct{}, 1)}
}

func (m *mockHotkeyBackend) Register() error {
	if m.conflictMode {
		return ErrHotkeyConflict
	}
	m.registered.Store(true)
	return nil
}

func (m *mockHotkeyBackend) Unregister() error {
	m.registered.Store(false)
	return nil
}

func (m *mockHotkeyBackend) Keydown() <-chan struct{} {
	return m.keydownCh
}

// simulatePress sends a synthetic keydown event to the mock backend.
func (m *mockHotkeyBackend) simulatePress() {
	m.keydownCh <- struct{}{}
}

// ── HotkeyService tests ───────────────────────────────────

func TestHotkeyServiceStart(t *testing.T) {
	mock := newMockBackend()
	svc := newHotkeyServiceWithBackend(mock)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.Start(ctx, "ctrl+space", func() {}); err != nil {
		t.Fatalf("Start() unexpected error: %v", err)
	}
	if !svc.IsRegistered() {
		t.Error("IsRegistered() = false after Start(); want true")
	}
}

func TestHotkeyServiceStop(t *testing.T) {
	mock := newMockBackend()
	svc := newHotkeyServiceWithBackend(mock)

	ctx, cancel := context.WithCancel(context.Background())

	if err := svc.Start(ctx, "ctrl+space", func() {}); err != nil {
		t.Fatalf("Start() error: %v", err)
	}

	cancel() // stopping via context cancellation
	time.Sleep(20 * time.Millisecond)

	if svc.IsRegistered() {
		t.Error("IsRegistered() = true after Stop(); want false")
	}
}

func TestHotkeyServiceConflict(t *testing.T) {
	mock := newMockBackend()
	mock.conflictMode = true
	svc := newHotkeyServiceWithBackend(mock)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	err := svc.Start(ctx, "ctrl+space", func() {})
	if err == nil {
		t.Fatal("Start() expected error for conflict; got nil")
	}
	if err != ErrHotkeyConflict {
		t.Errorf("Start() error = %v; want ErrHotkeyConflict", err)
	}
	if svc.IsRegistered() {
		t.Error("IsRegistered() = true after conflict; want false")
	}
}

func TestHotkeyServiceCallback(t *testing.T) {
	mock := newMockBackend()
	svc := newHotkeyServiceWithBackend(mock)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	triggered := make(chan struct{}, 1)
	if err := svc.Start(ctx, "ctrl+space", func() { triggered <- struct{}{} }); err != nil {
		t.Fatalf("Start() error: %v", err)
	}

	// Give the listener goroutine a moment to start
	time.Sleep(10 * time.Millisecond)
	mock.simulatePress()

	select {
	case <-triggered:
		// callback was invoked — success
	case <-time.After(500 * time.Millisecond):
		t.Fatal("callback not invoked after simulated keypress")
	}
}

// ── parseHotkey tests ─────────────────────────────────────

func TestParseHotkeyValid(t *testing.T) {
	cases := []struct {
		combo string
	}{
		{"ctrl+space"},
		{"option+f"},
		{"ctrl+shift+a"},
		{"cmd+z"},
		{"alt+1"},
		{"shift+f5"},
		{"CTRL+SPACE"}, // case insensitive
	}
	for _, tc := range cases {
		mods, key, err := parseHotkey(tc.combo)
		if err != nil {
			t.Errorf("parseHotkey(%q) error = %v; want nil", tc.combo, err)
			continue
		}
		if len(mods) == 0 {
			t.Errorf("parseHotkey(%q) returned no modifiers", tc.combo)
		}
		if key == 0 {
			t.Errorf("parseHotkey(%q) returned zero key", tc.combo)
		}
	}
}

func TestParseHotkeyInvalid(t *testing.T) {
	cases := []struct {
		combo string
	}{
		{"space"},        // no modifier
		{"ctrl+"},        // no key
		{"ctrl+unknown"}, // unknown key
		{"badmod+space"}, // unknown modifier
		{""},             // empty
	}
	for _, tc := range cases {
		_, _, err := parseHotkey(tc.combo)
		if err == nil {
			t.Errorf("parseHotkey(%q) expected error; got nil", tc.combo)
			continue
		}
		if !errors.Is(err, ErrHotkeyInvalid) {
			t.Errorf("parseHotkey(%q) error = %v; want ErrHotkeyInvalid", tc.combo, err)
		}
	}
}

// ── FormatHotkey tests ────────────────────────────────────

func TestFormatHotkey(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{"ctrl+space", "⌃Space"},
		{"option+f", "⌥F"},
		{"ctrl+shift+a", "⌃⇧A"},
		{"cmd+z", "⌘Z"},
	}
	for _, tc := range cases {
		got := FormatHotkey(tc.input)
		if got != tc.want {
			t.Errorf("FormatHotkey(%q) = %q; want %q", tc.input, got, tc.want)
		}
	}
}

// ── Reregister tests ──────────────────────────────────────

func TestHotkeyServiceReregister(t *testing.T) {
	mock := newMockBackend()
	svc := newHotkeyServiceWithBackend(mock)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.Start(ctx, "ctrl+space", func() {}); err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	if svc.Combo() != "ctrl+space" {
		t.Errorf("Combo() = %q; want \"ctrl+space\"", svc.Combo())
	}

	// Reregister with a new combo — mock always succeeds
	if err := svc.Reregister("option+f"); err != nil {
		t.Fatalf("Reregister() error: %v", err)
	}
	if svc.Combo() != "option+f" {
		t.Errorf("Combo() after Reregister = %q; want \"option+f\"", svc.Combo())
	}
	if !svc.IsRegistered() {
		t.Error("IsRegistered() = false after Reregister(); want true")
	}
}

func TestHotkeyServiceReregisterInvalid(t *testing.T) {
	mock := newMockBackend()
	svc := newHotkeyServiceWithBackend(mock)

	// Reregister without Start — should return ErrHotkeyInvalid for bad combo
	err := svc.Reregister("badmod+space")
	if err == nil {
		t.Fatal("Reregister(bad combo) expected error; got nil")
	}
	if !errors.Is(err, ErrHotkeyInvalid) {
		t.Errorf("error = %v; want ErrHotkeyInvalid", err)
	}
}
