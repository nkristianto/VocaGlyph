# Fix 4 VocaGlyph Bugs

## Bug Summary

| # | Bug | Root Cause |
|---|-----|------------|
| 1 | Onboarding Continue also closes the app | `windowWillClose` delegate calls `NSApp.terminate()` without distinguishing user-close vs programmatic close |
| 2 | App icon missing in Cmd+Tab when Settings is open | `NSApp.setActivationPolicy(.accessory)` is set at launch and never changed back to `.regular` when the Settings window is shown |
| 3 | App crashes when switching from Apple Intelligence to Local LLM | `switchPostProcessingEngine()` accesses the `LocalLLMEngine` **actor** from a non-isolated context, hitting an actor isolation violation at runtime |
| 4 | "Free Model Memory" button not working | `unloadLocalLLMEngine()` correctly calls `localLLMEngine.unloadModel()`, but `localLLMIsWarmedUp` is never reset to `false` after the unload, so both the UI and internal state remain stale |

---

## Bug #1 — Onboarding window: Continue closes the app

### Root Cause
In `AppDelegate.swift`, `windowWillClose(_ notification:)` fires for **any** close event on `onboardingWindow`, including when `onboardingWindow?.close()` is called programmatically by the `onContinue` closure. Because `NSApp.terminate(nil)` is called unconditionally in that delegate method, the Continue button path also terminates the app.

### Fix
Add a boolean flag `isOnboardingCompleted` to `AppDelegate`. Set it to `true` **before** calling `onboardingWindow?.close()` inside `onContinue`. Check this flag inside `windowWillClose` and only terminate if the flag is `false`.

### [MODIFY] [AppDelegate.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppDelegate.swift)

```diff
+    /// Set to `true` when the user completes onboarding via the Continue button.
+    /// Prevents windowWillClose from terminating the app on programmatic close.
+    private var isOnboardingCompleted = false

     func showOnboardingWindow() {
         let onboardingView = OnboardingView(permissionsService: permissionsService) { [weak self] in
             DispatchQueue.main.async {
+                self?.isOnboardingCompleted = true
                 self?.onboardingWindow?.close()
                 self?.onboardingWindow = nil
                 self?.initializeCoreServices()
                 self?.toggleSettingsWindow(nil)
             }
         }
     ...
     }

     public func windowWillClose(_ notification: Notification) {
         guard let window = notification.object as? NSWindow,
               window === onboardingWindow else { return }
+        guard !isOnboardingCompleted else { return }
         NSApp.terminate(nil)
     }
```

---

## Bug #2 — App icon missing in Cmd+Tab when Settings window is open

### Root Cause
`applicationDidFinishLaunching` sets `NSApp.setActivationPolicy(.accessory)` so the app runs as a menu-bar-only app (no Dock icon, no Cmd+Tab entry). When core services are initialized and the Settings window is shown (either after onboarding or when toggled from the menu bar), the activation policy is never switched to `.regular`, so the app never appears in the Cmd+Tab switcher.

### Fix
Change the activation policy to `.regular` when the Settings window is shown (`toggleSettingsWindow` when it becomes visible, and after onboarding `initializeCoreServices` shows it), and back to `.accessory` when it's hidden. This is the standard pattern for macOS menu-bar apps that can also have a main window.

### [MODIFY] [AppDelegate.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppDelegate.swift)

```diff
     @objc func toggleSettingsWindow(_ sender: AnyObject?) {
         if settingsWindow.isVisible {
             settingsWindow.orderOut(nil)
+            NSApp.setActivationPolicy(.accessory)
         } else {
             settingsWindow.makeKeyAndOrderFront(nil)
             NSApp.activate(ignoringOtherApps: true)
+            NSApp.setActivationPolicy(.regular)
         }
     }
```

Also handle the window-closed-by-red-button case by implementing `windowWillClose` for the Settings window:

```diff
     public func windowWillClose(_ notification: Notification) {
         guard let window = notification.object as? NSWindow else { return }
+        if window === settingsWindow {
+            NSApp.setActivationPolicy(.accessory)
+            return
+        }
         guard window === onboardingWindow else { return }
         guard !isOnboardingCompleted else { return }
         NSApp.terminate(nil)
     }
```

