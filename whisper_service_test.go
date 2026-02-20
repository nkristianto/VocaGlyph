package main

import (
	"errors"
	"testing"
	"time"
)

// mockWhisperBackend simulates whisper.cpp without loading a real model.
type mockWhisperBackend struct {
	loadCalled       bool
	transcribeCalled bool
	loadErr          error
	transcribeResult string
	transcribeErr    error
}

func (m *mockWhisperBackend) Load(_ string) error {
	m.loadCalled = true
	return m.loadErr
}

func (m *mockWhisperBackend) Transcribe(_ []float32, _ string) (string, error) {
	m.transcribeCalled = true
	return m.transcribeResult, m.transcribeErr
}

func (m *mockWhisperBackend) Close() error { return nil }

// ── Tests ────────────────────────────────────────────────

func TestWhisperServiceLoad(t *testing.T) {
	mock := &mockWhisperBackend{}
	svc := newWhisperServiceWithBackend(mock, "/fake/model.bin")

	if err := svc.Load(); err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if !mock.loadCalled {
		t.Error("backend.Load() not called")
	}
	if !svc.IsLoaded() {
		t.Error("IsLoaded() = false after successful Load()")
	}
}

func TestWhisperServiceModelNotFound(t *testing.T) {
	// Use real backend to test ErrModelNotFound for a non-existent path.
	svc := NewWhisperService("/nonexistent/model.bin")

	err := svc.Load()
	if err == nil {
		t.Fatal("Load() should return error for missing model; got nil")
	}
	if !errors.Is(err, ErrModelNotFound) {
		t.Errorf("Load() error = %v; want ErrModelNotFound", err)
	}
	if svc.IsLoaded() {
		t.Error("IsLoaded() = true after failed Load()")
	}
}

func TestWhisperServiceTranscribe(t *testing.T) {
	mock := &mockWhisperBackend{transcribeResult: "Hello world"}
	svc := newWhisperServiceWithBackend(mock, "/fake/model.bin")

	if err := svc.Load(); err != nil {
		t.Fatalf("Load(): %v", err)
	}

	resultCh := make(chan string, 1)
	whisperCh := make(chan TranscriptionJob, 1)

	svc.Start(whisperCh, func(text string) {
		resultCh <- text
	})

	// Send a fake job
	whisperCh <- TranscriptionJob{PCM: make([]float32, 1600), Prompt: "context"}
	close(whisperCh)

	select {
	case text := <-resultCh:
		if text != "Hello world" {
			t.Errorf("result = %q; want %q", text, "Hello world")
		}
	case <-time.After(2 * time.Second):
		t.Error("timeout waiting for transcription result")
	}
}
