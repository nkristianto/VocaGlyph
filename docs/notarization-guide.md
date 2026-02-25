# Notarization & Distribution Guide

## Option A — Xcode Organizer (Recommended)

The easiest route. Xcode handles signing, notarization, and stapling automatically.

1. **Product → Archive**
2. **Organizer → Distribute App → Direct Distribution → Next**
3. Xcode signs with your Developer ID Application cert, submits to Apple, waits for notarization (~1–5 min)
4. When complete, click **Save** → choose a folder → you get a notarized `VocaGlyph.app`
5. Package as DMG (see Step 5 below)

---

## Option B — Manual via `notarytool`

Use this for CI/CD pipelines or when you need full control.

### Prerequisites

- **Developer ID Application** certificate in your Keychain
- **App-specific password** from [appleid.apple.com](https://appleid.apple.com) → App-Specific Passwords

### Store credentials once (run this once, reuse forever)

```bash
xcrun notarytool store-credentials "VocaGlyph-notary" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Find your Team ID:
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# Output: ... "Developer ID Application: Your Name (ABCD123456)" ← that's your Team ID
```

### Full sequence

```bash
# 1 — Extract .app correctly from the latest .xcarchive
ARCHIVE=$(ls -dt ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)
ditto "$ARCHIVE/Products/Applications/VocaGlyph.app" ~/Desktop/VocaGlyph.app

# 2 — Re-sign with Developer ID Application certificate
#     --timestamp   : required by Apple notarization
#     --options runtime : enables Hardened Runtime (required by Apple)
#     --deep        : signs all nested frameworks/dylibs
CERT="Developer ID Application: Your Name (TEAMID)"

codesign --force --deep \
  --sign "$CERT" \
  --timestamp \
  --options runtime \
  ~/Desktop/VocaGlyph.app

# 3 — Verify signature before submitting
codesign --verify --deep --strict ~/Desktop/VocaGlyph.app && echo "✅ Signature OK"

# 4 — Zip and submit for notarization
cd ~/Desktop
ditto -c -k --keepParent VocaGlyph.app VocaGlyph.zip

xcrun notarytool submit VocaGlyph.zip \
  --keychain-profile "VocaGlyph-notary" \
  --wait

# 5 — Staple the approval ticket onto the .app
xcrun stapler staple VocaGlyph.app
xcrun stapler validate VocaGlyph.app  # confirm it worked

# 6 — Package as DMG
hdiutil create -volname "VocaGlyph" -srcfolder VocaGlyph.app \
  -ov -format UDZO VocaGlyph.dmg
```

If notarization fails, fetch the rejection log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "VocaGlyph-notary"
```

---

## Option C — Signed DMG for Internal Testers (Recommended)

> This uses your **Developer ID Application** certificate to sign the app — required for
> the microphone (and other TCC) permission dialogs to appear. No notarization is needed
> for internal testing, but signing IS required.

> [!IMPORTANT]
> When building with `xcodebuild … build` (not Archive), Xcode normally injects the debug-only
> entitlement `com.apple.security.get-task-allow`. macOS TCC sees this and silently refuses to
> show any permission dialogs. Always pass `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` to prevent
> this — the build command below includes it.

### Build & sign the DMG

```bash
# 1 — Build a Release .app from the command line
#     CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO prevents Xcode from adding
#     the debug-only get-task-allow entitlement to the Release build.
cd /Users/nkristianto/Workspace/Personal/voice-to-text/xcode-project/VocaGlyph
xcodebuild -scheme VocaGlyph -configuration Release \
  -derivedDataPath /tmp/VocaGlyph-build \
  CODE_SIGN_IDENTITY="Developer ID Application: Novian Kristianto (3C269K7QLF)" \
  DEVELOPMENT_TEAM="3C269K7QLF" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

# 2 — Copy the built .app out of DerivedData
#     Always rm -rf first — cp -R will nest the app inside an existing directory
rm -rf ~/Desktop/VocaGlyph.app
cp -R /tmp/VocaGlyph-build/Build/Products/Release/VocaGlyph.app ~/Desktop/VocaGlyph.app

# 3 — Verify: signature OK and no get-task-allow
codesign --verify --deep --strict ~/Desktop/VocaGlyph.app && echo "✅ Signature OK"
codesign -d --entitlements - --xml ~/Desktop/VocaGlyph.app 2>/dev/null | plutil -p - | grep -v get-task-allow && echo "✅ No get-task-allow"

# 4 — Package as DMG
hdiutil create -volname "VocaGlyph" -srcfolder ~/Desktop/VocaGlyph.app \
  -ov -format UDZO ~/Desktop/VocaGlyph-tester.dmg
```

> **Already ran the app without these steps?** Reset the TCC cache before testing:
> ```bash
> tccutil reset Microphone com.vocaglyph.app
> ```
> macOS caches permission states; resetting forces it to ask again.

### Tester instructions (how to open an app without notarization)

Send this to your testers along with the DMG:

1. Mount the DMG → drag `VocaGlyph.app` to `/Applications`
2. **Do NOT double-click to open** — Gatekeeper may block it without notarization
3. Instead: **Right-click** (or Control-click) on `VocaGlyph.app` → **Open**
4. A dialog appears warning about an unverified developer → click **Open** to proceed
5. After the first successful launch, you can open it normally going forward

> **Alternative (tester runs in Terminal):**
> ```bash
> xattr -d com.apple.quarantine /Applications/VocaGlyph.app
> ```
> This removes the Gatekeeper quarantine flag so the app opens without the warning.

---

## Notarization timing

| Scenario | Time |
|---|---|
| Typical | 1–5 minutes |
| Busy period (WWDC, holidays) | 15–30 minutes |
| Large binary with MLX | 5–15 minutes |
