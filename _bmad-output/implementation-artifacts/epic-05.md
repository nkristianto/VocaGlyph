# Epic 5: Native MLX Inference Implementation

Status: backlog

## Description

This Epic focuses on the core challenge of executing the Parakeet model (or other supported architectures) using Apple's MLX framework directly within the Swift native macOS application. While the infrastructure for loading states and routing audio to the engine was built in Epic 2, this Epic tackles the actual cross-language bridging, audio tensor processing, and neural network inference required to produce real transcriptions instead of placeholders.

## Technical Context

- Requires robust bridging between Swift's `[Float]` audio buffers and MLX Arrays.
- Involves memory management to ensure the models are executed efficiently on Apple Silicon Unified Memory without main thread locking.

## Stories

### Story 5.1: MLX Parakeet Inference
Status: backlog
- Implement the actual generation loop and MLX weights loading for the Parakeet model family.
- Replace the dummy placeholder string in `MLXEngine` with the true decoded text.
