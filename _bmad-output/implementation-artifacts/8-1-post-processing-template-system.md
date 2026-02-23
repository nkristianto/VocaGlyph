# Story 8.1: Post-Processing Template System

**Epic:** 8 — Structured Post-Processing Templates
**Status:** ready-for-dev
**Created:** 2026-02-23

---

## User Story

As a power user who relies on post-processing AI to refine my dictations,
I want to define and manage named templates — each containing an ordered list of discrete rules — to control how the AI refines my text,
So that I can precisely tune the AI's behaviour per use-case, reduce hallucinations from local models, and easily switch between different refinement styles.

---

## Background & Motivation

The current post-processing pipeline sends a single, free-form text prompt (stored in `UserDefaults`) to whichever AI engine is active. This approach causes:

- **Hallucinations** from local small models (Qwen 0.6B–7B) when the prompt is long or ambiguous
- **No scalability** — changing the post-processing logic requires code changes
- **No user control** — there is no UI to create or manage reusable prompt configurations

This story replaces the monolithic prompt with a **template system**: named, ordered collections of discrete rules stored in SwiftData and rendered at call-time into a tightly structured, numbered system prompt.

---

## Architecture Reference

[architecture-post-processing-template-system.md](file:///Users/nkristianto/.gemini/antigravity/brain/f7cd621e-bc95-4bcc-a42d-8f0e33d17634/architecture-post-processing-template-system.md)

---

## Acceptance Criteria

### AC1 — Domain Models Exist in SwiftData

**Given** the application launches
**When** the SwiftData container is initialized
**Then** `PostProcessingTemplate` and `TemplateRule` models are registered in the container alongside `TranscriptionItem`

### AC2 — Default Templates are Seeded on First Launch

**Given** no `PostProcessingTemplate` records exist in the SwiftData store
**When** the app launches for the first time
**Then** three system templates are automatically created:
- **"General Cleanup"** (active by default): Fix grammar & capitalization; Remove filler words (um, uh, you know, like); End with proper punctuation
- **"Meeting Notes"**: Formalize tone; Capitalize proper nouns and acronyms; Fix grammar; Remove filler words
- **"Raw — No Processing"**: No rules (produces a pass-through null prompt)

**And** all three are marked `isSystem = true`

### AC3 — Active Template Drives the Post-Processing Prompt

**Given** the user has selected a template and post-processing is enabled
**When** a dictation finishes
**Then** `AppStateManager.processAudio()` fetches the active template by UUID from `UserDefaults("activePostProcessingTemplateId")`
**And** calls `TemplatePromptRenderer.render(template:)` to build the final prompt
**And** passes the rendered prompt to `engine.refine(text:prompt:)` — **the engine protocol signature is unchanged**

### AC4 — Prompt Rendered as a Numbered List with Scope Guardrails

**Given** a template with N enabled rules
**When** `TemplatePromptRenderer.render(template:)` is called
**Then** the output is a structured prompt of the form:
```
You are a transcription refinement assistant. Apply ONLY the following rules. Do not add, summarize, translate, or interpret the text. Return ONLY the corrected transcription — nothing else.

Rules:
1. [rule 1 instruction]
2. [rule 2 instruction]
...

Return the corrected text only, with no preamble, label, or explanation.
```
**And** disabled rules (`isEnabled = false`) are excluded from the rendered output
**And** rules are sorted by `order` (ascending)

**Given** a template with no enabled rules
**When** `render(template:)` is called
**Then** it returns an empty string (which suppresses post-processing entirely)

### AC5 — Anti-Hallucination Length Guard

**Given** the total character count of all enabled rules in the active template exceeds 800 characters
**When** the template editor is displayed in Settings
**Then** an inline warning caption is shown: *"Too many rules may reduce accuracy for local AI engines."*

**And** `TemplatePromptRenderer.isOverRecommendedLength(template:)` returns `true`

### AC6 — Template Management UI in the Post-Processing Section

**Given** the user opens Settings → Post-Processing section
**When** the section is viewed
**Then** a **Template** subsection is visible that allows the user to:
- View the list of all templates with the active one highlighted
- Switch the active template (persists to `UserDefaults("activePostProcessingTemplateId")`)
- Create a new custom template (with `isSystem = false`)
- Edit an existing template's name, description, and rules
- Add, edit, reorder, and toggle individual rules
- Delete custom templates (system templates cannot be deleted)
- Reset a system template to its default rules via a "Reset to Default" button

### AC7 — Template Reset Restores Original System Rules

**Given** the user has modified a system template's rules
**When** the user taps "Reset to Default"
**Then** all existing `TemplateRule` rows for that template are deleted
**And** new `TemplateRule` rows are re-created from the template's `defaultRules` snapshot
**And** the template's `updatedAt` timestamp is refreshed

### AC8 — UserDefaults Prompt Key is Removed

**Given** the implementation is complete
**When** `AppStateManager.processAudio()` builds the post-processing prompt
**Then** it no longer reads `UserDefaults["postProcessingPrompt"]`
**And** the Settings UI no longer shows the raw free-text prompt input field (replaced by the template UI)

---

## Technical Tasks

### 1. Domain Models

- [ ] Create `Sources/VocaGlyph/Domain/PostProcessingTemplate.swift`
  - `@Model final class PostProcessingTemplate` with fields: `id`, `name`, `templateDescription`, `isSystem`, `defaultRules: [String]`, `rules: [TemplateRule]`, `createdAt`, `updatedAt`
- [ ] Create `Sources/VocaGlyph/Domain/TemplateRule.swift`
  - `@Model final class TemplateRule` with fields: `id`, `order`, `instruction`, `isEnabled`, `template: PostProcessingTemplate?`

### 2. Template Prompt Renderer

- [ ] Create `Sources/VocaGlyph/Utilities/TemplatePromptRenderer.swift`
  - `enum TemplatePromptRenderer` (stateless)
  - `static func render(template:) -> String`
  - `static func totalRuleCharacters(template:) -> Int`
  - `static let maxRecommendedRuleCharacters = 800`
  - `static func isOverRecommendedLength(template:) -> Bool`

### 3. Template Seeder

- [ ] Create `Sources/VocaGlyph/Services/TemplateSeederService.swift`
  - `func seedDefaultTemplatesIfNeeded(context: ModelContext)`
  - Seeds 3 system templates with their default rules and `defaultRules` snapshot
  - No-op if any `PostProcessingTemplate` already exists in the store

### 4. AppStateManager Integration

- [ ] Register `PostProcessingTemplate` and `TemplateRule` in the existing `ModelContainer` setup in `AppDelegate`
- [ ] Call `TemplateSeederService.seedDefaultTemplatesIfNeeded(context:)` at app startup
- [ ] Replace the `UserDefaults["postProcessingPrompt"]` read in `AppStateManager.processAudio()` with `buildActiveTemplatePrompt(context:)` using `TemplatePromptRenderer`

### 5. Settings UI

- [ ] Add Template subsection to the Post-Processing section in `SettingsView.swift`
  - Active template picker (list of template names with radio/checkmark selection)
  - "Edit" button to open a template editor (sheet or NavigationStack push)
  - "New Template" button to create a custom template
  - Per-template:
    - Name field
    - Rule list with toggle, reorder handles, and delete swipe
    - "Add Rule" button
    - "Reset to Default" button (visible only if `isSystem == true`)
    - Length warning caption (visible if `isOverRecommendedLength` returns true)
  - Custom templates show a "Delete Template" button; system templates do not
- [ ] Remove the legacy free-text `postProcessingPrompt` UserDefaults text field from the UI

### 6. Tests

- [ ] Create `Tests/VocaGlyphTests/Utilities/TemplatePromptRendererTests.swift`
  - Render with 3 enabled rules produces correct numbered output
  - Disabled rules are excluded
  - No enabled rules → empty string
  - Rules rendered in `order` order, regardless of insertion order
  - `isOverRecommendedLength` returns `true` when combined rules > 800 chars

---

## Files Changed

| File | Action |
|------|--------|
| `Domain/PostProcessingTemplate.swift` | **NEW** |
| `Domain/TemplateRule.swift` | **NEW** |
| `Utilities/TemplatePromptRenderer.swift` | **NEW** |
| `Services/TemplateSeederService.swift` | **NEW** |
| `Tests/Utilities/TemplatePromptRendererTests.swift` | **NEW** |
| `App/AppDelegate.swift` | MODIFY — register new @Models; call seeder |
| `App/AppStateManager.swift` | MODIFY — replace UserDefaults prompt read with template renderer |
| `UI/Settings/SettingsView.swift` | MODIFY — add Template UI, remove legacy text field |
| `Domain/Protocols.swift` | **UNCHANGED** |
| `Engines/PostProcessing/*.swift` | **UNCHANGED** |
| `Utilities/PostProcessingOutputSanitizer.swift` | **UNCHANGED** |

---

## Definition of Done

- [ ] All acceptance criteria pass
- [ ] `swift test` passes with no regressions
- [ ] `TemplatePromptRendererTests` all green
- [ ] Three default templates seed correctly on a clean launch
- [ ] Active template drives prompt end-to-end for at least one engine (verified manually)
- [ ] Legacy `postProcessingPrompt` UserDefaults key is dead code (removed)
- [ ] Anti-hallucination length warning visible in UI when rules are long
- [ ] No changes to `PostProcessingEngine` protocol or any engine implementations
