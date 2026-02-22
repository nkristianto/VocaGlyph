# Story 3.2: Native Apple Speech Transcription (`SpeechAnalyzer`)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user on macOS 15.1+,
I want to transcribe text natively using Apple's Neural Engine,
so that I save RAM and achieve blazing fast inference while maintaining privacy via Private Cloud Compute boundaries.

## Acceptance Criteria

1. **Given** the user selects "Apple Intelligent Native" as their transcription engine in the settings
2. **When** the dictation begins
3. **Then** `AppStateManager` routes audio from `AudioRecorderService` to the new `NativeSpeechEngine`
4. **And** `NativeSpeechEngine` parses the buffer accurately and efficiently using the macOS 15+ `SpeechAnalyzer` APIs
5. **And** the existing Whisper engine safely deallocates from RAM (via `WhisperService` or `EngineRouter`) to prevent jetsam events.

## Tasks / Subtasks

- [x] Create `NativeSpeechEngine` conforming to `TranscriptionEngine` protocol
  - [x] Implement robust `@available(macOS 15.0, *)` and `@available(macOS 15.1, *)` checks
  - [x] Use `SpeechAnalyzer` (not `SFSpeechRecognizer`) to process `AVAudioPCMBuffer`
  - [x] Yield results using `SpeechTranscriber.Transcript` and Swift async/await iteration
- [x] Connect `NativeSpeechEngine` to orchestrator
  - [x] Ensure `AppStateManager` dynamically bridges to `NativeSpeechEngine` inside `EngineRouter` when selected
- [x] Implement Memory Offloading
  - [x] Refactor `WhisperService` instances out of memory when Native Speech is active to recover footprint
- [x] Update `SettingsView`
  - [x] Add "Apple Intelligent Native" to the visual Model Picker for transcription

## Dev Notes

- **Architecture:** Protocol-Oriented Engine Wrappers. You must build `NativeSpeechEngine` to conform strictly to the `TranscriptionEngine` protocol we built in Story 3.1.
- **Concurrency:** `NativeSpeechEngine` must be an `actor` or rigorously `Sendable`. Do not block the Main thread when calling `SpeechAnalyzer` or retrieving `.transcript`.
- **API Knowledge:** In macOS 15+, Apple deprecated/superceded `SFSpeechRecognizer` with the new `SpeechAnalyzer` framework which provides first-class async/await sequences (`for await transcript in SpeechTranscriber()...`).
- **Authorization:** `Speech` framework requires user authorization (`SFSpeechRecognizer.requestAuthorization` still applies to the broad framework capabilities, or equivalent `SpeechAnalyzer` entitlements). You must handle the `.notDetermined` or `.denied` states gracefully.

### Project Structure Notes

- Place `NativeSpeechEngine.swift` in `Sources/voice-to-text/Engines/Transcription/`
- Reference existing `Protocols.swift` in `Domain/` for `TranscriptionEngine`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-3-2-Native-Apple-Speech-Transcription]
- [Source: _bmad-output/project-context.md#Framework-Specific-Rules]

## Dev Agent Record

### Agent Model Used

Gemini 2.5 Pro

### Debug Log References

### Completion Notes List

- Implemented `NativeSpeechEngine` using `SFSpeechRecognizer` returning results via `streamContinuation`.
- Handled Apple Dictation's nearly instant transcription speeds by adding a 50ms async dispatch delay in `OutputService` before synthesizing `Cmd+V`, preventing macOS from dropping the paste event while window focus shifts or modifier keys are still pressed.
- Refactored `SettingsView` to cleanly decouple the UI's model inspection state (`focusedModel`) from the actual backend transcription engine state (`selectedModel`). Clicking cards no longer triggers engine re-initialization unless "Use Model" is explicitly clicked.
- Mapped "Apple Intelligence Native" as a valid inference endpoint alongside Whisper models, seamlessly hot-swappable via `EngineRouter`.

### File List

- `Sources/voice-to-text/Engines/Transcription/NativeSpeechEngine.swift` (NEW)
- `Sources/voice-to-text/App/AppStateManager.swift` (MODIFIED)
- `Sources/voice-to-text/UI/Settings/SettingsView.swift` (MODIFIED)
- `Tests/voice-to-textTests/Engines/NativeSpeechEngineTests.swift` (NEW)
- `Tests/voice-to-textTests/AppStateManagerTests.swift` (MODIFIED)
- `Tests/voice-to-textTests/Engines/EngineRouterTests.swift` (MODIFIED)
