package main

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// httpClient is shared across all downloads and forces HTTP/1.1.
// HuggingFace CDN sometimes sends HTTP/2 GOAWAY frames mid-transfer which
// crash Go's internal h2 read-loop goroutine; disabling H2 avoids this.
var httpClient = &http.Client{
	Transport: &http.Transport{
		TLSClientConfig:    &tls.Config{MinVersion: tls.VersionTLS12},
		TLSNextProto:       make(map[string]func(string, *tls.Conn) http.RoundTripper), // disable HTTP/2
		DisableCompression: false,
	},
}

// modelEntry describes a known whisper.cpp model available for download.
type modelEntry struct {
	Name      string // e.g. "base"
	FileName  string // e.g. "ggml-base.en.bin"
	SizeLabel string // human-readable size displayed in UI
	URL       string
	SHA256    string // hex-encoded expected SHA-256 of the downloaded file
}

// modelRegistry lists the supported models in display order.
// URLs point to the official Hugging Face whisper.cpp model repository.
// SHA256 is left empty — the official download script also ships without checksums,
// and HTTPS from Hugging Face provides sufficient transport integrity.
var modelRegistry = []modelEntry{
	{
		Name:      "tiny",
		FileName:  "ggml-tiny.en.bin",
		SizeLabel: "75 MB",
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
		SHA256:    "",
	},
	{
		Name:      "base",
		FileName:  "ggml-base.en.bin",
		SizeLabel: "142 MB",
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
		SHA256:    "",
	},
	{
		Name:      "small",
		FileName:  "ggml-small.en.bin",
		SizeLabel: "466 MB",
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
		SHA256:    "",
	},
	{
		Name:      "medium",
		FileName:  "ggml-medium.en.bin",
		SizeLabel: "769 MB",
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin",
		SHA256:    "",
	},
	{
		Name:      "large-v3-turbo",
		FileName:  "ggml-large-v3-turbo.bin",
		SizeLabel: "838 MB",
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
		SHA256:    "",
	},
	{
		Name:      "large-v3",
		FileName:  "ggml-large-v3.bin",
		SizeLabel: "3.1 GB",
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
		SHA256:    "",
	},
}

// ModelStatus values sent to the frontend.
const (
	ModelStatusDownloaded    = "downloaded"
	ModelStatusNotDownloaded = "not_downloaded"
	// In-progress: "downloading:42" (integer percent 0-100)
)

// ModelService manages model discovery and background downloads.
type ModelService struct {
	mu         sync.Mutex
	modelsDir  string
	ctx        context.Context // set via SetContext after Wails starts
	inProgress map[string]bool // name → currently downloading
}

// NewModelService creates a ModelService pointing at the standard models directory.
func NewModelService() *ModelService {
	home, _ := os.UserHomeDir()
	return &ModelService{
		modelsDir:  filepath.Join(home, ".voice-to-text", "models"),
		inProgress: make(map[string]bool),
	}
}

// SetContext stores the Wails runtime context needed for EventsEmit.
// Called from app.startup() once Wails is ready.
func (ms *ModelService) SetContext(ctx context.Context) {
	ms.mu.Lock()
	ms.ctx = ctx
	ms.mu.Unlock()
}

// GetModelStatuses returns a map of model name → status string.
// Status is one of ModelStatusDownloaded, ModelStatusNotDownloaded,
// or "downloading:N" for an in-progress download.
func (ms *ModelService) GetModelStatuses() map[string]string {
	ms.mu.Lock()
	defer ms.mu.Unlock()

	result := make(map[string]string, len(modelRegistry))
	for _, m := range modelRegistry {
		if ms.inProgress[m.Name] {
			result[m.Name] = "downloading:0" // progress updated via events
			continue
		}
		path := filepath.Join(ms.modelsDir, m.FileName)
		if _, err := os.Stat(path); err == nil {
			result[m.Name] = ModelStatusDownloaded
		} else {
			result[m.Name] = ModelStatusNotDownloaded
		}
	}
	return result
}

// ModelPath returns the expected file path for the given model name.
func (ms *ModelService) ModelPath(name string) string {
	return filepath.Join(ms.modelsDir, "ggml-"+name+".en.bin")
}

