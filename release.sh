#!/bin/bash
# ──────────────────────────────────────────────────────────────
# VocaGlyph Release Script
# Usage: ./release.sh <version>   e.g. ./release.sh 0.1.0
# Expects: VocaGlyph.app already notarized on ~/Desktop/
# ──────────────────────────────────────────────────────────────
set -e

VERSION="${1:?Usage: $0 <version>  e.g. $0 1.0}"
TAG="v$VERSION"
APP=~/Desktop/VocaGlyph.app
DMG=~/Desktop/VocaGlyph-${VERSION}.dmg
RELEASES_DIR=~/releases/vocaglyph
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 Releasing VocaGlyph $TAG"

# ── 1. Verify the notarized app exists ───────────────────────
if [ ! -d "$APP" ]; then
  echo "❌ VocaGlyph.app not found on Desktop. Notarize it first."
  exit 1
fi
codesign --verify --deep --strict "$APP" && echo "✅ Signature OK"

# ── 2. Build DMG with create-dmg ─────────────────────────────
if ! command -v create-dmg &>/dev/null; then
  echo "❌ create-dmg not installed. Run: brew install create-dmg"
  exit 1
fi

create-dmg \
  --volname "VocaGlyph" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "VocaGlyph.app" 150 185 \
  --hide-extension "VocaGlyph.app" \
  --app-drop-link 450 185 \
  "$DMG" \
  "$APP"

# ── 3. Notarize the DMG and staple ───────────────────────────
# The .app inside is already notarized, but the DMG is a NEW file
# that Apple has no record of — so we must submit it separately.
echo "Submitting DMG for notarization (may take 1-5 min)..."
xcrun notarytool submit "$DMG" \
  --keychain-profile "VocaGlyph-notary" \
  --wait
xcrun stapler staple "$DMG"
echo "✅ DMG notarized and stapled: $DMG"

# ── 3. Generate signed appcast entry ─────────────────────────
mkdir -p "$RELEASES_DIR"
cp "$DMG" "$RELEASES_DIR/"

GENERATE_APPCAST=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "generate_appcast" -not -path "*.dSYM*" 2>/dev/null | head -1)

if [ -z "$GENERATE_APPCAST" ]; then
  echo "❌ generate_appcast not found — build the project in Xcode first."
  exit 1
fi

security find-generic-password -a "ed25519" -w > /tmp/vg_key.b64
"$GENERATE_APPCAST" \
  --ed-key-file /tmp/vg_key.b64 \
  "$RELEASES_DIR" \
  --download-url-prefix "https://github.com/nkristianto/VocaGlyph/releases/download/$TAG/" \
  -o "$REPO_ROOT/appcast.xml"
rm /tmp/vg_key.b64
echo "✅ appcast.xml updated"

# ── 4. Commit and push appcast ────────────────────────────────
cd "$REPO_ROOT"
git add appcast.xml
git commit -m "Release $TAG"
git push swift-origin main
echo "✅ appcast.xml pushed to GitHub"

# ── 5. Done — remind to create GitHub Release ─────────────────
echo ""
echo "🎉 Done! Final step:"
echo "   Go to https://github.com/nkristianto/VocaGlyph/releases/new"
echo "   Tag: $TAG  |  Attach: $DMG"