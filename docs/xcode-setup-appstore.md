# VocaGlyph — Xcode Project Setup & Mac App Store Publishing Guide

> **Context**: Your project lives at `swift-version/` and is structured as a Swift Package Manager (SPM) **executable** target. The Mac App Store requires an **app bundle** produced by an Xcode **App target** — not a raw SPM executable. This guide walks you through the exact steps.

---

## Overview of the Approach

The key insight: you will **create a new Xcode macOS App project**, then link your existing SPM `swift-version/` folder as a **local package dependency**. This gives you a proper Xcode App target while reusing all your existing source code unchanged.

```
Existing SPM Package (Package.swift)
    → Open in Xcode as local dependency
    → Add macOS App target
    → Configure Signing & Capabilities
    → Archive & Upload
    → App Store Connect → Mac App Store
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Xcode | 15.x or later (supports macOS 14 SDK) |
| Apple Developer Account | Paid ($99/yr) — required for App Store |
| App ID registered | At developer.apple.com → Identifiers |
| Bundle ID | `com.vocaglyph.app` (matches your `Info.plist`) |

---

## Step 1 — Register App ID on Apple Developer Portal

1. Go to [developer.apple.com](https://developer.apple.com) → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Click **+** → Choose **App IDs** → **App**.
3. Fill in:
   - **Description**: VocaGlyph
   - **Bundle ID**: `com.vocaglyph.app` (Explicit)
4. Click **Continue** → **Register** — that's it.

> **Note**: Most capabilities (Microphone, App Sandbox, Network, Speech Recognition, Hardened Runtime) are **not** configured on the Apple Developer Portal. They are configured in Xcode and your entitlements/Info.plist files. The portal has very few Mac-specific toggles (Push Notifications, iCloud, In-App Purchase, etc.) — none of which VocaGlyph needs.

### Where each VocaGlyph capability is actually configured

| Capability | Configured in |
|---|---|
| App Sandbox | Xcode → Signing & Capabilities → **+ App Sandbox** |
| Microphone | `VocaGlyph.entitlements` (`com.apple.security.device.audio-input`) ✅ already set |
| Network (outgoing) | `VocaGlyph.entitlements` (`com.apple.security.network.client`) ✅ already set |
| Speech Recognition | `Info.plist` (`NSSpeechRecognitionUsageDescription`) ✅ already set |
| Hardened Runtime | Xcode → Signing & Capabilities → **+ Hardened Runtime** |
| Accessibility | `Info.plist` (`NSAccessibilityUsageDescription`) ✅ already set |

---

## Step 2 — Create the Xcode App Project

> **Important**: Do **not** open just the `Package.swift` file — that gives you a "package project" without a proper App target. You need a separate `.xcodeproj` that wraps your SPM package.

1. Open **Xcode** → **File → New → Project…**
2. Choose **macOS → App** → click **Next**.
3. Fill in:
   - **Product Name**: `VocaGlyph`
   - **Team**: Your Apple Developer team
   - **Organization Identifier**: `com.vocaglyph`
   - **Bundle Identifier**: `com.vocaglyph.app`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Uncheck**: Include Tests (you already have SPM tests)
4. **Save location**: `voice-to-text/xcode-project/VocaGlyph.xcodeproj` (new subfolder alongside `swift-version/`).

---

## Step 3 — Add Dependencies

You have two options. **Option A** links your local source code directly (recommended during development). **Option B** adds the packages directly from GitHub (good if you want a clean, standalone Xcode project without referencing local paths).

---

### Option A — Add `swift-version/` as a Local Package (Recommended)

This keeps your existing source code at `swift-version/Sources/VocaGlyph/` without copying anything. The Xcode project references it in place.

**3A-1.** With your Xcode project open, look at the left-hand **Project Navigator** (the folder icon panel on the far left, `⌘1`). Click on the **blue `.xcodeproj` icon** at the very top — this opens the project settings in the main editor area.

**3A-2.** At the top of the main editor, you'll see a row of tabs: **General, Signing & Capabilities, Resource Tags, Info, Build Settings, Build Phases, Build Rules**. Also look for a **Package Dependencies** tab — click it.

**3A-3.** At the bottom-left of the Package Dependencies pane, click the **`+`** button.

**3A-4.** A sheet drops down with a search bar at the top right and a file browser. In the **bottom-left corner** of this sheet, you'll see a button labelled **"Add Local…"** — click it.

**3A-5.** A Finder file picker opens. Navigate to your `swift-version/` folder:
```
voice-to-text/
└── swift-version/     ← select this folder (it contains Package.swift)
```
Click **Add Package**.

**3A-6.** Xcode now reads `Package.swift` and resolves WhisperKit and MLX from GitHub automatically. This takes about 1–2 minutes. You'll see a progress spinner in the top Xcode toolbar.

**3A-7.** A sheet appears titled **"Choose Package Products and Targets"**. It lists all products your package exports. For each product, set the **"Add to Target"** column to **VocaGlyph**:

| Product | Add to Target |
|---|---|
| `WhisperKit` | VocaGlyph ✅ |
| `MLXLLM` | VocaGlyph ✅ |
| `MLXLMCommon` | VocaGlyph ✅ |

> If you see other products you don't recognise, leave them unchecked.

Click **Add Package**.

**3A-8.** In the Project Navigator, you'll now see a new section called **"Swift Package Dependencies"** with your local package and the GitHub packages nested inside it. ✅

---

### Option B — Fetch Dependencies Directly from GitHub

Use this if you want the Xcode project to be self-contained and not depend on the local `swift-version/` path. In this case **your source files must live inside the Xcode project folder** (you'd copy or move them), and the dependencies (WhisperKit, MLX) are fetched fresh from GitHub.

**3B-1.** In Xcode, click the **blue `.xcodeproj` icon** in the Project Navigator → **Package Dependencies** tab → click **`+`**.

**3B-2.** In the sheet that opens, you'll see a **search bar at the top right** that says *"Search or Enter Package URL"*. Paste the first URL:

```
https://github.com/argmaxinc/WhisperKit
```

Press **Enter**. Xcode fetches the package metadata.

**3B-3.** A version rule picker appears. Set it to:
- **Dependency Rule**: Up to Next Major Version
- **Version**: `0.10.0`

Click **Add Package**.

**3B-4.** The product chooser sheet appears. Set **WhisperKit** → Add to Target: **VocaGlyph**. Click **Add Package**.

**3B-5.** Repeat for MLX. Click **`+`** again and enter:

```
https://github.com/ml-explore/mlx-swift-lm
```

**3B-6.** Set dependency rule to **Branch: `main`** (matching your `Package.swift`). Click **Add Package**.

**3B-7.** In the product chooser, set:

| Product | Add to Target |
|---|---|
| `MLXLLM` | VocaGlyph ✅ |
| `MLXLMCommon` | VocaGlyph ✅ |

Click **Add Package**.

**3B-8.** Now add your **VocaGlyph source files** to the Xcode target. In Xcode: **File → Add Files to "VocaGlyph"…** → navigate to `swift-version/Sources/VocaGlyph/` → select the folder → ensure **"Add to target: VocaGlyph"** is checked → click **Add**.

> With Option B, you own the source files inside the Xcode project. Changes you make in Xcode directly edit the files in `swift-version/Sources/VocaGlyph/` since they're added by reference (not copied), unless you checked "Copy items if needed" — in that case you'd have two copies.

---

> **Which option should you use?**
> - Use **Option A** if you want to keep developing with your existing `swift-version/` SPM workflow (Makefile, CLI builds, tests) alongside Xcode.
> - Use **Option B** if you want a single standalone Xcode project and don't need the SPM CLI workflow anymore.

---

## Step 4 — Fix the Entry Point Conflict

Xcode generates a default `VocaGlyphApp.swift`. Your SPM package currently has an `.executableTarget` which also defines a `@main` entry — these will conflict.

**Fix in `Package.swift`** — change `.executableTarget` to `.target`:

```diff
-        .executableTarget(
+        .target(
             name: "VocaGlyph",
```

**Then delete** Xcode's generated `VocaGlyphApp.swift` and `ContentView.swift`, and replace with a thin entry point that imports your package:

```swift
// xcode-project/VocaGlyph/VocaGlyphApp.swift
import SwiftUI
import VocaGlyph

@main
struct VocaGlyphEntryPoint: App {
    var body: some Scene {
        VocaGlyphScene()   // use your actual top-level Scene type
    }
}
```

---

## Step 5 — Configure Info.plist

Your existing `swift-version/Info.plist` already has all the right keys. Point the Xcode target to it:

1. Select the **VocaGlyph target** → **Build Settings** → search `INFOPLIST_FILE`.
2. Set to the relative path from the `.xcodeproj`:
   ```
   ../swift-version/Info.plist
   ```

Keys already present (✅):
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSAccessibilityUsageDescription`
- `LSUIElement = true` (menu bar app, no Dock icon)

---

## Step 6 — Configure Signing & Capabilities

1. Select the **VocaGlyph target** → **Signing & Capabilities** tab.
2. Set **Team** to your Apple Developer team.
3. Confirm **Bundle Identifier** = `com.vocaglyph.app`.
4. Enable **Automatically manage signing**.
5. Click **+ Capability** and add:
   - **App Sandbox** → enable: **Network: Outgoing Connections (Client)**, **Hardware: Microphone**
   - **Hardened Runtime** → enable: **Audio Input**

---

## Step 7 — Configure the Entitlements File

Point the build setting to your existing entitlements file:

1. **Build Settings** → search `CODE_SIGN_ENTITLEMENTS` → set to:
   ```
   ../swift-version/VocaGlyph.entitlements
   ```

> **⚠️ App Review Warning**: Your entitlements include `com.apple.security.temporary-exception.mach-lookup.global-name` (needed for CGEvent tap / global hotkeys). This is a **restricted entitlement** — Apple must approve it. In your App Review notes, write something like:
>
> *"VocaGlyph uses a global hotkey to start/stop voice recording and paste transcribed text into the user's active app. The mach-lookup temporary exception is required to listen for the hotkey via CGEvent tap while running in a sandbox. The user must explicitly grant Accessibility permission in System Settings before this works."*

---

## Step 8 — Handle the MLX Metal Library

The MLX framework needs `mlx.metallib` placed **next to the binary** (`Contents/MacOS/`). Add a build phase in Xcode:

1. **Target → Build Phases → +** → **New Run Script Phase**.
2. Place it **before** "Copy Bundle Resources".
3. Script:

```bash
cd "${SRCROOT}/../swift-version"
swift package resolve --build-path "${BUILD_DIR}/spm-build"

# Compile MLX Metal shaders
MLX_METAL_DIR="${BUILD_DIR}/spm-build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
MLX_INCLUDE_DIR="${BUILD_DIR}/spm-build/checkouts/mlx-swift/Source/Cmlx"
MLX_AIR_DIR="${BUILD_DIR}/mlx-air"
mkdir -p "${MLX_AIR_DIR}"

for f in "${MLX_METAL_DIR}"/*.metal; do
    name=$(basename "$f" .metal)
    xcrun metal -std=metal3.1 -O2 -I "${MLX_INCLUDE_DIR}" -c "$f" -o "${MLX_AIR_DIR}/${name}.air"
done

xcrun metallib "${MLX_AIR_DIR}"/*.air -o "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS/mlx.metallib"
```

---

## Step 9 — Build Settings

| Setting | Value |
|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` |
| `SWIFT_VERSION` | `5.9` |
| `ENABLE_HARDENED_RUNTIME` | `YES` |
| `CODE_SIGN_STYLE` | `Automatic` |

---

## Step 10 — Build & Test in Xcode

```
Product → Build  (⌘B)
Product → Run    (⌘R)
```

Test checklist:
- [ ] VocaGlyph appears in menu bar
- [ ] Hotkey triggers recording
- [ ] Microphone permission prompt appears
- [ ] Transcription works (Apple Speech & WhisperKit)
- [ ] Text pastes into active app

---

## Step 11 — Archive for App Store

1. Set destination to **"Any Mac (Apple Silicon, Intel)"**.
2. **Product → Archive** (takes several minutes due to MLX).
3. **Organizer** opens → select archive → **Distribute App**.
4. Choose **App Store Connect → Upload → Next**.
5. Xcode validates and uploads automatically.

---

## Step 12 — App Store Connect Setup

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps → + → New App**.
2. Fill in:
   - **Platform**: macOS
   - **Name**: VocaGlyph
   - **Bundle ID**: `com.vocaglyph.app`
   - **Category**: Productivity
3. Complete **App Information**, **Pricing**, and **Privacy Policy URL** (required since you use microphone).

---

## Step 13 — Prepare App Store Assets

| Asset | Requirement |
|---|---|
| App Icon | 1024×1024 PNG (no alpha) |
| Screenshots | At least 1, size: 1280×800 or 2560×1600 |
| App Description | ≤ 4000 chars |
| Keywords | ≤ 100 chars total |
| Support URL | Required |
| Privacy Policy URL | Required |

Verify your icon size:
```bash
sips -g pixelWidth -g pixelHeight swift-version/Sources/VocaGlyph/Resources/appicon.png
```

---

## Step 14 — Submit for App Review

1. App Store Connect → your app → select build → **Submit for Review**.
2. In **Review Notes**, explain the mach-lookup entitlement (see Step 7 above).

---

## Common Issues & Fixes

| Issue | Fix |
|---|---|
| `@main` conflict | Change `.executableTarget` to `.target` in `Package.swift` |
| `mlx.metallib` not found at runtime | Ensure it's copied to `Contents/MacOS/`, not `Contents/Resources/` |
| Sandbox blocking paste/CGEvent | Accessibility permission required from user; entitlement exception must be approved by Apple |
| WhisperKit model download fails | `com.apple.security.network.client` must be enabled — already in your entitlements ✅ |
| Archive grayed out | Select "Any Mac" destination, not a simulator |
| Code signing error | Ensure Mac App Distribution certificate is in your keychain |

---

## Final Checklist

- [ ] App ID registered at developer.apple.com
- [ ] New Xcode macOS App project created at `xcode-project/`
- [ ] `swift-version/` added as local SPM dependency
- [ ] `.executableTarget` changed to `.target` in `Package.swift`
- [ ] Thin `@main` entry point in Xcode app target
- [ ] `INFOPLIST_FILE` → `../swift-version/Info.plist`
- [ ] `CODE_SIGN_ENTITLEMENTS` → `../swift-version/VocaGlyph.entitlements`
- [ ] App Sandbox + Hardened Runtime capabilities enabled
- [ ] MLX metallib build phase script added
- [ ] Deployment target = macOS 14.0
- [ ] Build succeeds (⌘B) and app runs (⌘R)
- [ ] Archive uploaded to App Store Connect
- [ ] App Store listing complete (icon, screenshots, description, privacy policy)
- [ ] App Review notes explain mach-lookup entitlement
- [ ] Submitted for review
