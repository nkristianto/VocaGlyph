package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	// NOTE: This import requires the go.mod replace directive pointing to ../whisper.cpp/bindings/go
	// and libwhisper.a built with GGML_METAL=1. See the Makefile for build instructions.
	whisperlib "github.com/ggerganov/whisper.cpp/bindings/go/pkg/whisper"
)

// ErrModelNotFound is returned when the Whisper model file is missing.
var ErrModelNotFound = errors.New("whisper model not found — download with: sh models/download-ggml-model.sh base.en")

// whisperBackend abstracts the actual whisper.cpp bindings.
// Keeps CGo and model loading out of unit tests.
type whisperBackend interface {
	Load(modelPath string) error
	Transcribe(pcm []float32) (string, error)
	Close() error
}

// realWhisperBackend wraps github.com/ggerganov/whisper.cpp/bindings/go.
type realWhisperBackend struct {
	model   whisperlib.Model
	context whisperlib.Context
}

func newRealWhisperBackend() *realWhisperBackend {
	return &realWhisperBackend{}
}

func (r *realWhisperBackend) Load(modelPath string) error {
	if _, err := os.Stat(modelPath); os.IsNotExist(err) {
		return ErrModelNotFound
	}

	model, err := whisperlib.New(modelPath)
	if err != nil {
		return fmt.Errorf("whisper: load model %q: %w", modelPath, err)
	}
	r.model = model

	ctx, err := model.NewContext()
	if err != nil {
		model.Close()
		return fmt.Errorf("whisper: create context: %w", err)
	}

	ctx.SetLanguage("en") //nolint:errcheck — "en" is always valid

	// ── Speed tuning ──────────────────────────────────────────────────────
	// Goal: minimise transcription latency for short dictation bursts.
	//
	// SetThreads: M4 has 10 cores (4e+6p); 8 keeps UI/audio threads free.
	ctx.SetThreads(8)
	// SetBeamSize(2): balanced quality/speed. beam_size=5 (default) is most
	// accurate but explores 5 candidate paths; beam_size=1 (greedy) is fastest
	// but may miss words in longer/complex sentences. beam_size=2 gives ~2x
	// speedup vs default with negligible quality loss for short dictation clips.
	ctx.SetBeamSize(2)
	// SetAudioCtx: reduce encoder context from 1500→768 frames (~15s→~7.5s).
	// Any recording longer than ~7.5s uses the full window anyway; for typical
	// 1–5s dictation bursts this halves the encoder compute.
	ctx.SetAudioCtx(768)
	// SetMaxContext(0): each recording is independent — don't feed previous
	// segment tokens as context into the next decode pass.
	ctx.SetMaxContext(0)

	r.context = ctx
	return nil
}

func (r *realWhisperBackend) Transcribe(pcm []float32) (string, error) {
	if r.context == nil {
		return "", fmt.Errorf("whisper: not loaded")
	}

	if err := r.context.Process(pcm, nil, nil, nil); err != nil {
		return "", fmt.Errorf("whisper: process: %w", err)
	}

	var text string
	for {
		seg, err := r.context.NextSegment()
		if err != nil {
			break // io.EOF — no more segments
		}
		text += seg.Text
	}
	return text, nil
}

func (r *realWhisperBackend) Close() error {
	if r.model != nil {
		return r.model.Close()
	}
	return nil
}

// WhisperService manages model loading and transcription.
// It consumes PCM buffers from whisperCh and calls onResult with the text.
type WhisperService struct {
	backend   whisperBackend
	modelPath string
	loaded    bool
}

// NewWhisperService creates a WhisperService backed by the real whisper.cpp CGo bindings.
func NewWhisperService(modelPath string) *WhisperService {
	return &WhisperService{
		backend:   newRealWhisperBackend(),
		modelPath: modelPath,
	}
}

// newWhisperServiceWithBackend creates a WhisperService with a custom backend (for tests).
func newWhisperServiceWithBackend(b whisperBackend, modelPath string) *WhisperService {
	return &WhisperService{backend: b, modelPath: modelPath}
}

// Load loads the Whisper model into memory. Call once at startup.
// Returns ErrModelNotFound if the .bin file doesn't exist.
func (s *WhisperService) Load() error {
	if err := s.backend.Load(s.modelPath); err != nil {
		return err
	}
	s.loaded = true
	log.Printf("whisper: model loaded from %q", s.modelPath)
	return nil
}

// Start begins consuming PCM buffers from whisperCh in a goroutine.
// Each buffer is transcribed and the result passed to onResult.
// Returns immediately — the goroutine exits when whisperCh is closed.
func (s *WhisperService) Start(whisperCh <-chan []float32, onResult func(string)) {
	go func() {
		for pcm := range whisperCh {
			if !s.loaded {
				log.Printf("whisper: model not loaded — skipping %d samples", len(pcm))
				continue
			}
			log.Printf("whisper: transcribing %d samples (%.2fs)…", len(pcm), float64(len(pcm))/16000)
			t0 := time.Now()
			text, err := s.backend.Transcribe(pcm)
			latency := time.Since(t0)
			if err != nil {
				log.Printf("whisper: transcription error: %v", err)
				continue
			}
			text = trim(text)
			if text == "" {
				log.Printf("whisper: empty transcription — skipping")
				continue
			}
			if isHallucination(text) {
				log.Printf("whisper: hallucination tag %q — skipping", text)
				continue
			}
			if latency > 500*time.Millisecond {
				log.Printf("whisper: ⚠ slow transcription %q (%dms — exceeds 500ms NFR)", text, latency.Milliseconds())
			} else {
				log.Printf("whisper: ✓ %q (%dms)", text, latency.Milliseconds())
			}
			onResult(text)
		}
	}()
}

// IsLoaded reports whether the model has been successfully loaded.
func (s *WhisperService) IsLoaded() bool {
	return s.loaded
}

// Reload closes the current model and loads a new one from modelPath.
// Used when the user switches models in Settings. Safe to call at runtime;
// audio queued in whisperCh will be processed with the new model once loaded.
func (s *WhisperService) Reload(modelPath string) error {
	s.loaded = false
	if err := s.backend.Close(); err != nil {
		log.Printf("whisper: reload: close error (non-fatal): %v", err)
	}
	s.modelPath = modelPath
	return s.Load()
}

// Close releases model resources.
func (s *WhisperService) Close() error {
	return s.backend.Close()
}

// trim removes leading/trailing spaces and common whisper artifacts.
func trim(s string) string {
	for len(s) > 0 && (s[0] == ' ' || s[0] == '\n') {
		s = s[1:]
	}
	for len(s) > 0 && (s[len(s)-1] == ' ' || s[len(s)-1] == '\n') {
		s = s[:len(s)-1]
	}
	return s
}

// isHallucination reports whether the text is a known whisper.cpp hallucination tag
// produced during silence or noise (e.g. "[BLANK_AUDIO]", "(Music)", "(noise)").
func isHallucination(s string) bool {
	tags := []string{
		"[BLANK_AUDIO]",
		"[blank_audio]",
		"(Music)",
		"(music)",
		"(noise)",
		"(Noise)",
		"[MUSIC]",
		"[Music]",
		"(clapping)",
		"(Applause)",
		"[silence]",
	}
	for _, tag := range tags {
		if s == tag {
			return true
		}
	}
	// Also catch variations wrapped in brackets/parens that appear alone
	return len(s) > 2 && ((s[0] == '[' && s[len(s)-1] == ']') || (s[0] == '(' && s[len(s)-1] == ')'))
}
