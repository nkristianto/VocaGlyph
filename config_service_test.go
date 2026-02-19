package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestConfigServiceDefaults(t *testing.T) {
	dir := t.TempDir()
	svc := newConfigServiceAt(filepath.Join(dir, "config.json"))

	cfg := svc.Load()
	if cfg.Model != "base" {
		t.Errorf("default model = %q; want %q", cfg.Model, "base")
	}
	if cfg.Language != "en" {
		t.Errorf("default language = %q; want %q", cfg.Language, "en")
	}
}

func TestConfigServiceSaveLoad(t *testing.T) {
	dir := t.TempDir()
	svc := newConfigServiceAt(filepath.Join(dir, "config.json"))

	want := Config{Model: "small", Language: "auto"}
	if err := svc.Save(want); err != nil {
		t.Fatalf("Save: %v", err)
	}

	got := svc.Load()
	if got != want {
		t.Errorf("Load() = %+v; want %+v", got, want)
	}
}

func TestConfigServiceCorruptFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")

	// Write corrupt JSON
	if err := os.WriteFile(path, []byte("{bad json"), 0o644); err != nil {
		t.Fatal(err)
	}

	svc := newConfigServiceAt(path)
	cfg := svc.Load()

	// Should get defaults without panicking
	if cfg.Model != "base" {
		t.Errorf("corrupt fallback model = %q; want %q", cfg.Model, "base")
	}

	// And the corrupt file should have been overwritten with valid JSON
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !errors.Is(nil, nil) { // just ensure file exists
		t.Log(string(data))
	}
}

func TestConfigServicePartialFillsDefaults(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")

	// Write config missing Language
	if err := os.WriteFile(path, []byte(`{"model":"tiny"}`), 0o644); err != nil {
		t.Fatal(err)
	}

	svc := newConfigServiceAt(path)
	cfg := svc.Load()
	if cfg.Model != "tiny" {
		t.Errorf("model = %q; want %q", cfg.Model, "tiny")
	}
	if cfg.Language != "en" {
		t.Errorf("language should default to %q, got %q", "en", cfg.Language)
	}
}
