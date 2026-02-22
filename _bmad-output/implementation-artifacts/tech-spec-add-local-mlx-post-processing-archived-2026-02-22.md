---
title: 'Add Local MLX Post-Processing Engine'
slug: 'add-local-mlx-post-processing'
created: '2026-02-22T18:01:47+07:00'
status: 'in-progress'
stepsCompleted: [1]
tech_stack: []
files_to_modify: []
code_patterns: []
test_patterns: []
---

# Tech-Spec: Add Local MLX Post-Processing Engine

**Created:** 2026-02-22T18:01:47+07:00

## Overview

### Problem Statement

Currently, the application supports Apple Intelligence and external AI models (Anthropic, Gemini APIs) for post-processing transcription text. Users need a local LLM post-processing option (like the Qwen model) that runs 100% offline without relying on cloud APIs or OS-level Apple Foundation Models.

### Solution

Implement a `LocalMLXEngine` (or `QwenEngine`) conforming to the `PostProcessingEngine` protocol. Update the central Orchestrator (`AppStateManager`) to route requests to this new engine when selected, and update the UI (`SettingsView` / `SettingsViewModel`) to allow users to select a local model and manage its options.

### Scope

**In Scope:**
- Creating a new `LocalMLXEngine` struct conforming to `PostProcessingEngine`.
- Updating `AppStateManager` to support the local MLX routing state.
- Updating `SettingsViewModel` and `SettingsView` to enable selection of the local model option.

**Out of Scope:**
- Automatic downloading of models from HuggingFace (unless explicitly requested otherwise).

## Context for Development

### Codebase Patterns

- **Project Context:** Must use `mlx-swift` (>= 0.22.0) for Apple Silicon inference.
- **Concurrency:** Inference must be strictly isolated from the `@MainActor` using Swift 6 concurrency (`globalactor` or `actor`).
- **Protocols:** Must conform to the `PostProcessingEngine` protocol (which is `Sendable`).

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `architecture.md` | Provides architectural guidance and engine protocols. |

### Technical Decisions

- The engine will handle loading the model into memory and performing inference.
- UI elements will not directly talk to the MLX engine; they will pass intents through the central Orchestrator.

## Implementation Plan

### Tasks

### Acceptance Criteria

## Additional Context

### Dependencies

### Testing Strategy

### Notes
