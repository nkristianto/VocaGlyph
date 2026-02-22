# Story 6.1: Onboarding Permissions Screen

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a new user,
I want to be guided to grant Microphone, Accessibility, and Full Disk Access permissions on first launch,
So that the app functions correctly immediately without requiring a manual restart.

## Acceptance Criteria

1. **Given** a fresh install (no permissions), when the app launches, then the Onboarding window is shown and the main engines/hotkeys do NOT start.
2. **Given** the Onboarding window is visible, when a user clicks a permission row, then the native macOS permission prompt appears.
3. **Given** the Onboarding window, when all permissions are granted, then the "Continue" button becomes active.
4. **Given** an active "Continue" button, when clicked, then the Onboarding window closes and the main application (status bar icon, hotkeys, transcription engine) starts up seamlessly without requiring an app restart.
- **IMPORTANT**: During implementation, the UX around Full Disk Access was refined based on User feedback. Instead of presenting a "Grant" button that explicitly opens System Settings and triggers a TCC read intentionally (which is aggressive for an onboarding screen), the FDA section is now purely *informational*. It informs the user that permission will be requested automatically when an offline model is actually initiated. The overarching "Continue" button no longer waits for FDA to be granted to proceed.
- We opted to verify FDA dynamically only when specifically required by a feature (like swapping to a local model) instead of making it a hard block at launch.
5. **Given** all permissions were previously granted, when the app launches, then the Onboarding window is bypassed and the app starts normally.

## Tasks / Subtasks

- [x] Task 1: Implement Permissions Checking Logic in a centralized robust service (`PermissionsService`)
  - [x] Subtask 1.1: Implement Microphone access check via `AVCaptureDevice.authorizationStatus`.
  - [x] Subtask 1.2: Implement Accessibility system events check via `AXIsProcessTrusted()`.
  - [x] Subtask 1.3: Implement Full Disk Access (FDA) check (e.g. by attempting to read a known restricted path such as `~/Library/Safari/Bookmarks.plist` or `~/Library/Messages`) and handle safely.
- [x] Task 2: Create the Onboarding SwiftUI View and Window Controller
  - [x] Subtask 2.1: Build `OnboardingView` detailing the 3 required permissions with clear "Grant" buttons. The visual state should reflect granted vs. denied.
  - [x] Subtask 2.2: Link the "Grant" buttons to native macOS System Settings intent triggers or prompt handlers (e.g. `AVCaptureDevice.requestAccess`).
  - [x] Subtask 2.3: Make the overarching "Continue" button enabled *only* when all three components report a granted state.
- [x] Task 3: Refactor AppDelegate Lifecycle to integrate Onboarding
  - [x] Subtask 3.1: In `applicationDidFinishLaunching`, check the `PermissionsService` before initializing `hotkeyService`, `stateManager`, and `audioRecorder`.
  - [x] Subtask 3.2: If permissions are incomplete, display the Onboarding window and defer Core Services init.
  - [x] Subtask 3.3: When the user presses "Continue" from Onboarding, trigger the deferred initialization natively inside the running session so an app restart isn't necessary.

## Dev Notes

- **Architecture Compliance:**
  - **macOS Permissions Focus:** NFR dictates offline privacy and system-level typing. Therefore, Accessibility (for `CGEvent` `Cmd+V` synthesization) and Microphone (via `AVFoundation`) are *strictly* required. `Full Disk Access` must be explicitly verified.
  - **No Implicit Restarts:** The PRD requires that the application gracefully transitions to the ready state after granting permissions, *without* telling the user to restart the app manually. This implies hooking into `NSWorkspace` notifications or using a polling mechanism (e.g., `Timer` or Combine Publisher) in the `OnboardingView` to detect state changes when users toggle access in System Settings.
  - **App Sandbox Safety:** Ensure that if Full Disk Access is blocked, the check simply returns false rather than crashing.
  
- **Technical Specifications:**
  - **Accessibility Verification:** Use `AXIsProcessTrustedWithOptions` with the prompt option set to `false` for passive checking, and `true` only when the user explicitly clicks the "Grant" button.
  - **Microphone Verification:** Use `AVCaptureDevice.requestAccess(for: .audio)`. Remember that the callback fires on a background thread, so dispatch your UI updates back to `@MainActor`.
  - **Full Disk Access Verification:** macOS does not provide a direct API like iOS. The standard convention is checking readability.

### Project Structure Notes

- Add `PermissionsService.swift` to `Sources/voice-to-text/Services/`.
- Add `OnboardingView.swift` to `Sources/voice-to-text/UI/`.
- Modifications must occur in `Sources/voice-to-text/App/AppDelegate.swift`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-6-1-Onboarding-Permissions-Screen]
- [Source: _bmad-output/planning-artifacts/prd.md#Functional-Requirements]
- [Source: _bmad-output/planning-artifacts/architecture.md#macOS-Permissions]
- [Source: _bmad-output/project-context.md]

## Dev Agent Record

### Agent Model Used

BMad Developer Agent (Gemini)

### Debug Log References

- PermissionsServiceTests.swift
- OnboardingView.swift integration

### Completion Notes List

- Implemented `PermissionsService` with tests
- Created `OnboardingView` connecting with native permission URLs and prompts
- Refactored `AppDelegate` to inject the onboarding view conditionally at launch without crashing or blocking standard access flows. All original `AppDelegate` logic triggers cleanly post-onboarding sequence.
- Cleaned up obsolete macOS 14.0 `@available` checks by permanently moving project minimum to macOS 14.

### File List

- `Sources/voice-to-text/Services/PermissionsService.swift` [NEW]
- `Sources/voice-to-text/UI/OnboardingView.swift` [NEW]
- `Tests/voice-to-textTests/PermissionsServiceTests.swift` [NEW]
- `Sources/voice-to-text/App/AppDelegate.swift` [MODIFIED]
- `Package.swift` [MODIFIED]
- `Sources/voice-to-text/Domain/Protocols.swift` [MODIFIED]

### Change Log

- 2026-02-22: Implemented core onboarding permission flows and application initialization refactoring.
