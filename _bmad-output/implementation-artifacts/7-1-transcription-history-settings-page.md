# Story 7.1: Transcription History Settings Page

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an active user,
I want to view a chronological history of my recent dictations within Settings,
So that I can recover text if I lost my clipboard or want to reference past thoughts.

## Acceptance Criteria

1. **Given** a successful dictation, **when** the text is finalized by the engine, **then** a new `TranscriptionItem` is automatically saved to the local SwiftData store.
2. **Given** the History Settings page is open, **when** the user views the list, **then** the transcriptions are displayed grouped chronologically by date with their timestamps.
3. **Given** a populated history list, **when** the user types in the search bar, **then** the list instantly filters to show only matching transcriptions.
4. **Given** a specific history item, **when** the user clicks the Copy button, **then** the text is copied to the macOS clipboard.
5. **Given** a specific history item, **when** the user selects Delete from the menu, **then** the item is deleted from the database and the UI updates immediately.
6. **Given** a database containing items older than 30 days, **when** a new dictation finishes (or the app launches), **then** those old items are automatically deleted from SwiftData.

## Tasks / Subtasks

- [x] Task 1: Define SwiftData Model (AC: 1, 2)
  - [x] Create `Domain/TranscriptionItem.swift`
  - [x] Define `@Model class TranscriptionItem` with `id` (UUID), `text` (String), and `timestamp` (Date)
- [x] Task 2: Implement History Persistance (AC: 1, 6)
  - [x] Modify `App/AppDelegate.swift` to initialize the SwiftData `ModelContainer`
  - [x] Inject save logic into `appStateManagerDidTranscribe(text:)` to insert the new record
  - [x] Implement a lightweight cleanup routine to purge items older than 30 days during save/boot
- [x] Task 3: Create UI View (AC: 2, 3, 4, 5)
  - [x] Create `UI/Settings/HistorySettingsView.swift`
  - [x] Use `@Query` to fetch `TranscriptionItem`s sorted descending by date
  - [x] Group list items visually by Date (Today, Yesterday, etc.)
  - [x] Add `.searchable` support to filter lists
  - [x] Add 'Copy to Clipboard' and 'Delete' context operations per row
- [x] Task 4: Integrate Tab into Settings 
  - [x] Modify `UI/Settings/SettingsView.swift`
  - [x] Add `.history` to `SettingsTab` enum
  - [x] Add a `SidebarItemView` and route it to `HistorySettingsView`

## Dev Notes

### Dev Agent Guardrails

#### Technical Requirements
- **SwiftData Usage**: Apple's native `SwiftData` framework MUST be used. Ensure `ModelContext` is safely accessed on the correct thread (e.g. `@MainActor`) because `AppDelegate.appStateManagerDidTranscribe` can sometimes arrive from background threads if not explicitly dispatched.
- **Copying to Clipboard**: Use `NSPasteboard.general` to copy text to the macOS clipboard.

#### Architecture Compliance
- **Strict Concurrency**: Enforce `async/await`, `Task`, and `@MainActor`. Avoid GCD/DispatchQueue.
- **State Management**: Use `@Observable` exclusively for any ViewModels needed. Do not use legacy `@Published` or `ObservableObject`.
- **UI Boundary**: Do not put business logic or data cleanup routines directly inside the `View` body. Keep persistence/save operations isolated in the AppDelegate lifecycle or a dedicated MainActor service/manager.

#### File Structure Requirements
- Ensure new models go into `Swift-version/Sources/voice-to-text/Domain/`.
- Ensure new views go into `Swift-version/Sources/voice-to-text/UI/Settings/`.

#### Testing Requirements
- Use `XCTest` in the `voice-to-textTests` target.
- Test SwiftData logic by spinning up an in-memory-only `ModelContainer` (`isStoredInMemoryOnly: true`).
- Verify the 30-day cleanup logic correctly targets older entries without deleting recent ones.

### Git Intelligence & Previous Work
- **Recent Commits:** The team recently added Gemma integration, keychain storage, and an onboarding screen. Look at `SettingsView.swift` to see how the onboarding screen and API settings Tabs were added, and replicate that Tab pattern for the History tab.

### Project Structure Notes
- Alignment with unified project structure: `App/`, `Domain/`, `Engines/`, `Services/`, `UI/`, `Utilities/`.

### References
- [Source: _bmad-output/planning-artifacts/architecture.md]
- [Source: _bmad-output/project-context.md]
- [Source: _bmad-output/implementation-artifacts/tech-spec-transcription-history-settings-page.md]

## Dev Agent Record

### Agent Model Used
Antigravity 

### Completion Notes List
- Ultimate context engine analysis completed - comprehensive developer guide created based on architecture constraints, project context guidelines, and recent code modifications.
- Defined `TranscriptionItem` SwiftData model to store transcription items locally.
- Injected `ModelContainer` initialization into `AppDelegate` and wired `appStateManagerDidTranscribe` to auto-save transcripts and auto-purge records older than 30 days.
- Created `HistorySettingsView.swift` implementing the Stitch-based UI with daily grouping, text search, copy-to-clipboard, and delete actions.
- Integrated the "History" tab intelligently into `SettingsView.swift` sidebar logic.
- Implemented and passed `HistoryCleanupTests` validating 30-day SwiftData chronological prune logic.

### File List
- `_bmad-output/implementation-artifacts/7-1-transcription-history-settings-page.md`
- `Swift-version/Sources/voice-to-text/Domain/TranscriptionItem.swift`
- `Swift-version/Sources/voice-to-text/App/AppDelegate.swift`
- `Swift-version/Sources/voice-to-text/UI/Settings/HistorySettingsView.swift`
- `Swift-version/Sources/voice-to-text/UI/Settings/SettingsView.swift`
- `Swift-version/Tests/voice-to-textTests/HistoryCleanupTests.swift`
