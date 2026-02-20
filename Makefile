WHISPER_DIR := $(HOME)/Workspace/Personal/whisper.cpp

export PKG_CONFIG_PATH := /opt/homebrew/lib/pkgconfig
export CGO_CPPFLAGS    := -I$(WHISPER_DIR)/include -I$(WHISPER_DIR)/ggml/include
export CGO_LDFLAGS     := \
	-L$(WHISPER_DIR)/build/src -lwhisper -lwhisper.coreml \
	-L$(WHISPER_DIR)/build/ggml/src -lggml -lggml-base -lggml-cpu \
	-L$(WHISPER_DIR)/build/ggml/src/ggml-metal -lggml-metal \
	-L$(WHISPER_DIR)/build/ggml/src/ggml-blas  -lggml-blas \
	-framework Accelerate -framework Foundation \
	-framework Metal -framework MetalKit -framework MetalPerformanceShaders \
	-framework CoreGraphics -framework Security -framework CoreML

.PHONY: whisper-build whisper-model build test dev

## Build whisper.cpp static libraries with Metal acceleration (one-time setup)
whisper-build:
	cmake -B $(WHISPER_DIR)/build $(WHISPER_DIR) \
		-DGGML_METAL=1 -DWHISPER_COREML=1 -DBUILD_SHARED_LIBS=OFF \
		-DWHISPER_COREML_ALLOW_FALLBACK=1 \
		-DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build $(WHISPER_DIR)/build --config Release -j$(shell sysctl -n hw.logicalcpu)

## Download whisper base.en model (~150 MB) and generate CoreML model
whisper-model:
	mkdir -p $(HOME)/.voice-to-text/models
	cd $(WHISPER_DIR) && sh models/download-ggml-model.sh base.en
	cp $(WHISPER_DIR)/models/ggml-base.en.bin $(HOME)/.voice-to-text/models/
	./scripts/generate-coreml.sh base.en

## Setup (first time): builds whisper.cpp and downloads model
setup: whisper-build whisper-model

## Compile the Go binary
build:
	go build ./...

## Run all tests
test:
	go test ./... -count=1 -timeout 30s

## Run wails dev with all required env vars set
dev:
	wails dev
