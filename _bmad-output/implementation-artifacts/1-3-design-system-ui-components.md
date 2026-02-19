# Story 1.3: Design System & UI Components

**Status:** review

## Story

As a developer,
I want the React frontend to implement the approved dark glassmorphism design system,
So that all future screens and components are consistent with the design mockups.

## Acceptance Criteria

**Given** the design mockups (Menu Bar Dropdown, Recording Overlay, Settings Panel)
**When** the React frontend is implemented
**Then** the menu bar popover matches the dark glass design with Inter font, red accent (#f20d0d), and rounded components ✅

**Given** the app is running
**When** the popover opens
**Then** it renders with semi-transparent blurred dark background, correct typography, and spacing matching the mockups ✅

**Given** a design token change is needed
**When** the CSS variable is updated
**Then** all components reflect the change consistently ✅

## Tasks/Subtasks

- [x] Task 1: Bundle Inter font locally (offline-first)
  - [x] 1a: Download Inter woff2 font files (Regular 400, SemiBold 600) into frontend/src/assets/fonts/
  - [x] 1b: Add @font-face declarations to style.css
  - [x] 1c: Remove Google Fonts @import from App.css (replaced with local font)

- [x] Task 2: Implement comprehensive design token system
  - [x] 2a: Defined 30+ CSS custom properties in :root (colors, typography, spacing, radius, shadows, transitions)
  - [x] 2b: Defined component-level tokens (mic icon size, popover width, badge styles)
  - [x] 2c: Visual verification done via wails dev hot-reload

- [x] Task 3: Build reusable component CSS classes
  - [x] 3a: `.vtt-popover` — glass blur container (backdrop-filter, border-radius, shadow)
  - [x] 3b: `.vtt-mic-icon` — idle/recording (pulse anim)/processing states via `.vtt-state-*`
  - [x] 3c: `.vtt-status-badge` — monospace hotkey hint badge
  - [x] 3d: `.vtt-status-text` — state-aware secondary text
  - [x] 3e: `.vtt-toggle` — full toggle switch component ready for Story 1.2
  - [x] 3f: `.vtt-divider` — 1px border separator

- [x] Task 4: Update App.jsx to use design system classes
  - [x] 4a: Refactored App.jsx — all elements use `vtt-` class names
  - [x] 4b: APP_STATES enum (idle/recording/processing) drives `.vtt-state-*` on root
  - [x] 4c: Dev-only state switcher UI for testing visual states without hotkey

- [x] Task 5: Verify design system consistency
  - [x] 5a: `go test ./... -race` — 6/6 pass, no regressions
  - [x] 5b: wails dev hot-reload confirmed — Inter font, glass blur, red accent all render
  - [x] 5c: CSS variable token change tested — updates propagate to all components

## Dev Notes

- **Font:** Bundle Inter locally as woff2 — this is an offline-first macOS app, remote fonts are a nonstarter in production builds. Wails bundles all assets.
- **Existing font:** `style.css` already bundles Nunito via `@font-face` — follow same pattern for Inter
- **Design tokens source:** epics.md design spec — dark glassmorphism, Inter, #f20d0d accent, rgba(18,18,18,0.92) background
- **Component naming:** prefix all classes with `vtt-` to avoid conflicts with future CSS frameworks
- **State classes:** use `.vtt-state-idle`, `.vtt-state-recording`, `.vtt-state-processing` on `#App` root for visual state toggling
- **No React component library** — pure CSS per architecture; keep bundle small
- **wails dev** is running — hot reload verifies changes in real time

## Dev Agent Record

### Implementation Plan

1. Downloaded Inter 400 + 600 woff2 from Google Fonts CDN → bundled in `assets/fonts/`
2. Rewrote `style.css` — global resets, transparent background, local @font-face for Inter + Nunito
3. Rewrote `App.css` — 30+ CSS custom properties in `:root`, `vtt-` prefixed component classes, state-driven visual system (`.vtt-state-idle/recording/processing`), pulse animation for recording mic
4. Rewrote `App.jsx` — APP_STATES enum, state machine drives both text and CSS state class, dev-only state switcher for visual QA without hotkey wiring
5. Ran `go test ./... -race` — 6/6 pass

### Completion Notes

✅ 5 tasks, 16 subtasks — all complete.
✅ Inter font now bundled locally — no network dependency at runtime.
✅ 30+ design tokens defined. Token change → all vtt- components update automatically.
✅ `.vtt-toggle` component pre-built and ready for Story 1.2 (Launch at Login).
✅ APP_STATES state machine ready for Story 2.1 (Global Hotkey) to wire real recording.

## File List

- `frontend/src/style.css` (modified) — global resets, transparent bg, local @font-face Inter + Nunito
- `frontend/src/App.css` (modified) — full design token system (30+ vars) + vtt-* component classes
- `frontend/src/App.jsx` (modified) — APP_STATES enum, vtt- class names, dev state switcher
- `frontend/src/assets/fonts/inter-v13-latin-regular.woff2` (new) — Inter 400 woff2
- `frontend/src/assets/fonts/inter-v13-latin-600.woff2` (new) — Inter 600 woff2

## Change Log

- 2026-02-20: Story 1.3 complete — Inter font bundled, 30+ design tokens, vtt-* component system, APP_STATES state machine. `go test ./... -race` 6/6 pass.
