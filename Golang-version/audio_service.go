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
// Uses the BLOCKING stream API (stream.Read in a Go goroutine) rather than
// the callback API — callbacks run on a C thread and calling Go runtime
// functions (make, channel sends) from C threads causes goroutine panics.
type realAudioBackend struct {
	stream   *portaudio.Stream
	buf      []float32 // shared read buffer
	framesCh chan []float32
	stopCh   chan struct{} // closed by Stop() to signal reader goroutine
}

func newRealAudioBackend() *realAudioBackend {
	return &realAudioBackend{}
}

func (r *realAudioBackend) Open() error {
	if err := portaudio.Initialize(); err != nil {
		return fmt.Errorf("portaudio init: %w", err)
	}

	r.buf = make([]float32, audioFramesPerBuf)
	r.framesCh = make(chan []float32, 64) // fresh channel each session
	r.stopCh = make(chan struct{})

	// Blocking stream: pass a []float32 buffer, not a callback.
	stream, err := portaudio.OpenDefaultStream(
		audioChannels,
		0,
		float64(audioSampleRate),
		audioFramesPerBuf,
		r.buf, // <-- blocking API: portaudio fills this on each Read()
	)
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

	// Reader goroutine: blocks on stream.Read(), copies buffer, sends to framesCh.
	// Runs on a proper Go goroutine — safe to use Go runtime functions.
	go func() {
		defer close(r.framesCh) // clean up without racing against Stop()
		for {
			select {
			case <-r.stopCh:
				return
			default:
			}

			if err := r.stream.Read(); err != nil {
				return // stream stopped or error
			}

			// Copy the filled buffer before next Read() overwrites it.
			frame := make([]float32, len(r.buf))
			copy(frame, r.buf)

			select {
			case r.framesCh <- frame:
			case <-r.stopCh:
				return
			default:
				// Consumer too slow — drop frame; ring buffer handles overflow
			}
		}
	}()

	return nil
}

func (r *realAudioBackend) Stop() error {
	close(r.stopCh) // signal reader goroutine to exit
	err := r.stream.Stop()
	// The reader goroutine will close r.framesCh when it exits.
	if err != nil {
		return fmt.Errorf("portaudio stop stream: %w", err)
	}
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
