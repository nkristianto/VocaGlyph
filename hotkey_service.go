package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.design/x/hotkey"
)

// ErrHotkeyConflict is returned when the hotkey is already registered by another app.
var ErrHotkeyConflict = errors.New("hotkey: key combination already registered by another application")

// ErrHotkeyInvalid is returned when the hotkey string cannot be parsed.
var ErrHotkeyInvalid = errors.New("hotkey: invalid key combination")

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
	hk        *hotkey.Hotkey
	mods      []hotkey.Modifier
	key       hotkey.Key
	keyCh     chan struct{} // buffered relay; filled once in Register()
	closeOnce sync.Once     // guards close(keyCh) to prevent double-close panic
}

func newRealBackend() *realHotkeyBackend {
	mods, key, _ := parseHotkey("ctrl+space")
	return &realHotkeyBackend{mods: mods, key: key}
}

func newRealBackendFromCombo(combo string) (*realHotkeyBackend, error) {
	mods, key, err := parseHotkey(combo)
	if err != nil {
		return nil, err
	}
	return &realHotkeyBackend{mods: mods, key: key}, nil
}

func (r *realHotkeyBackend) Register() error {
	r.hk = hotkey.New(r.mods, r.key)
	if err := r.hk.Register(); err != nil {
		// Clean up any CGo/OS-level state created by hotkey.New() to prevent
		// goroutine leaks and panics when the abandoned object is GC'd.
		_ = r.hk.Unregister()
		r.hk = nil
		return ErrHotkeyConflict
	}
	// Create a buffered relay channel and pump events into it.
	// This goroutine owns the hk.Keydown() read loop; it exits when hk channel closes.
	r.keyCh = make(chan struct{}, 4)
	src := r.hk.Keydown()
	go func() {
		for range src {
			select {
			case r.keyCh <- struct{}{}:
			default: // drop if buffer full (rapid presses)
			}
		}
		// close only once — prevents panic if Unregister races with a second close
		r.closeOnce.Do(func() { close(r.keyCh) })
	}()
	return nil
}

func (r *realHotkeyBackend) Unregister() error {
	if r.hk == nil {
		return nil
	}
	return r.hk.Unregister()
}

// Keydown returns the relay channel. No goroutine spawned here.
func (r *realHotkeyBackend) Keydown() <-chan struct{} {
	return r.keyCh
}

// HotkeyService manages global hotkey registration for voice-to-text.
type HotkeyService struct {
	mu             sync.Mutex
	backend        hotkeyBackend
	combo          string // current hotkey combo string e.g. "ctrl+space"
	registered     atomic.Bool
	shuttingDown   atomic.Bool        // set during app quit; defers skip CGo Unregister
	doneCh         chan struct{}      // closed when the active listen goroutine exits
	parentCtx      context.Context    // root context from Start() — used by Reregister
	cancel         context.CancelFunc // cancels the listen goroutine
	onTrigger      func()
	backendFactory func(string) (hotkeyBackend, error) // factory for new backends
}

// NewHotkeyService creates a HotkeyService backed by the real macOS hotkey API.
func NewHotkeyService() *HotkeyService {
	return &HotkeyService{
		backend: newRealBackend(),
		combo:   "ctrl+space",
		backendFactory: func(c string) (hotkeyBackend, error) {
			return newRealBackendFromCombo(c)
		},
	}
}

// newHotkeyServiceWithBackend creates a HotkeyService with a custom backend (for tests).
func newHotkeyServiceWithBackend(b hotkeyBackend) *HotkeyService {
	return &HotkeyService{
		backend: b,
		combo:   "ctrl+space",
		backendFactory: func(c string) (hotkeyBackend, error) {
			_, _, err := parseHotkey(c)
			if err != nil {
				return nil, err
			}
			return b, nil
		},
	}
}

// Start registers the hotkey and launches a listener goroutine that calls onTrigger
// each time the hotkey is pressed. The goroutine exits when ctx is cancelled.
// Returns ErrHotkeyConflict if the key is taken by another app.
func (s *HotkeyService) Start(ctx context.Context, combo string, onTrigger func()) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// If a combo was provided, swap backend to use it.
	if combo != "" && combo != s.combo {
		b, err := s.backendFactory(combo)
		if err != nil {
			return err
		}
		s.backend = b
		s.combo = combo
	}

	if err := s.backend.Register(); err != nil {
		return err
	}
	s.registered.Store(true)
	s.onTrigger = onTrigger
	s.parentCtx = ctx // save so Reregister can inherit the right parent
	log.Printf("hotkey: %s registered", s.combo)

	listenCtx, cancel := context.WithCancel(ctx)
	s.cancel = cancel
	curBackend := s.backend // capture NOW — prevents Reregister() swap from affecting this defer
	curCombo := s.combo
	keydown := curBackend.Keydown()
	// Each listen goroutine gets a fresh doneCh. Store it under the lock
	// so Reregister() and Stop() can safely swap it.
	doneCh := make(chan struct{})
	s.doneCh = doneCh
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("hotkey: recovered panic during Start cleanup (CGo/shutdown race): %v", r)
			}
			// Skip CGo call during app shutdown — the OS cleans up the event monitor.
			if !s.shuttingDown.Load() {
				curBackend.Unregister() //nolint:errcheck
			}
			s.registered.Store(false)
			log.Printf("hotkey: %s unregistered", curCombo)
			close(doneCh) // signal that this goroutine has fully exited
		}()
		for {
			select {
			case <-listenCtx.Done():
				return
			case _, ok := <-keydown:
				if !ok {
					return
				}
				log.Printf("hotkey: %s triggered", curCombo)
				onTrigger()
			}
		}
	}()
	return nil
}

