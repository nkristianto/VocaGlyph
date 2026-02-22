package main

import (
	"os"
	"path/filepath"
	"testing"
)

// newTestLoginItemService returns a LoginItemService that writes to a temp dir.
func newTestLoginItemService(t *testing.T) *LoginItemService {
	t.Helper()
	return &LoginItemService{plistDir: t.TempDir()}
}

func TestEnable(t *testing.T) {
	svc := newTestLoginItemService(t)
	execPath := "/Applications/voice-to-text.app/Contents/MacOS/voice-to-text"

	if err := svc.Enable(execPath); err != nil {
		t.Fatalf("Enable() unexpected error: %v", err)
	}

	plistPath := filepath.Join(svc.plistDir, plistFilename)
	data, err := os.ReadFile(plistPath)
	if err != nil {
		t.Fatalf("plist not created at %s: %v", plistPath, err)
	}

	content := string(data)
	if want := plistLabel; !containsString(content, want) {
		t.Errorf("plist missing label %q", want)
	}
	if !containsString(content, execPath) {
		t.Errorf("plist missing execPath %q", execPath)
	}
}

func TestDisable(t *testing.T) {
	svc := newTestLoginItemService(t)

	if err := svc.Enable("/usr/local/bin/voice-to-text"); err != nil {
		t.Fatalf("Enable() error: %v", err)
	}
	if err := svc.Disable(); err != nil {
		t.Fatalf("Disable() error: %v", err)
	}

	plistPath := filepath.Join(svc.plistDir, plistFilename)
	if _, err := os.Stat(plistPath); !os.IsNotExist(err) {
		t.Errorf("plist still exists after Disable(); stat err: %v", err)
	}
}

func TestIsEnabled(t *testing.T) {
	svc := newTestLoginItemService(t)

	if svc.IsEnabled() {
		t.Error("IsEnabled() = true before Enable(); want false")
	}

	if err := svc.Enable("/usr/local/bin/voice-to-text"); err != nil {
		t.Fatalf("Enable() error: %v", err)
	}
	if !svc.IsEnabled() {
		t.Error("IsEnabled() = false after Enable(); want true")
	}
}

func TestToggleRoundtrip(t *testing.T) {
	svc := newTestLoginItemService(t)
	exec := "/Applications/voice-to-text.app/Contents/MacOS/voice-to-text"

	// off → on → off → on
	for i, enable := range []bool{true, false, true} {
		var err error
		if enable {
			err = svc.Enable(exec)
		} else {
			err = svc.Disable()
		}
		if err != nil {
			t.Fatalf("step %d: error: %v", i, err)
		}
		if got := svc.IsEnabled(); got != enable {
			t.Errorf("step %d: IsEnabled() = %v, want %v", i, got, enable)
		}
	}
}

func TestDisableWhenNotEnabled(t *testing.T) {
	svc := newTestLoginItemService(t)
	// Disable when plist doesn't exist — must not error
	if err := svc.Disable(); err != nil {
		t.Errorf("Disable() on non-existent plist returned error: %v", err)
	}
}

// containsString is a simple substring check to avoid importing strings in test.
func containsString(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(substr) == 0 ||
		func() bool {
			for i := 0; i <= len(s)-len(substr); i++ {
				if s[i:i+len(substr)] == substr {
					return true
				}
			}
			return false
		}())
}
