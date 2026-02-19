package main

import (
	"context"
	"errors"
	"log"
	"sync/atomic"

	"golang.design/x/hotkey"
)

// ErrHotkeyConflict is returned when the hotkey is already registered by another app.
var ErrHotkeyConflict = errors.New("hotkey: key combination already registered by another application")

// hotkeyBackend abstracts the real hotkey implementation so tests can use a mock.
type hotkeyBackend interface {
	Register() error
	Unregister() error
	Keydown() <-chan struct{}
}

// realHotkeyBackend wraps golang.design/x/hotkey for production use.
// The hotkey.Hotkey is created lazily in Register() to avoid spawning CGo
// goroutines at construction time — which would leak into unit tests.
type realHotkeyBackend struct {
	hk *hotkey.Hotkey
}

func newRealBackend() *realHotkeyBackend {
	return &realHotkeyBackend{}
}

func (r *realHotkeyBackend) Register() error {
	// Lazy creation — hotkey.New spawns internal goroutines; defer until needed.
	r.hk = hotkey.New([]hotkey.Modifier{hotkey.ModCtrl}, hotkey.KeySpace)
	err := r.hk.Register()
	if err != nil {
		return ErrHotkeyConflict
	}
	return nil
}

func (r *realHotkeyBackend) Unregister() error {
	if r.hk == nil {
		return nil
	}
	return r.hk.Unregister()
}

// Keydown wraps the hotkey.Event channel into a plain struct{} channel.
func (r *realHotkeyBackend) Keydown() <-chan struct{} {
	ch := make(chan struct{}, 1)
	go func() {
		for range r.hk.Keydown() {
			ch <- struct{}{}
		}
	}()
	return ch
}

// HotkeyService manages global hotkey registration for voice-to-text.
type HotkeyService struct {
	backend    hotkeyBackend
	registered atomic.Bool
}

// NewHotkeyService creates a HotkeyService backed by the real macOS hotkey API.
func NewHotkeyService() *HotkeyService {
	return &HotkeyService{backend: newRealBackend()}
}

// newHotkeyServiceWithBackend creates a HotkeyService with a custom backend (for tests).
func newHotkeyServiceWithBackend(b hotkeyBackend) *HotkeyService {
	return &HotkeyService{backend: b}
}

// Start registers the hotkey and launches a listener goroutine that calls onTrigger
// each time the hotkey is pressed. The goroutine exits when ctx is cancelled.
// Returns ErrHotkeyConflict if the key is taken by another app.
func (s *HotkeyService) Start(ctx context.Context, onTrigger func()) error {
	if err := s.backend.Register(); err != nil {
		return err
	}
	s.registered.Store(true)
	log.Printf("hotkey: ⌃Space registered")

	keydown := s.backend.Keydown()

	go func() {
		defer func() {
			s.backend.Unregister() //nolint:errcheck
			s.registered.Store(false)
			log.Printf("hotkey: ⌃Space unregistered")
		}()
		for {
			select {
			case <-ctx.Done():
				return
			case _, ok := <-keydown:
				if !ok {
					return
				}
				log.Printf("hotkey: ⌃Space triggered")
				onTrigger()
			}
		}
	}()
	return nil
}

// IsRegistered reports whether the hotkey is currently registered.
func (s *HotkeyService) IsRegistered() bool {
	return s.registered.Load()
}