// Reregister swaps to a new hotkey combo at runtime without restarting the app.
// Returns ErrHotkeyConflict if the new combo is taken, ErrHotkeyInvalid if unparseable.
// On any error the original hotkey stays registered.
func (s *HotkeyService) Reregister(newCombo string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	newBackend, err := s.backendFactory(newCombo)
	if err != nil {
		return err
	}
	// Try registering the new key first — before unregistering the old one.
	if err := newBackend.Register(); err != nil {
		return err // conflict — old hotkey still live
	}
	// New key is registered; unregister old one and stop old listen goroutine.
	if s.cancel != nil {
		s.cancel()
	}
	oldCombo := s.combo

	s.backend = newBackend
	s.combo = newCombo
	s.registered.Store(true)
	log.Printf("hotkey: re-registered %s → %s", oldCombo, newCombo)

	// Restart the listen goroutine with a new context derived from the stored parent.
	// Using parentCtx (from Start) ensures the goroutine is cancelled when the app shuts down,
	// not just when context.Background() is cleaned up (which is never).
	parent := s.parentCtx
	if parent == nil {
		parent = context.Background()
	}
	listenCtx, cancel := context.WithCancel(parent)
	s.cancel = cancel
	trigger := s.onTrigger
	// Replace doneCh so Stop() always waits on the LATEST goroutine.
	newDoneCh := make(chan struct{})
	s.doneCh = newDoneCh
	keydown := newBackend.Keydown()
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("hotkey: recovered panic during Reregister cleanup (CGo/shutdown race): %v", r)
			}
			// Skip CGo call during app shutdown — the OS cleans up the event monitor.
			if !s.shuttingDown.Load() {
				newBackend.Unregister() //nolint:errcheck
			}
			s.registered.Store(false)
			log.Printf("hotkey: %s unregistered", newCombo)
			close(newDoneCh) // signal exit
		}()
		for {
			select {
			case <-listenCtx.Done():
				return
			case _, ok := <-keydown:
				if !ok {
					return
				}
				log.Printf("hotkey: %s triggered", newCombo)
				if trigger != nil {
					trigger()
				}
			}
		}
	}()
	return nil
}

// Stop signals that the app is shutting down.
// It explicitly calls backend.Unregister() BEFORE cancelling the goroutine
// context, so the GCD/NSEvent callback block is removed while the Cocoa
// event loop is still alive. This prevents a workq crash when Cocoa tears
// down the GCD work queue while our monitor block is still registered.
// It then waits up to 200ms for the goroutine to exit before returning,
// ensuring no CGo callbacks are in-flight when runtime.Quit() runs.
func (s *HotkeyService) Stop() {
	s.shuttingDown.Store(true)

	s.mu.Lock()
	backend := s.backend
	doneCh := s.doneCh
	if s.cancel != nil {
		s.cancel() // unblocks goroutine's select
	}
	s.mu.Unlock()

	// Unregister NOW, while the Cocoa event loop is still running.
	// The goroutine defer will skip its own Unregister() since shuttingDown is set.
	if backend != nil {
		if err := backend.Unregister(); err != nil {
			log.Printf("hotkey: Unregister in Stop() returned: %v", err)
		}
	}

	// Wait for the goroutine to acknowledge cancellation and fully exit.
	if doneCh != nil {
		select {
		case <-doneCh:
			// clean exit
		case <-time.After(200 * time.Millisecond):
			log.Printf("hotkey: Stop() timed out waiting for goroutine to exit")
		}
	}
}

// IsRegistered reports whether the hotkey is currently registered.
func (s *HotkeyService) IsRegistered() bool {
	return s.registered.Load()
}

// Combo returns the currently active hotkey combo string.
func (s *HotkeyService) Combo() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.combo
}

