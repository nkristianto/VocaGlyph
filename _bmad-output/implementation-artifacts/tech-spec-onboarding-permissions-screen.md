```
---
title: 'Onboarding Permissions Screen'
slug: 'onboarding-permissions-screen'
created: '2026-02-22T03:01:34+07:00'
status: 'review'
stepsCompleted: [1, 2, 3]
tech_stack: []
files_to_modify: []
code_patterns: []
test_patterns: []
---

# Tech-Spec: Onboarding Permissions Screen

**Created:** 2026-02-22T03:01:34+07:00

## Overview

### Problem Statement

The app needs a first-launch experience to guide users in granting required permissions (Microphone, Accessibility, Full Disk Access) before they can use the app. Currently, the main app UI loads regardless of whether permissions are granted, leading to a broken experience. Furthermore, granting permissions (like Accessibility) often requires a manual app restart to take effect.

### Solution

Create a new SwiftUI Onboarding View matching the provided design. It will act as a blocking screen shown at startup if any required permissions are missing. We will create a `PermissionsManager` to handle checking and requesting these permissions dynamically. We will also implement a `reinitializeServices()` method in the `AppDelegate` or `AppStateManager` so that once all permissions are granted, the app can be used immediately without requiring a manual restart.

### Scope

**In Scope:**
- Onboarding UI matching the reference design (Microphone, Accessibility, Full Disk Access).
- Centralized `PermissionsManager` class.
- Blocking the main UI from loading until permissions are granted.
- Dynamic service re-initialization upon permission completion (no restart required).

**Out of Scope:**
- Changes to the core transcription logic.
- Changes to the main app UI beyond the initial routing logic.

## Context for Development

### Codebase Patterns

*   **SwiftUI State**: Strictly uses `@Observable` (Swift 17+) for all ViewModels, as defined in `project-context.md`.
*   **App Lifecycle**: `AppDelegate` is responsible for initializing Core Services (`AppStateManager`, `WhisperService`, `HotkeyService`) and starting the `engineRouter`.
*   **Settings Window UI**: The Settings UI uses a custom transparent title bar. The new Onboarding screen could similarly use a new `NSWindow` or be presented as an interactive sheet before `SettingsWindow` allows normal interaction.
*   **Actors and Concurrency**: Heavy tasks like permission checks and engine reloads must respect the `@MainActor` boundary vs. background tasks.

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `App/AppDelegate.swift` | App bootflow and initializing core services. Will need a `reinitializeServices()` method. |
| `App/AppStateManager.swift` | Coordinates app state and starts the ML model. Will need to delay execution until permissions are granted. |
| `App/main.swift` | Program entry point. |

### Technical Decisions

- **PermissionsManager**: We will introduce a new `PermissionsManager` class. It will manage checks for `AVAudioSession` (Microphone), `AXIsProcessTrusted` (Accessibility), and standard file system checks (Full Disk Access).
- **Blocking Flow**: We will modify `AppDelegate.applicationDidFinishLaunching` to check `PermissionsManager.isAllGranted()` before starting the `AppStateManager` engine or the `HotkeyService`.
- **Re-initialization**: When permissions are granted via the UI, the UI will trigger `AppDelegate.shared.reinitializeServices()` to start everything dynamically without a restart.

## Implementation Plan

### Tasks

- [ ] Task 1: Create `PermissionsManager`
  - File: `App/PermissionsManager.swift` (New File)
  - Action: Create an `@Observable` class. Implement methods to check and request `AVAudioSession` (Microphone), `AXIsProcessTrusted` (Accessibility), and a basic file write check for Full Disk Access. Expose a published property `isAllGranted`.
- [ ] Task 2: Create Onboarding UI
  - File: `UI/Onboarding/OnboardingView.swift` (New File)
  - Action: Build a SwiftUI View matching the reference design. It should observe `PermissionsManager` and show the status of the three permissions. Include a 'Continue' button that is disabled until `isAllGranted` is true.
- [ ] Task 3: Implement Blocking Boot Flow
  - File: `App/AppDelegate.swift`
  - Action: In `applicationDidFinishLaunching`, check `PermissionsManager.shared.isAllGranted`. If false, immediately present `OnboardingView` in a floating, modal-style `NSWindow` (or as the sole content of a temporary window), and *return early* without initializing `AppStateManager`, `WhisperService`, or `HotkeyService`.
- [ ] Task 4: Implement Dynamic Re-initialization
  - File: `App/AppDelegate.swift`
  - Action: Add a `func reinitializeServices()` method that performs the setup originally found in `applicationDidFinishLaunching` (initializing `AppStateManager`, `EngineRouter`, `HotkeyService`, etc.).
- [ ] Task 5: Connect UI to Boot Flow
  - File: `UI/Onboarding/OnboardingView.swift`
  - Action: When the user clicks "Continue" (after all permissions are granted), close the onboarding window and call `AppDelegate.shared.reinitializeServices()` to start the app normally without a restart.

### Acceptance Criteria

- [ ] AC 1: Given a fresh install (no permissions), when the app launches, then the Onboarding window is shown and the main engines/hotkeys do NOT start.
- [ ] AC 2: Given the Onboarding window is visible, when a user clicks a permission row, then the native macOS permission prompt appears.
- [ ] AC 3: Given the Onboarding window, when all permissions are granted, then the "Continue" button becomes active.
- [ ] AC 4: Given an active "Continue" button, when clicked, then the Onboarding window closes and the main application (status bar icon, hotkeys, transcription engine) starts up seamlessly without requiring an app restart.
- [ ] AC 5: Given all permissions were previously granted, when the app launches, then the Onboarding window is bypassed and the app starts normally.

## Additional Context

### Dependencies

- Requires AVFoundation (Microphone).
- Requires ApplicationServices (Accessibility API for `AXIsProcessTrusted`).
- Requires SwiftUI for the Onboarding View.

### Testing Strategy

- **Manual Testing**: A fresh macOS environment (or resetting permissions via `tccutil reset All "com.your.bundle.id"`) is the most reliable way to test the full first-launch blocking experience.
- **Unit Tests**: Add tests for `PermissionsManager` using mock permission providers to verify the `isAllGranted` logic independently of the OS dialogs.



### Notes

