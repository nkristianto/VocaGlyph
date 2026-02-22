package main

import (
	"sync"
)

// RingBuffer is a thread-safe circular buffer for float32 PCM audio samples.
// When the buffer is full, the oldest samples are overwritten (drop oldest).
// This is intentional for live dictation — we never want to block the audio callback.
type RingBuffer struct {
	mu   sync.Mutex
	buf  []float32
	cap  int
	head int // index of next write position
	len  int // number of valid samples
}

// NewRingBuffer creates a new RingBuffer with the given capacity (in samples).
func NewRingBuffer(capacity int) *RingBuffer {
	return &RingBuffer{
		buf: make([]float32, capacity),
		cap: capacity,
	}
}

// Write appends samples to the ring buffer. If the buffer would overflow,
// the oldest samples are dropped to make room.
func (rb *RingBuffer) Write(samples []float32) {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	for _, s := range samples {
		rb.buf[rb.head] = s
		rb.head = (rb.head + 1) % rb.cap
		if rb.len < rb.cap {
			rb.len++
		}
		// When full, head has advanced past the oldest sample — it is now lost.
	}
}

// Drain returns all buffered samples as a contiguous slice and resets the buffer.
// The returned slice is safe to use after the call (it's a copy).
func (rb *RingBuffer) Drain() []float32 {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	if rb.len == 0 {
		return nil
	}

	out := make([]float32, rb.len)

	// The oldest sample is at (head - len + cap) % cap
	start := (rb.head - rb.len + rb.cap) % rb.cap
	for i := 0; i < rb.len; i++ {
		out[i] = rb.buf[(start+i)%rb.cap]
	}

	// Reset
	rb.head = 0
	rb.len = 0

	return out
}

// Len returns the number of samples currently held in the buffer.
func (rb *RingBuffer) Len() int {
	rb.mu.Lock()
	defer rb.mu.Unlock()
	return rb.len
}