// ── parseHotkey ──────────────────────────────────────────────────────────────
// Parses a combo string like "ctrl+space", "option+f", "ctrl+shift+a"
// into golang.design/x/hotkey modifiers + key.

var modMap = map[string]hotkey.Modifier{
	"ctrl":    hotkey.ModCtrl,
	"control": hotkey.ModCtrl,
	"option":  hotkey.ModOption,
	"alt":     hotkey.ModOption,
	"shift":   hotkey.ModShift,
	"cmd":     hotkey.ModCmd,
	"command": hotkey.ModCmd,
}

var keyMap = map[string]hotkey.Key{
	"space":  hotkey.KeySpace,
	"tab":    hotkey.KeyTab,
	"return": hotkey.KeyReturn,
	"enter":  hotkey.KeyReturn,
	"a":      hotkey.KeyA, "b": hotkey.KeyB, "c": hotkey.KeyC, "d": hotkey.KeyD,
	"e": hotkey.KeyE, "f": hotkey.KeyF, "g": hotkey.KeyG, "h": hotkey.KeyH,
	"i": hotkey.KeyI, "j": hotkey.KeyJ, "k": hotkey.KeyK, "l": hotkey.KeyL,
	"m": hotkey.KeyM, "n": hotkey.KeyN, "o": hotkey.KeyO, "p": hotkey.KeyP,
	"q": hotkey.KeyQ, "r": hotkey.KeyR, "s": hotkey.KeyS, "t": hotkey.KeyT,
	"u": hotkey.KeyU, "v": hotkey.KeyV, "w": hotkey.KeyW, "x": hotkey.KeyX,
	"y": hotkey.KeyY, "z": hotkey.KeyZ,
	"0": hotkey.Key0, "1": hotkey.Key1, "2": hotkey.Key2, "3": hotkey.Key3,
	"4": hotkey.Key4, "5": hotkey.Key5, "6": hotkey.Key6, "7": hotkey.Key7,
	"8": hotkey.Key8, "9": hotkey.Key9,
	"f1": hotkey.KeyF1, "f2": hotkey.KeyF2, "f3": hotkey.KeyF3, "f4": hotkey.KeyF4,
	"f5": hotkey.KeyF5, "f6": hotkey.KeyF6, "f7": hotkey.KeyF7, "f8": hotkey.KeyF8,
	"f9": hotkey.KeyF9, "f10": hotkey.KeyF10, "f11": hotkey.KeyF11, "f12": hotkey.KeyF12,
}

// parseHotkey parses a combo string into hotkey modifiers and key.
func parseHotkey(combo string) ([]hotkey.Modifier, hotkey.Key, error) {
	parts := strings.Split(strings.ToLower(strings.TrimSpace(combo)), "+")
	if len(parts) < 2 {
		return nil, 0, fmt.Errorf("%w: %q (need at least one modifier)", ErrHotkeyInvalid, combo)
	}
	keyPart := parts[len(parts)-1]
	modParts := parts[:len(parts)-1]

	key, ok := keyMap[keyPart]
	if !ok {
		return nil, 0, fmt.Errorf("%w: unknown key %q", ErrHotkeyInvalid, keyPart)
	}

	var mods []hotkey.Modifier
	seen := map[string]bool{}
	for _, m := range modParts {
		if seen[m] {
			continue
		}
		seen[m] = true
		mod, ok := modMap[m]
		if !ok {
			return nil, 0, fmt.Errorf("%w: unknown modifier %q", ErrHotkeyInvalid, m)
		}
		mods = append(mods, mod)
	}
	if len(mods) == 0 {
		return nil, 0, fmt.Errorf("%w: no valid modifier in %q", ErrHotkeyInvalid, combo)
	}
	return mods, key, nil
}

// FormatHotkey converts a combo string to a user-friendly display string.
// e.g. "ctrl+space" → "⌃Space", "option+f" → "⌥F", "ctrl+shift+a" → "⌃⇧A"
func FormatHotkey(combo string) string {
	parts := strings.Split(strings.ToLower(strings.TrimSpace(combo)), "+")
	if len(parts) < 2 {
		return combo
	}
	modSymbols := map[string]string{
		"ctrl": "⌃", "control": "⌃",
		"option": "⌥", "alt": "⌥",
		"shift": "⇧",
		"cmd":   "⌘", "command": "⌘",
	}
	keyDisplay := map[string]string{
		"space": "Space", "tab": "Tab", "return": "Return", "enter": "Return",
	}

	var out strings.Builder
	for _, p := range parts[:len(parts)-1] {
		if s, ok := modSymbols[p]; ok {
			out.WriteString(s)
		}
	}
	key := parts[len(parts)-1]
	if d, ok := keyDisplay[key]; ok {
		out.WriteString(d)
	} else {
		out.WriteString(strings.ToUpper(key))
	}
	return out.String()
}
