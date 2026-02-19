package main

import (
	"errors"
	"testing"
)

// ── mock outputter ────────────────────────────────────────

type mockOutputter struct {
	pasteCalled     bool
	clipboardCalled bool
	pasteErr        error
	clipboardErr    error
	pastedText      string
	clipboardText   string
}

func (m *mockOutputter) Paste(text string) error {
	m.pasteCalled = true
	m.pastedText = text
	return m.pasteErr
}

func (m *mockOutputter) CopyToClipboard(text string) error {
	m.clipboardCalled = true
	m.clipboardText = text
	return m.clipboardErr
}

// ── tests ─────────────────────────────────────────────────

func TestOutputServicePasteSuccess(t *testing.T) {
	mock := &mockOutputter{}
	svc := newOutputServiceWithBackend(mock)

	fallbackCalled := false
	svc.Send("Hello world", func() { fallbackCalled = true })

	if !mock.pasteCalled {
		t.Error("Paste() not called")
	}
	if mock.pastedText != "Hello world" {
		t.Errorf("pastedText = %q; want %q", mock.pastedText, "Hello world")
	}
	if mock.clipboardCalled {
		t.Error("CopyToClipboard() should not be called on paste success")
	}
	if fallbackCalled {
		t.Error("onFallback should not fire on paste success")
	}
}

func TestOutputServiceClipboardFallback(t *testing.T) {
	mock := &mockOutputter{pasteErr: errors.New("accessibility denied")}
	svc := newOutputServiceWithBackend(mock)

	fallbackCalled := false
	svc.Send("Hello world", func() { fallbackCalled = true })

	if !mock.pasteCalled {
		t.Error("Paste() not called")
	}
	if !mock.clipboardCalled {
		t.Error("CopyToClipboard() should be called on paste failure")
	}
	if mock.clipboardText != "Hello world" {
		t.Errorf("clipboardText = %q; want %q", mock.clipboardText, "Hello world")
	}
	if !fallbackCalled {
		t.Error("onFallback should fire when falling back to clipboard")
	}
}

func TestOutputServiceBothFail(t *testing.T) {
	mock := &mockOutputter{
		pasteErr:     errors.New("accessibility denied"),
		clipboardErr: errors.New("pbcopy unavailable"),
	}
	svc := newOutputServiceWithBackend(mock)

	// Should not panic; onFallback must NOT be called when clipboard also fails.
	fallbackCalled := false
	svc.Send("Hello world", func() { fallbackCalled = true })

	if fallbackCalled {
		t.Error("onFallback should not fire when both paste and clipboard fail")
	}
}

func TestOutputServiceEmptyText(t *testing.T) {
	mock := &mockOutputter{}
	svc := newOutputServiceWithBackend(mock)

	svc.Send("", nil)

	if mock.pasteCalled || mock.clipboardCalled {
		t.Error("neither Paste nor CopyToClipboard should be called for empty text")
	}
}

func TestEscapeForAppleScript(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{`Hello "world"`, `Hello \"world\"`},
		{`back\slash`, `back\\slash`},
		{`both "quotes" and \backslash`, `both \"quotes\" and \\backslash`},
		{`plain text`, `plain text`},
	}
	for _, tc := range cases {
		got := escapeForAppleScript(tc.input)
		if got != tc.want {
			t.Errorf("escapeForAppleScript(%q) = %q; want %q", tc.input, got, tc.want)
		}
	}
}