> [!NOTE]  
> `settingsWindow.delegate = self` must also be set in `initializeCoreServices()` for the close event to be received (currently only `onboardingWindow` sets a delegate).

---

## Bug #3 — Crash when switching to Local LLM in post-processing

### Root Cause
`LocalLLMEngine` is a Swift `actor`. The computed property `localLLMEngine` on `AppStateManager` (a regular class) creates and returns a `LocalLLMEngine` actor instance. The crash happens because `switchPostProcessingEngine()` (called from SwiftUI on the `@MainActor`) tries to call `localLLMEngine.isModelDownloaded()` — an `actor`-isolated method — with `Task { self.localLLMIsDownloaded = await localLLMEngine.isModelDownloaded() }`. However, this code path isn't the actual crash.

The real crash is that `LocalLLMEngine` is an `actor` but `AppStateManager` is a plain `class` marked `@unchecked Sendable`. The private property `_localLLMEngine: LocalLLMEngine?` is accessed/written from the `@MainActor` context in `switchPostProcessingEngine()` without any actor isolation, which is an undefined-behaviour data race that can crash.

### Fix
Make the `_localLLMEngine` and `_localLLMEngineModelId` properties and the `localLLMEngine` computed property thread-safe by isolating them to `@MainActor` (since `AppStateManager` UI-published properties are already `@MainActor`-expected), or simply declare them within a lock/serial queue. The simplest correct fix is to annotate the class with `@MainActor` or mark the problematic accessors. Since `AppStateManager` already dives into `@MainActor` for its `@Published` vars, the simplest fix is to ensure the `localLLMEngine` computed property is only ever accessed on the main thread, which it is (it is called from `switchPostProcessingEngine` which is always called from `@MainActor` SwiftUI context).

The actual crash point is more likely a nil dereference inside `AppleIntelligenceEngine` that is initialized from `switchPostProcessingEngine` on macOS versions that don't support FoundationModels without the `#if canImport(FoundationModels)` guard. Let me verify:

Looking at `switchPostProcessingEngine()` at line 167–177:
```swift
} else if selectedPostModel == "apple-native" {
    if #available(macOS 26.0, *) {
        self.postProcessingEngine = AppleIntelligenceEngine()
    } else {
        self.postProcessingEngine = AppleIntelligenceLegacyStub()
    }
```

The user is switching **away** from Apple Intelligence **to** local LLM. The crash is **when selecting "Local AI (Qwen)"**. The `switchPostProcessingEngine()` function then reaches the `local-llm` branch at line 178. Let me look at `localLLMEngine` computed property again:

```swift
private var localLLMEngine: LocalLLMEngine {
    let modelId = UserDefaults.standard.string(forKey: "selectedLocalLLMModel") ?? "..."
    if let existing = _localLLMEngine, _localLLMEngineModelId == modelId {
        return existing
    }
    let engine = LocalLLMEngine(modelId: modelId)   // ← Creates actor
    _localLLMEngine = engine
    _localLLMEngineModelId = modelId
    return engine
}
```

And in `switchPostProcessingEngine` line 181:
```swift
self.postProcessingEngine = localLLMEngine   // ← Assigns LocalLLMEngine (actor) to postProcessingEngine (protocol type)
Task { self.localLLMIsDownloaded = await localLLMEngine.isModelDownloaded() }
```

The issue: `localLLMEngine` is an `actor`, but it's assigned to `postProcessingEngine: (any PostProcessingEngine)?`. Since `LocalLLMEngine` is an `actor` conforming to `PostProcessingEngine`, the protocol itself may not be `Sendable`.

Checking `Protocols.swift` for the `PostProcessingEngine` protocol definition.

### [MODIFY] [AppStateManager.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppStateManager.swift)

The fix: catch errors when initializing `LocalLLMEngine` and add `@MainActor` isolation to `switchPostProcessingEngine` to properly handle actor context crossing.

```diff
-    public func switchPostProcessingEngine() {
+    @MainActor public func switchPostProcessingEngine() {
```

Also reset `localLLMIsWarmedUp` when switching away from local LLM (to avoid stale state in the UI next time user switches to local LLM).

---

## Bug #4 — "Free Model Memory" button not working

