#!/bin/sh
# distribute-devid.sh
# Exports, notarizes, and staples VocaGlyph for direct download (Developer ID).
#
# Workaround for Xcode 26 beta bug where Organizer "Direct Distribution"
# produces an invalid binary signature. This CLI path works correctly.
#
# Prerequisites:
#   xcrun notarytool store-credentials "AC_notary" \
#     --apple-id "YOUR_APPLE_ID" \
#     --team-id "3C269K7QLF" \
#     --password "APP_SPECIFIC_PASSWORD"
#
# Usage:
#   ./distribute-devid.sh                          # uses latest archive
#   ./distribute-devid.sh "/path/to/MyApp.xcarchive"  # explicit archive

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVES_DIR="$HOME/Library/Developer/Xcode/Archives"
APP_NAME="VocaGlyph"
KEYCHAIN_PROFILE="AC_notary"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions-DevID.plist"
EXPORT_DIR="$SCRIPT_DIR/dist/DevID"

# ── 1. Find archive ───────────────────────────────────────────────────────────
if [ -n "$1" ]; then
  ARCHIVE="$1"
else
  ARCHIVE=$(ls -dt "$ARCHIVES_DIR"/????-??-??/"${APP_NAME}"*.xcarchive 2>/dev/null | head -1)
fi

if [ -z "$ARCHIVE" ] || [ ! -d "$ARCHIVE" ]; then
  echo "error: No .xcarchive found. Archive first or pass path as argument."
  exit 1
fi
echo "Archive : $ARCHIVE"
echo "Output  : $EXPORT_DIR"
echo ""

# ── 2. Export (re-signs with Developer ID Application) ───────────────────────
rm -rf "$EXPORT_DIR"
mkdir -p "$(dirname "$EXPORT_DIR")"

echo "Step 1/4 — Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  2>&1 | grep -E "EXPORT|error:|warning:" || true
echo "Exported to $EXPORT_DIR"

APP="$EXPORT_DIR/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
  echo "error: ${APP_NAME}.app not found at $APP"
  exit 1
fi

# ── 3. Verify signature before submitting ────────────────────────────────────
echo ""
echo "Step 2/4 — Verifying signature..."
codesign -d -vvvv "$APP/Contents/MacOS/$APP_NAME" 2>&1 | grep -E "Authority|hashes"
codesign --verify --deep --strict "$APP" && echo "Signature: valid ✅"

# ── 4. Zip and notarize ───────────────────────────────────────────────────────
ZIP="$EXPORT_DIR/${APP_NAME}.zip"
echo ""
echo "Step 3/4 — Zipping..."
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zipped: $ZIP"

echo ""
echo "Step 4/4 — Notarizing (this takes a few minutes)..."
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

# ── 5. Staple ─────────────────────────────────────────────────────────────────
echo ""
echo "Stapling ticket..."
xcrun stapler staple "$APP"

echo ""
echo "✅ Done! Notarized app: $APP"
echo "   You can now distribute it (drag to /Applications, DMG, Sparkle, etc.)"
