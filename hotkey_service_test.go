package main

import (
	"context"
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

// ── Tests ────────────────────────────────────────────────

func TestHotkeyServiceStart(t *testing.T) {
	mock := newMockBackend()
	svc := newHotkeyServiceWithBackend(mock)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.Start(ctx, func() {}); err != nil {
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

	if err := svc.Start(ctx, func() {}); err != nil {
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

	err := svc.Start(ctx, func() {})
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
	if err := svc.Start(ctx, func() { triggered <- struct{}{} }); err != nil {
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