### Root Cause
`unloadLocalLLMEngine()` calls `localLLMEngine.unloadModel()` which evicts the `MLXLMInferenceProvider`'s `cachedContainer`. However, `AppStateManager.localLLMIsWarmedUp` is **never reset to `false`** after the unload, so the UI still shows "Model ready in memory" and the internal state is stale.

### Fix
After `unloadModel()` completes, reset `localLLMIsWarmedUp = false` on `@MainActor`.

### [MODIFY] [AppStateManager.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppStateManager.swift)

```diff
     public func unloadLocalLLMEngine() async {
         await localLLMEngine.unloadModel()
+        await MainActor.run {
+            self.localLLMIsWarmedUp = false
+        }
     }
```

---

## Bug #5 — Loading overlay not shown on first app launch

### Root Cause
In `initializeCoreServices()`, execution order is:
1. `stateManager.startEngine()` — triggers `WhisperService.autoInitialize()` → `initializeWhisper()` → calls `delegate?.whisperServiceDidUpdateState("Loading into memory...")` → AppDelegate sets `currentState = .initializing` → `OverlayPanelManager.shared.updateVisibility(for: .initializing)` fires
2. `OverlayPanelManager.shared.setupPanel(...)` — **panel created here, too late**

So when `updateVisibility` is called in step 1, `panel` is still `nil` and the guard fails silently.

### Fix
Move `OverlayPanelManager.shared.setupPanel(with: stateManager)` to **before** `stateManager.startEngine()` so the panel exists before any state change can fire.

### [MODIFY] [AppDelegate.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppDelegate.swift)

```diff
     @MainActor func initializeCoreServices() {
         ...
+        // Setup Overlay Panel FIRST — must exist before startEngine() fires state changes
+        OverlayPanelManager.shared.setupPanel(with: stateManager)
+
         stateManager.delegate = self
         ...
         stateManager.startEngine()
         ...
-        // Setup Overlay Panel for Recording
-        OverlayPanelManager.shared.setupPanel(with: stateManager)
     }
```

---

## Bug #6 — Progress bar not working in loading overlay

### Root Cause
The progress bar in `RecordingOverlayView` uses `GeometryReader` to get the available width:

```swift
GeometryReader { geo in
    ZStack(alignment: .leading) {
        Capsule().fill(Color.black.opacity(0.08)).frame(height: 3)
        Capsule().fill(Theme.accent)
            .frame(width: geo.size.width * stateManager.whisperLoadingProgress, height: 3)
    }
}
.frame(height: 3)
```

`GeometryReader` inside an `HStack` inside a `VStack` with no explicit width gets an unreliable/zero size during layout. This makes `geo.size.width` return `0`, so the colored capsule is always invisible.

### Fix
Replace `GeometryReader` with a fixed explicit width using `containerRelativeFrame` or a simple overlay-with-`GeometryReader`-on-the-background approach. The simplest fix is to give the progress bar a fixed width that matches the overlay (e.g. `186` — which is `230 - 2×32` horizontal padding) and use `frame(maxWidth:)` with alignment:

```swift
// Before:
GeometryReader { geo in
    ZStack(alignment: .leading) {
        Capsule().fill(Color.black.opacity(0.08)).frame(height: 3)
        Capsule().fill(Theme.accent)
            .frame(width: geo.size.width * stateManager.whisperLoadingProgress, height: 3)
            .animation(.linear(duration: 0.5), value: stateManager.whisperLoadingProgress)
    }
}
.frame(height: 3)

// After:
ZStack(alignment: .leading) {
    Capsule()
        .fill(Color.black.opacity(0.08))
        .frame(height: 3)
    GeometryReader { geo in
        Capsule()
            .fill(Theme.accent)
            .frame(width: geo.size.width * stateManager.whisperLoadingProgress, height: 3)
    }
    .frame(height: 3)
    .animation(.linear(duration: 0.5), value: stateManager.whisperLoadingProgress)
}
.frame(height: 3)
```

The key change is moving the `GeometryReader` to wrap only the **foreground capsule** while the background capsule provides its natural full width to the `ZStack`, giving `GeometryReader` a reliable size to measure.