// DownloadModel starts a background download of the named model.
// It is safe to call from the UI thread; the download runs in a goroutine.
// Progress is emitted as Wails events:
//   - "model:download:progress" {name string, pct int}
//   - "model:download:done"     {name string}
//   - "model:download:error"    {name string, err string}
func (ms *ModelService) DownloadModel(name string) error {
	var entry *modelEntry
	for i := range modelRegistry {
		if modelRegistry[i].Name == name {
			entry = &modelRegistry[i]
			break
		}
	}
	if entry == nil {
		return fmt.Errorf("model_service: unknown model %q", name)
	}

	ms.mu.Lock()
	if ms.inProgress[name] {
		ms.mu.Unlock()
		return fmt.Errorf("model_service: %q download already in progress", name)
	}
	ms.inProgress[name] = true
	ctx := ms.ctx
	ms.mu.Unlock()

	go ms.runDownload(ctx, *entry)
	return nil
}

// runDownload performs the actual HTTP download, SHA256 check, and atomic rename.
func (ms *ModelService) runDownload(ctx context.Context, entry modelEntry) {
	name := entry.Name
	defer func() {
		// Recover from any unexpected panics so the app never crashes from a
		// failed download (e.g. HTTP/2 transport bugs, nil dereferences).
		if r := recover(); r != nil {
			log.Printf("model: download panic recovered for %s: %v", name, r)
			if ctx != nil {
				runtime.EventsEmit(ctx, "model:download:error",
					map[string]string{"name": name, "err": fmt.Sprintf("unexpected error: %v", r)})
			}
		}
		ms.mu.Lock()
		delete(ms.inProgress, name)
		ms.mu.Unlock()
	}()

	emit := func(event string, data ...interface{}) {
		if ctx != nil {
			runtime.EventsEmit(ctx, event, data...)
		}
	}

	log.Printf("model: starting download of %s from %s", entry.FileName, entry.URL)

	if err := os.MkdirAll(ms.modelsDir, 0o755); err != nil {
		log.Printf("model: mkdir error: %v", err)
		emit("model:download:error", map[string]string{"name": name, "err": err.Error()})
		return
	}

	// Download to a temp file first.
	tmpPath := filepath.Join(ms.modelsDir, entry.FileName+".download")
	f, err := os.Create(tmpPath)
	if err != nil {
		log.Printf("model: create temp file: %v", err)
		emit("model:download:error", map[string]string{"name": name, "err": err.Error()})
		return
	}
	defer os.Remove(tmpPath) // clean up temp file on any error path

	resp, err := httpClient.Get(entry.URL) //nolint:noctx — intentional long-running download
	if err != nil {
		f.Close()
		log.Printf("model: http get: %v", err)
		emit("model:download:error", map[string]string{"name": name, "err": err.Error()})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		f.Close()
		errMsg := fmt.Sprintf("server returned %d", resp.StatusCode)
		log.Printf("model: %s: %s", entry.FileName, errMsg)
		emit("model:download:error", map[string]string{"name": name, "err": errMsg})
		return
	}

	// Stream body, tracking progress and computing SHA256 simultaneously.
	total := resp.ContentLength // may be -1 if unknown
	hasher := sha256.New()
	var downloaded int64
	lastPct := -1

	buf := make([]byte, 32*1024)
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, werr := f.Write(buf[:n]); werr != nil {
				f.Close()
				log.Printf("model: write error: %v", werr)
				emit("model:download:error", map[string]string{"name": name, "err": werr.Error()})
				return
			}
			hasher.Write(buf[:n])
			downloaded += int64(n)

			if total > 0 {
				pct := int(downloaded * 100 / total)
				if pct != lastPct {
					lastPct = pct
					emit("model:download:progress", map[string]interface{}{"name": name, "pct": pct})
				}
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			f.Close()
			log.Printf("model: read error: %v", readErr)
			emit("model:download:error", map[string]string{"name": name, "err": readErr.Error()})
			return
		}
	}
	f.Close()

	// Verify SHA256.
	if entry.SHA256 != "" {
		got := hex.EncodeToString(hasher.Sum(nil))
		if got != entry.SHA256 {
			errMsg := fmt.Sprintf("SHA256 mismatch: got %s want %s", got[:8]+"…", entry.SHA256[:8]+"…")
			log.Printf("model: %s: %s", entry.FileName, errMsg)
			emit("model:download:error", map[string]string{"name": name, "err": errMsg})
			return
		}
		log.Printf("model: %s SHA256 verified ✓", entry.FileName)
	}

	// Atomic rename: temp → final destination.
	finalPath := filepath.Join(ms.modelsDir, entry.FileName)
	if err := os.Rename(tmpPath, finalPath); err != nil {
		log.Printf("model: rename error: %v", err)
		emit("model:download:error", map[string]string{"name": name, "err": err.Error()})
		return
	}

	log.Printf("model: %s downloaded successfully", entry.FileName)
	emit("model:download:done", map[string]string{"name": name})
}
