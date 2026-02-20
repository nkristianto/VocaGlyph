package main

/*
#cgo LDFLAGS: -framework ApplicationServices -framework Foundation
#include <stdlib.h>
#include "keystroke_darwin.h"
*/
import "C"

import (
	"fmt"
	"log"
	"os/exec"
	"strings"
	"time"
	"unsafe"
)

// outputter abstracts the two output strategies so we can swap them in tests.
type outputter interface {
	Paste(text string) error
	CopyToClipboard(text string) error
}

// OutputService tries to paste via osascript; falls back to clipboard.
type OutputService struct {
	backend outputter
}

// NewOutputService returns a production-ready OutputService.
func NewOutputService() *OutputService {
	return &OutputService{backend: &realOutputter{}}
}

// newOutputServiceWithBackend wires in a custom backend (tests only).
func newOutputServiceWithBackend(b outputter) *OutputService {
	return &OutputService{backend: b}
}

// Send attempts to paste text into the frontmost app.
// If paste fails it copies to clipboard and calls onFallback so the caller
// can notify the UI.
func (s *OutputService) Send(text string, onFallback func()) {
	if text == "" {
		return
	}
	start := time.Now()
	if err := s.backend.Paste(text); err != nil {
		log.Printf("output: paste failed (%v) — falling back to clipboard", err)
		if cbErr := s.backend.CopyToClipboard(text); cbErr != nil {
			log.Printf("output: clipboard fallback also failed: %v", cbErr)
			return
		}
		log.Printf("output: copied to clipboard")
		if onFallback != nil {
			onFallback()
		}
	} else {
		log.Printf("output: pasted %d chars via CGO CoreGraphics in %s", len(text), time.Since(start))
	}
}

// ── Real implementation ───────────────────────────────────

type realOutputter struct{}

// Paste uses native CGEventPost to keystroke text into the OS queue with zero latency.
func (r *realOutputter) Paste(text string) error {
	// 1. Check if we have accessibility permissions required for CGEventPost.
	// We pass true to prompt the user if they haven't granted it yet.
	if !C.is_accessibility_trusted(C.bool(true)) {
		return fmt.Errorf("accessibility permission denied — falling back to clipboard")
	}

	cstr := C.CString(text)
	defer C.free(unsafe.Pointer(cstr))

	success := C.post_keystrokes(cstr)
	if !success {
		return fmt.Errorf("CGEventPost failed to create events")
	}
	return nil
}

// CopyToClipboard writes text to the system clipboard via pbcopy.
func (r *realOutputter) CopyToClipboard(text string) error {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("pbcopy: %w — %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
