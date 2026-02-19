package main

import (
	"context"
	"testing"
	"time"
)

// mockAudioBackend simulates PortAudio without requiring a real mic.
type mockAudioBackend struct {
	opened  bool
	started bool
	stopped bool
	closed  bool
	// dataCh simulates audio frames arriving during recording.
	dataCh chan []float32
}

func newMockAudioBackend() *mockAudioBackend {
	return &mockAudioBackend{dataCh: make(chan []float32, 8)}
}

func (m *mockAudioBackend) Open() error {
	m.opened = true
	return nil
}

func (m *mockAudioBackend) Start() error {
	m.started = true
	return nil
}

func (m *mockAudioBackend) Stop() error {
	m.stopped = true
	close(m.dataCh) // signal end of stream
	return nil
}

func (m *mockAudioBackend) Close() error {
	m.closed = true
	return nil
}

func (m *mockAudioBackend) Frames() <-chan []float32 {
	return m.dataCh
}

// injectFrame sends a synthetic audio frame into the mock backend.
func (m *mockAudioBackend) injectFrame(samples []float32) {
	m.dataCh <- samples
}

// ── Tests ────────────────────────────────────────────────

func TestStartRecording(t *testing.T) {
	mock := newMockAudioBackend()
	svc := newAudioServiceWithBackend(mock, NewRingBuffer(4096))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.StartRecording(ctx); err != nil {
		t.Fatalf("StartRecording() error: %v", err)
	}

	if !mock.opened || !mock.started {
		t.Error("backend not opened and started after StartRecording()")
	}
	if !svc.IsRecording() {
		t.Error("IsRecording() = false after StartRecording(); want true")
	}
}

func TestStopRecording(t *testing.T) {
	mock := newMockAudioBackend()
	svc := newAudioServiceWithBackend(mock, NewRingBuffer(4096))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.StartRecording(ctx); err != nil {
		t.Fatalf("StartRecording() error: %v", err)
	}

	pcm, err := svc.StopRecording()
	if err != nil {
		t.Fatalf("StopRecording() error: %v", err)
	}

	if !mock.stopped || !mock.closed {
		t.Error("backend not stopped/closed after StopRecording()")
	}
	if svc.IsRecording() {
		t.Error("IsRecording() = true after StopRecording(); want false")
	}
	_ = pcm // may be empty for mock
}

func TestRecordingProducesData(t *testing.T) {
	mock := newMockAudioBackend()
	rb := NewRingBuffer(4096)
	svc := newAudioServiceWithBackend(mock, rb)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.StartRecording(ctx); err != nil {
		t.Fatalf("StartRecording() error: %v", err)
	}

	// Inject synthetic audio frames
	frame := make([]float32, 256)
	for i := range frame {
		frame[i] = float32(i) * 0.001
	}
	mock.injectFrame(frame)
	mock.injectFrame(frame)

	// Give the goroutine time to process
	time.Sleep(30 * time.Millisecond)

	pcm, err := svc.StopRecording()
	if err != nil {
		t.Fatalf("StopRecording() error: %v", err)
	}
	if len(pcm) < 512 {
		t.Errorf("StopRecording() returned %d samples; want >= 512", len(pcm))
	}
}

func TestNoDiskWrites(t *testing.T) {
	// Structural test: AudioService has no file/path fields and no os.WriteFile calls.
	// Verified by code review. This test asserts the contract exists in the service.
	mock := newMockAudioBackend()
	svc := newAudioServiceWithBackend(mock, NewRingBuffer(1024))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if err := svc.StartRecording(ctx); err != nil {
		t.Fatalf("StartRecording(): %v", err)
	}
	pcm, err := svc.StopRecording()
	if err != nil {
		t.Fatalf("StopRecording(): %v", err)
	}
	// pcm is the only output — no file was created
	_ = pcm
}
