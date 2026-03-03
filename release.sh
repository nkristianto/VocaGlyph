#!/bin/bash
# ──────────────────────────────────────────────────────────────
# VocaGlyph Release Script
# Usage: ./release.sh <version>   e.g. ./release.sh 0.1.0
# Expects: distribute-devid.sh has already been run (notarized app in dist/DevID/)
# ──────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:?Usage: $0 <version>  e.g. $0 1.0}"
TAG="v$VERSION"
APP="$SCRIPT_DIR/xcode-project/VocaGlyph/dist/DevID/VocaGlyph.app"
DMG="$SCRIPT_DIR/xcode-project/VocaGlyph/dist/DevID/VocaGlyph-${VERSION}.dmg"
RELEASES_DIR=~/releases/vocaglyph
REPO_ROOT="$SCRIPT_DIR"

echo "🚀 Releasing VocaGlyph $TAG"

# ── 1. Verify the notarized app exists ───────────────────────
if [ ! -d "$APP" ]; then
  echo "❌ VocaGlyph.app not found at $APP"
  echo "   Run ./xcode-project/VocaGlyph/distribute-devid.sh first."
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
  --keychain-profile "AC_notary" \
  --wait
xcrun stapler staple "$DMG"
echo "✅ DMG notarized and stapled: $DMG"

# ── 3. Generate signed appcast entry ─────────────────────────
# Each version gets its own subdirectory so generate_appcast only
# produces the new entry (with the correct tag URL), which is then
# merged back into the full appcast.xml.
VERSION_DIR="$RELEASES_DIR/$TAG"
mkdir -p "$VERSION_DIR"
cp "$DMG" "$VERSION_DIR/"

# ── Verify embedded app version matches the release version ──
MOUNT_POINT=$(mktemp -d)
hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -quiet -nobrowse
EMBEDDED_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
  "$MOUNT_POINT/VocaGlyph.app/Contents/Info.plist" 2>/dev/null || echo "unknown")
hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "$MOUNT_POINT"

if [ "$EMBEDDED_VERSION" != "$VERSION" ]; then
  echo "❌ Version mismatch! DMG contains app version '$EMBEDDED_VERSION' but expected '$VERSION'."
  echo "   Please update CFBundleShortVersionString and CFBundleVersion in Xcode, rebuild, and retry."
  rm -f "$VERSION_DIR/$(basename "$DMG")"
  exit 1
fi
echo "✅ Embedded app version verified: $EMBEDDED_VERSION"

GENERATE_APPCAST=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "generate_appcast" -not -path "*.dSYM*" 2>/dev/null | head -1)

if [ -z "$GENERATE_APPCAST" ]; then
  echo "❌ generate_appcast not found — build the project in Xcode first."
  exit 1
fi

# Generate a partial appcast for just this release's DMG.
TMP_APPCAST=$(mktemp -u /tmp/appcast_new_XXXXXX.xml)
security find-generic-password -a "ed25519" -w > /tmp/vg_key.b64
"$GENERATE_APPCAST" \
  --ed-key-file /tmp/vg_key.b64 \
  "$VERSION_DIR" \
  --download-url-prefix "https://github.com/nkristianto/VocaGlyph/releases/download/$TAG/" \
  -o "$TMP_APPCAST"
rm /tmp/vg_key.b64

# Merge: extract the new <item> block and prepend it into the existing appcast.
NEW_ITEM=$(xmllint --xpath '//item' "$TMP_APPCAST" 2>/dev/null || \
  python3 -c "
import xml.etree.ElementTree as ET, sys
tree = ET.parse('$TMP_APPCAST')
for item in tree.findall('.//item'):
    print(ET.tostring(item, encoding='unicode'))
")
rm -f "$TMP_APPCAST"

if [ -f "$REPO_ROOT/appcast.xml" ]; then
  # Insert new item after the opening <channel> tags (before the first existing <item>).
  python3 - <<EOF
import re, sys
with open('$REPO_ROOT/appcast.xml', 'r') as f:
    content = f.read()
new_item = '''$NEW_ITEM'''
# Insert before first <item>
content = content.replace('<item>', new_item + '\n        <item>', 1)
with open('$REPO_ROOT/appcast.xml', 'w') as f:
    f.write(content)
EOF
  echo "✅ New <item> prepended to appcast.xml"
else
  # No existing appcast — run generate_appcast across ALL version dirs.
  ALL_DMGS_DIR=$(mktemp -d)
  find "$RELEASES_DIR" -name '*.dmg' -exec cp {} "$ALL_DMGS_DIR/" \;
  security find-generic-password -a "ed25519" -w > /tmp/vg_key.b64
  "$GENERATE_APPCAST" \
    --ed-key-file /tmp/vg_key.b64 \
    "$ALL_DMGS_DIR" \
    --download-url-prefix "https://github.com/nkristianto/VocaGlyph/releases/download/$TAG/" \
    -o "$REPO_ROOT/appcast.xml"
  rm /tmp/vg_key.b64
  rm -rf "$ALL_DMGS_DIR"
  echo "✅ appcast.xml created"
fi

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