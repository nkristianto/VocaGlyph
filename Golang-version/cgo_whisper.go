package main

// CGo linker directives for whisper.cpp + ggml with Metal acceleration.
// The paths assume whisper.cpp is cloned at ../whisper.cpp relative to this module.
// Build whisper.cpp first:
//
//	cmake -B ../whisper.cpp/build ../whisper.cpp -DGGML_METAL=1 -DBUILD_SHARED_LIBS=OFF
//	cmake --build ../whisper.cpp/build --config Release -j$(nproc)

// #cgo CXXFLAGS: -std=c++17
// #cgo darwin LDFLAGS: -L${SRCDIR}/../whisper.cpp/build/src -lwhisper
// #cgo darwin LDFLAGS: -L${SRCDIR}/../whisper.cpp/build/ggml/src -lggml
// #cgo darwin LDFLAGS: -L${SRCDIR}/../whisper.cpp/build/ggml/src -lggml-base
// #cgo darwin LDFLAGS: -L${SRCDIR}/../whisper.cpp/build/ggml/src -lggml-cpu
// #cgo darwin LDFLAGS: -L${SRCDIR}/../whisper.cpp/build/ggml/src/ggml-metal -lggml-metal
// #cgo darwin LDFLAGS: -L${SRCDIR}/../whisper.cpp/build/ggml/src/ggml-blas -lggml-blas
// #cgo darwin LDFLAGS: -framework Accelerate -framework Foundation -framework Metal -framework MetalKit -framework MetalPerformanceShaders -framework CoreGraphics -framework Security
// #cgo CPPFLAGS: -I${SRCDIR}/../whisper.cpp/include -I${SRCDIR}/../whisper.cpp/ggml/include
import "C" //nolint:typecheck
