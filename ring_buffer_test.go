package main

import (
	"sync"
	"testing"
)

func TestRingBufferWrite(t *testing.T) {
	rb := NewRingBuffer(1024)

	chunk := make([]float32, 128)
	for i := range chunk {
		chunk[i] = float32(i) * 0.1
	}

	rb.Write(chunk)

	if rb.Len() != 128 {
		t.Errorf("Len() = %d after Write(128), want 128", rb.Len())
	}
}

func TestRingBufferDrain(t *testing.T) {
	rb := NewRingBuffer(1024)

	written := []float32{0.1, 0.2, 0.3, 0.4}
	rb.Write(written)

	drained := rb.Drain()

	if len(drained) != len(written) {
		t.Fatalf("Drain() len = %d, want %d", len(drained), len(written))
	}
	for i, v := range written {
		if drained[i] != v {
			t.Errorf("Drain()[%d] = %f, want %f", i, drained[i], v)
		}
	}

	// Buffer should be empty after drain
	if rb.Len() != 0 {
		t.Errorf("Len() = %d after Drain(), want 0", rb.Len())
	}
}

func TestRingBufferOverflow(t *testing.T) {
	rb := NewRingBuffer(4) // capacity=4

	// Write 6 samples — oldest 2 should be dropped
	rb.Write([]float32{1, 2, 3, 4, 5, 6})

	drained := rb.Drain()
	// Should contain latest 4 samples
	if len(drained) != 4 {
		t.Fatalf("after overflow: len = %d, want 4", len(drained))
	}
	// Latest 4 samples are 3,4,5,6
	for i, want := range []float32{3, 4, 5, 6} {
		if drained[i] != want {
			t.Errorf("drained[%d] = %f, want %f", i, drained[i], want)
		}
	}
}

func TestRingBufferConcurrent(t *testing.T) {
	rb := NewRingBuffer(4096)
	var wg sync.WaitGroup

	// 4 concurrent writers
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 100; j++ {
				rb.Write([]float32{float32(j)})
			}
		}()
	}

	// 1 concurrent drainer
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 50; i++ {
			rb.Drain()
		}
	}()

	wg.Wait() // must not deadlock or panic
}
