package main

import (
	"fmt"
	"log"
	"os/exec"
	"strings"
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
		log.Printf("output: pasted %d chars via osascript", len(text))
	}
}

// ── Real implementation ───────────────────────────────────

type realOutputter struct{}

// Paste uses osascript to keystroke text into the frontmost application.
// Special characters (quotes, backslashes) are escaped to prevent injection.
func (r *realOutputter) Paste(text string) error {
	escaped := escapeForAppleScript(text)
	script := fmt.Sprintf(
		`tell application "System Events" to keystroke "%s"`,
		escaped,
	)
	cmd := exec.Command("osascript", "-e", script)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("osascript: %w — %s", err, strings.TrimSpace(string(out)))
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

// escapeForAppleScript escapes characters that are special inside an
// AppleScript double-quoted string literal.
func escapeForAppleScript(s string) string {
	// Backslash must be first to avoid double-escaping.
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}
