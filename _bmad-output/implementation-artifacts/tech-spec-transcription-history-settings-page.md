---
title: 'Transcription History Settings Page'
slug: 'transcription-history-settings-page'
created: '2026-02-22T16:15:00+07:00'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack: ['Swift 6.0', 'AppKit', 'SwiftUI', 'SwiftData', 'Concurrency']
files_to_modify: ['App/AppDelegate.swift', 'UI/Settings/SettingsView.swift']
code_patterns: ['MVVM with @Observable', 'Strict Concurrency (@MainActor)', 'AppLifecycle in AppDelegate']
test_patterns: ['XCTest', 'Mocking Services']
---

# Tech-Spec: Transcription History Settings Page

**Created:** 2026-02-22T16:15:00+07:00

## Overview

### Problem Statement

Users need a way to view, search, and manage their past dictations within the application. Currently, transcribed text is pasted into the active application window or copied to the clipboard, but there is no persistent record accessible from within VocaGlyph itself.

### Solution

Implement a "History" tab within the existing `SettingsView` sidebar. This page will display a chronological list of recent transcriptions grouped by date (e.g., Today, Yesterday, October 24, 2024). It will include features such as:
- Searching through past transcriptions.
- A compact, visually appealing list layout.
- Quick action buttons per item: "Copy to Clipboard" and a context menu (Delete).
- A persistent local storage mechanism using `SwiftData` to save the history offline automatically.
- Automatic cleanup of histories older than 30 days.

### Scope

**In Scope:**
- Add "History" tab to `CustomSidebar` in `UI/Settings/SettingsView.swift`.
- Create `HistorySettingsView.swift` implementing the UI depicted in the reference screenshot (Search, Filter, Date Grouping).
- Create a data layer using `SwiftData` to persist `TranscriptionItem` holding `text`, `timestamp`.
- Integration into the transcription finish pipeline to automatically save records.
- Automatic deletion of records older than 30 days.

**Out of Scope:**
- Cloud syncing of history.
- Advanced querying (e.g., by ML model used).
- Other context menu actions aside from Delete.

## Context for Development

### Codebase Patterns

*   **SwiftUI State**: Strictly uses `@Observable` (Swift 17+) for all ViewModels, as defined in `project-context.md`.
*   **App Lifecycle**: `AppDelegate` orchestrates core services. Final transcription text is delivered to `AppDelegate.appStateManagerDidTranscribe(text:)`, which is the ideal injection point for saving history.
*   **Settings Window UI**: The Settings UI (`SettingsView.swift`) uses a custom transparent title bar and a custom `CustomSidebar` with `SettingsTab` enum.
*   **Data Persistence**: We will use Apple's native `SwiftData` framework to store history locally, as it integrates perfectly with SwiftUI and provides automatic migrations and seamless persistence.

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `App/AppDelegate.swift` | Where the final transcription text arrives before output. We will inject a SwiftData save call here. |
| `UI/Settings/SettingsView.swift` | Contains the `CustomSidebar` and `SettingsTab` enum where we will add the new "History" tab. |
| `project-context.md` | Core rules for Swift concurrency and UI thread safety. |

### Technical Decisions

- **SwiftData Usage**: We will define a `TranscriptionItem` `@Model`. A singleton `HistoryManager` (or just utilizing `@Environment(\.modelContext)`) will handle saving. Since saves happen from `AppDelegate` (often jumping off background threads), the `HistoryManager` must safely ensure the `ModelContext` is accessed on the correct thread (e.g., MainActor or a dedicated ModelActor) to avoid data races.
- **History Cleanup**: We will implement a cleanup routine that deletes any `TranscriptionItem` older than 30 days. This check can run statelessly on app boot or periodically within `HistoryManager`.
- **Search & Filter**: The UI will use standard SwiftUI `List` or `ScrollView` with `@Query` bounded filtering, combined with a local `.searchable` modifier to filter text efficiently.

## Implementation Plan

### Tasks

- [ ] Task 1: Define SwiftData Model
  - File: `Domain/TranscriptionItem.swift`
  - Action: Create a SwiftData `@Model` class named `TranscriptionItem`. It must contain an `id` (UUID), `text` (String), and `timestamp` (Date).
- [ ] Task 2: Implement History Persistance
  - File: `App/AppDelegate.swift`
  - Action: Set up the SwiftData `ModelContainer` for the application. Inside `appStateManagerDidTranscribe(text:)`, create and insert a new `TranscriptionItem` using the `ModelContext`. Also, execute a helper routine here to delete any `TranscriptionItem` where the `timestamp` is older than 30 days.
- [ ] Task 3: Create UI View
  - File: `UI/Settings/HistorySettingsView.swift`
  - Action: Build the new `HistorySettingsView` SwiftUI view. Use a `@Query` to fetch `TranscriptionItem`s sorted by date descending. Group them visually by Day (e.g. Today, Yesterday, specific date). Include a `.searchable` modifier to filter the text. Add buttons for "Copy to Clipboard" and a context menu for "Delete".
- [ ] Task 4: Integrate Tab into Settings
  - File: `UI/Settings/SettingsView.swift`
  - Action: Add a `.history` case to the `SettingsTab` enum. Add a new `SidebarItemView` for History in the `CustomSidebar` (using a clock icon like `clock.arrow.circlepath`). Map the `.history` tab selection to display the `HistorySettingsView`.

### Acceptance Criteria

- [ ] AC 1: Given a successful dictation, when the text is finalized by the engine, then a new `TranscriptionItem` is automatically saved to the local SwiftData store.
- [ ] AC 2: Given the History Settings page is open, when the user views the list, then the transcriptions are displayed grouped chronologically by date with their timestamps.
- [ ] AC 3: Given a populated history list, when the user types in the search bar, then the list instantly filters to show only matching transcriptions.
- [ ] AC 4: Given a specific history item, when the user clicks the Copy button, then the text is copied to the macOS clipboard.
- [ ] AC 5: Given a specific history item, when the user selects Delete from the menu, then the item is deleted from the database and the UI updates immediately.
- [ ] AC 6: Given a database containing items older than 30 days, when a new dictation finishes (or the app launches), then those old items are automatically deleted from SwiftData.

## Additional Context

### Dependencies

- Requires Apple's native `SwiftData` framework.

### Testing Strategy

- **Manual Testing**: Perform a dictation and immediately open the History tab to verify it appears at the top under "Today". Use the search bar to filter for specific words in that dictation. Delete the item and verify it disappears.
- **Unit Testing**: Create a SwiftData ModelContainer in memory (`isStoredInMemoryOnly: true`) to write tests verifying that the 30-day cleanup logic correctly identifies and removes stale records without touching new ones.

### Notes