### [MODIFY] [RecordingOverlayView.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/UI/HUD/RecordingOverlayView.swift)
- Replace the `GeometryReader`-wrapping-`ZStack` pattern with the fixed approach above

---

## Proposed Changes

### AppDelegate.swift

#### [MODIFY] [AppDelegate.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppDelegate.swift)
- Add `isOnboardingCompleted` flag (Bug #1)
- Set `isOnboardingCompleted = true` before programmatic close in `onContinue` (Bug #1)
- Update `windowWillClose` to short-circuit on `isOnboardingCompleted` or `settingsWindow` (Bugs #1, #2)
- Set `settingsWindow.delegate = self` in `initializeCoreServices()` (Bug #2)
- Toggle `.regular` / `.accessory` activation policy in `toggleSettingsWindow` (Bug #2)
- Move `OverlayPanelManager.shared.setupPanel()` to before `stateManager.startEngine()` (Bug #5)

---

### AppStateManager.swift

#### [MODIFY] [AppStateManager.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/App/AppStateManager.swift)
- Add `@MainActor` to `switchPostProcessingEngine()` to prevent the actor isolation crash (Bug #3)
- Reset `localLLMIsWarmedUp = false` inside `unloadLocalLLMEngine()` after the actor call completes (Bug #4)
- Reset `localLLMIsWarmedUp = false` when switching away from `local-llm` in `switchPostProcessingEngine()` (Bug #4)

### RecordingOverlayView.swift

#### [MODIFY] [RecordingOverlayView.swift](file:///Users/nkristianto/Workspace/Personal/voice-to-text/swift-version/Sources/VocaGlyph/UI/HUD/RecordingOverlayView.swift)
- Fix `GeometryReader` nesting so the background capsule provides the reference width (Bug #6)

---

## Verification Plan

### Automated Tests
Run the existing test suite to ensure nothing is broken:
```bash
cd /Users/nkristianto/Workspace/Personal/voice-to-text/swift-version
swift test 2>&1
```

**Bug #5 — First-launch overlay**
- Verify `setupPanel` is called before `startEngine` by code inspection

### Manual Verification

**Bug #1 — Onboarding Continue**
1. Revoke both Microphone and Accessibility permissions for VocaGlyph in System Settings
2. Launch the app — the onboarding window appears
3. Grant Microphone permission (click Grant → allow in the system dialog)
4. Grant Accessibility permission
5. Once both permissions are granted and Continue is enabled, click **Continue**
6. ✅ Expected: Settings window opens without the app quitting
7. ✅ Expected: Close the onboarding window (if visible again) or test by _not_ completing — clicking the red ✕ close button on the onboarding window should still quit the app

**Bug #2 — Cmd+Tab icon**
1. Open VocaGlyph Settings (click the menu-bar icon → Settings…)
2. Hold **Cmd+Tab** — switch between apps
3. ✅ Expected: VocaGlyph appears in the app switcher with its icon while Settings is open
4. Close the Settings window
5. Hold **Cmd+Tab** again
6. ✅ Expected: VocaGlyph no longer appears in the switcher (back to accessory/menu-bar mode)

**Bug #3 — Crash on LLM switch**
1. Open Settings → Post-Processing
2. Enable "Automated Text Refinement"
3. The AI Processing Model should default to "Apple Intelligence"
4. Change "AI Processing Model" to **Local AI (Qwen)**
5. ✅ Expected: No crash; the Local AI section appears below with download/status UI

**Bug #4 — Free Memory button**
1. Open Settings → Post-Processing
2. With Local AI selected and the model loaded (status shows "Model ready in memory")
3. Click **Free RAM**
4. ✅ Expected: Badge changes to "Model downloaded" (green checkmark) — evicted from RAM

**Bug #5 — First-launch overlay**
1. Fully quit VocaGlyph
2. Launch the app fresh (with a Whisper model already downloaded)
3. ✅ Expected: The loading overlay appears immediately showing the gear animation + progress bar while WhisperKit initializes

**Bug #6 — Progress bar in overlay**
1. Trigger a model load (e.g. switch to a Whisper model in Model Settings)
2. Watch the loading overlay that appears
3. ✅ Expected: The thin progress bar below the gear icon fills up left-to-right as the model loads, reaching ~95% before snapping to complete
