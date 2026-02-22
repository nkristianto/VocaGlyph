---
project_name: 'voice-to-text'
user_name: 'Novian'
date: '2026-02-21'
sections_completed:
  ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules', 'anti_patterns']
status: 'complete'
rule_count: 14
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- Swift 6.0 framework
- macOS 14+ target (Apple Silicon) using AppKit & SwiftUI
- whisperKit (>= 0.10.0)
- mlx-swift (>= 0.22.0)

## Critical Implementation Rules

### Language-Specific Rules

- **Strict Concurrency:** Use `async`/`await`, `Task`, `actor`, and `@MainActor`. Avoid Grand Central Dispatch (`DispatchQueue`), Combine, or raw completion handlers unless interfacing with legacy Objective-C or CoreAudio libraries.
- **Error Handling:** Return strongly-typed `Error` enums specific to the domain (e.g., `ModelLoadError.fileNotFound`). Functions must declare explicitly that they `throw`, rather than returning `nil` or optional strings on failure.
- **Protocol Inheritance (Open Sandbox):** All engine implementations must conform to protocols that inherit from `Sendable` to be safely boxed and passed across strict `actor` boundaries.

### Framework-Specific Rules

- **State Management:** Strictly use the `@Observable` macro (Swift 17+) for all ViewModels and UI state representations. Do not use older reactive patterns (`ObservableObject`, `@Published`) unless natively required for AppKit bridging backwards compatibility.
- **Naming Conventions:** ViewModels must be suffixed with `ViewModel` (e.g., `SettingsViewModel`, `HUDViewModel`).
- **UI-Thread Boundary:** Core ML and MLX compute jobs must run exclusively in the `Engines/` directory, isolated from the `@MainActor`. No transcription logic should be referenced directly inside a SwiftUI `View` or `ViewModel`.
- **The Orchestrator Boundary:** UI components in the `UI/` folder never talk directly to the `Engines/`. They emit intents to the Orchestrator. 

### Testing Rules

- **Framework:** Use `XCTest`.
- **Test Organization:** Maintain a separate test target (`voice-to-textTests`). Group tests logically by the service or component they map to.
- **Mocking:** Use protocol-based mocks (e.g., `MockAppStateManagerDelegate`) to isolate components and verify state transitions and delegation.
- **Coverage Focus:** Ensure tests cover object lifespans, explicit state machine transitions (e.g., in `AppStateManager`), and graceful handling of edge cases (e.g., empty audio buffers, missing hardware hooks).

### Code Quality & Style Rules

- **Project Structure:** Adhere strictly to the defined folder structure: `App/`, `Domain/`, `Engines/`, `Services/`, `UI/`, and `Utilities/`.
- **Component Isolation:** Ensure `UI/` components never directly instantiate or communicate with `Engines/`. All communication must flow through the central Orchestrator (e.g., `AppStateManager`).

### Development Workflow Rules

- **Build & Packaging:** Use the provided `Makefile` for building the app (`make build-app`) and packaging it into a macOS DMG (`make package-dmg`). Do not bypass the defined build process.

### Critical Don't-Miss Rules

- **Main Thread Blocking:** NEVER perform core ML inference (CoreML or MLX) or heavy audio processing on the main UI thread. Always use isolated `actor` instances or `globalactor` for these tasks.
- **Accessibility/Pasteboard Limitations:** The app relies on synthesizing `CGEvent` keystrokes (Cmd+V) after writing to the `NSPasteboard`. Do not attempt to use `AXUIElement` for focus-detection as it is unreliable across third-party apps.
- **Error Swallowing:** Never swallow errors or return `nil` silently from engine components. Always throw typed errors to allow the Orchestrator's state machine to handle failures gracefully (e.g., falling back to raw output).

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code
- Follow ALL rules exactly as documented
- When in doubt, prefer the more restrictive option
- Update this file if new patterns emerge

**For Humans:**

- Keep this file lean and focused on agent needs
- Update when technology stack changes
- Review quarterly for outdated rules
- Remove rules that become obvious over time

Last Updated: 2026-02-21
