package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync/atomic"

	"github.com/gordonklaus/portaudio"
)

// ErrMicPermissionDenied is returned when macOS has denied microphone access.
var ErrMicPermissionDenied = errors.New("microphone access denied — enable in System Settings → Privacy → Microphone")

const (
	audioSampleRate   = 16000 // Hz — Whisper's expected input rate
	audioChannels     = 1     // Mono
	audioFramesPerBuf = 512   // samples per callback frame
)

// audioBackend abstracts the real PortAudio implementation.
// Allows unit tests to inject a mock without a real microphone.
type audioBackend interface {
	Open() error
	Start() error
	Stop() error
	Close() error
	Frames() <-chan []float32
}

// realAudioBackend wraps gordonklaus/portaudio for production use.
type realAudioBackend struct {
	stream   *portaudio.Stream
	framesCh chan []float32
}

func newRealAudioBackend() *realAudioBackend {
	return &realAudioBackend{
		framesCh: make(chan []float32, 64), // buffered to avoid dropping frames
	}
}

func (r *realAudioBackend) Open() error {
	if err := portaudio.Initialize(); err != nil {
		return fmt.Errorf("portaudio init: %w", err)
	}

	buf := make([]float32, audioFramesPerBuf)
	stream, err := portaudio.OpenDefaultStream(
		audioChannels, // input channels
		0,             // output channels (none)
		float64(audioSampleRate),
		audioFramesPerBuf,
		func(in []float32) {
			// Copy the frame — portaudio reuses the buffer
			frame := make([]float32, len(in))
			copy(frame, in)
			select {
			case r.framesCh <- frame:
			default:
				// Drop frame if consumer is too slow (ring buffer handles overflow)
			}
		},
	)
	_ = buf // suppress unused warning
	if err != nil {
		portaudio.Terminate() //nolint:errcheck
		// Detect macOS microphone permission denial.
		errStr := strings.ToLower(err.Error())
		if strings.Contains(errStr, "denied") ||
			strings.Contains(errStr, "device unavailable") ||
			strings.Contains(errStr, "unauthorized") {
			return ErrMicPermissionDenied
		}
		return fmt.Errorf("portaudio open stream: %w", err)
	}
	r.stream = stream
	return nil
}

func (r *realAudioBackend) Start() error {
	if err := r.stream.Start(); err != nil {
		return fmt.Errorf("portaudio start stream: %w", err)
	}
	return nil
}

func (r *realAudioBackend) Stop() error {
	if err := r.stream.Stop(); err != nil {
		return fmt.Errorf("portaudio stop stream: %w", err)
	}
	close(r.framesCh)
	return nil
}

func (r *realAudioBackend) Close() error {
	err := r.stream.Close()
	portaudio.Terminate() //nolint:errcheck
	return err
}

func (r *realAudioBackend) Frames() <-chan []float32 {
	return r.framesCh
}

// AudioService manages microphone capture for voice-to-text.
// Audio is captured as float32 PCM into an in-memory RingBuffer.
// No audio data is ever written to disk.
type AudioService struct {
	backend   audioBackend
	ring      *RingBuffer
	recording atomic.Bool
}

// NewAudioService creates an AudioService backed by the real PortAudio API.
func NewAudioService() *AudioService {
	return &AudioService{
		backend: newRealAudioBackend(),
		ring:    NewRingBuffer(16000 * 60), // 60 seconds max @ 16kHz
	}
}

// newAudioServiceWithBackend creates an AudioService with injectable backend (for tests).
func newAudioServiceWithBackend(b audioBackend, rb *RingBuffer) *AudioService {
	return &AudioService{backend: b, ring: rb}
}

// StartRecording opens the microphone and begins capturing audio into the ring buffer.
// The goroutine exits when ctx is cancelled or StopRecording is called.
func (s *AudioService) StartRecording(ctx context.Context) error {
	if s.recording.Load() {
		return nil // already recording — idempotent
	}

	if err := s.backend.Open(); err != nil {
		if errors.Is(err, ErrMicPermissionDenied) {
			return ErrMicPermissionDenied // return sentinel unwrapped for errors.Is()
		}
		return fmt.Errorf("audio: open: %w", err)
	}
	if err := s.backend.Start(); err != nil {
		s.backend.Close() //nolint:errcheck
		return fmt.Errorf("audio: start: %w", err)
	}

	s.recording.Store(true)
	log.Printf("audio: recording started @ %dHz", audioSampleRate)

	frames := s.backend.Frames()

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case frame, ok := <-frames:
				if !ok {
					return
				}
				s.ring.Write(frame)
			}
		}
	}()

	return nil
}

// StopRecording stops audio capture and returns the sealed PCM buffer.
// The returned []float32 slice is safe to consume after the call.
// No data is written to disk at any point.
func (s *AudioService) StopRecording() ([]float32, error) {
	if !s.recording.Load() {
		return nil, nil
	}

	if err := s.backend.Stop(); err != nil {
		return nil, fmt.Errorf("audio: stop: %w", err)
	}
	if err := s.backend.Close(); err != nil {
		log.Printf("audio: close warning: %v", err)
	}

	s.recording.Store(false)
	pcm := s.ring.Drain()
	log.Printf("audio: recording stopped — captured %d samples (%.2fs)", len(pcm), float64(len(pcm))/float64(audioSampleRate))
	return pcm, nil
}

// IsRecording reports whether audio capture is currently active.
func (s *AudioService) IsRecording() bool {
	return s.recording.Load()
}
