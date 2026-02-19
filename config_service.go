package main

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
)

// Config holds persistent user preferences.
// Stored as JSON at ~/.voice-to-text/config.json.
type Config struct {
	Model    string `json:"model"`    // "tiny", "base", "small"
	Language string `json:"language"` // "en", "auto", "es", etc.
	Hotkey   string `json:"hotkey"`   // e.g. "ctrl+space", "option+f"
}

// defaultConfig returns factory defaults.
func defaultConfig() Config {
	return Config{Model: "base", Language: "en", Hotkey: "ctrl+space"}
}

// ConfigService loads and saves user configuration.
type ConfigService struct {
	path string
}

// NewConfigService creates a ConfigService pointing to the standard config path.
func NewConfigService() *ConfigService {
	home, _ := os.UserHomeDir()
	return &ConfigService{
		path: filepath.Join(home, ".voice-to-text", "config.json"),
	}
}

// newConfigServiceAt creates a ConfigService with a custom path (tests only).
func newConfigServiceAt(path string) *ConfigService {
	return &ConfigService{path: path}
}

// Load reads config from disk. Returns defaults if the file doesn't exist.
// If the file is corrupt it logs the error and writes fresh defaults.
func (c *ConfigService) Load() Config {
	data, err := os.ReadFile(c.path)
	if os.IsNotExist(err) {
		return defaultConfig()
	}
	if err != nil {
		log.Printf("config: read error: %v — using defaults", err)
		return defaultConfig()
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		log.Printf("config: parse error: %v — resetting to defaults", err)
		defaults := defaultConfig()
		_ = c.Save(defaults) // overwrite corrupt file
		return defaults
	}
	// Fill any zero-value fields with defaults.
	d := defaultConfig()
	if cfg.Model == "" {
		cfg.Model = d.Model
	}
	if cfg.Language == "" {
		cfg.Language = d.Language
	}
	if cfg.Hotkey == "" {
		cfg.Hotkey = d.Hotkey
	}
	return cfg
}

// Save writes the config to disk atomically (write to temp, then rename).
func (c *ConfigService) Save(cfg Config) error {
	if err := os.MkdirAll(filepath.Dir(c.path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	tmp := c.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, c.path)
}
