package main

import (
	"fmt"
	"os"
	"path/filepath"
	"text/template"
)

const (
	plistLabel    = "com.voice-to-text"
	plistFilename = plistLabel + ".plist"
)

// plistTemplate is the launchd property list template for login-at-launch.
// RunAtLoad=true  → start app when user logs in.
// KeepAlive=false → don't restart if it exits cleanly.
var plistTemplate = template.Must(template.New("plist").Parse(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{{.Label}}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{.ExecPath}}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
`))

// LoginItemService manages the macOS launchd login item for voice-to-text.
// It creates/removes a plist in plistDir (default: ~/Library/LaunchAgents).
// plistDir is overridable for unit tests (use t.TempDir()).
type LoginItemService struct {
	plistDir string
}

// NewLoginItemService returns a LoginItemService pointing at the user's
// LaunchAgents directory.
func NewLoginItemService() (*LoginItemService, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("login item: failed to resolve home dir: %w", err)
	}
	return &LoginItemService{
		plistDir: filepath.Join(home, "Library", "LaunchAgents"),
	}, nil
}

// Enable writes the launchd plist so the app launches at login.
// execPath is the path to the executable to launch (usually the .app bundle binary).
func (s *LoginItemService) Enable(execPath string) error {
	if err := os.MkdirAll(s.plistDir, 0o755); err != nil {
		return fmt.Errorf("login item: cannot create LaunchAgents dir: %w", err)
	}

	f, err := os.Create(s.plistPath())
	if err != nil {
		return fmt.Errorf("login item: cannot create plist: %w", err)
	}
	defer f.Close()

	data := struct {
		Label    string
		ExecPath string
	}{
		Label:    plistLabel,
		ExecPath: execPath,
	}
	if err := plistTemplate.Execute(f, data); err != nil {
		return fmt.Errorf("login item: failed to write plist: %w", err)
	}
	return nil
}

// Disable removes the launchd plist, preventing launch at login.
// Returns nil if the plist does not exist (idempotent).
func (s *LoginItemService) Disable() error {
	err := os.Remove(s.plistPath())
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("login item: cannot remove plist: %w", err)
	}
	return nil
}

// IsEnabled reports whether the login item plist currently exists.
func (s *LoginItemService) IsEnabled() bool {
	_, err := os.Stat(s.plistPath())
	return err == nil
}

// plistPath returns the full path to the launchd plist file.
func (s *LoginItemService) plistPath() string {
	return filepath.Join(s.plistDir, plistFilename)
}
