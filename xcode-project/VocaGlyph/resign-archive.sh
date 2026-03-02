#!/bin/sh
# resign-archive.sh
# Workaround for Xcode 26 beta bug: Organizer re-signs the archive binary
# with Developer ID Application after the build, stripping entitlements.
#
# Run this script AFTER archiving and BEFORE clicking "Validate App":
#   ./resign-archive.sh
#
# Optional: pass an archive path explicitly:
#   ./resign-archive.sh "/path/to/MyApp.xcarchive"

set -e

ARCHIVES_DIR="$HOME/Library/Developer/Xcode/Archives"
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"
APP_NAME="VocaGlyph"
CERT="Apple Distribution: Novian Kristianto (3C269K7QLF)"

# ── 1. Find the archive ───────────────────────────────────────────────────────
if [ -n "$1" ]; then
  ARCHIVE="$1"
else
  ARCHIVE=$(find "$ARCHIVES_DIR" -name "${APP_NAME}*.xcarchive" -maxdepth 2 \
    | xargs ls -dt 2>/dev/null | head -1)
fi

if [ -z "$ARCHIVE" ] || [ ! -d "$ARCHIVE" ]; then
  echo "error: No .xcarchive found. Pass the path as an argument or archive first."
  exit 1
fi
echo "Archive: $ARCHIVE"

APP="$ARCHIVE/Products/Applications/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
  echo "error: ${APP_NAME}.app not found inside archive."
  exit 1
fi

# ── 2. Find the .xcent from DerivedData ──────────────────────────────────────
# Prefer the most recently modified .xcent for this app.
XCENT=$(find "$DERIVED_DATA_DIR/${APP_NAME}-"* \
  -path "*/ArchiveIntermediates/${APP_NAME}/*/${APP_NAME}.app.xcent" \
  2>/dev/null | xargs ls -t 2>/dev/null | head -1)

if [ -z "$XCENT" ] || [ ! -f "$XCENT" ]; then
  echo "warning: .xcent not found in DerivedData — falling back to source entitlements"
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  XCENT="$SCRIPT_DIR/VocaGlyph/VocaGlyph.entitlements"
fi

if [ ! -f "$XCENT" ]; then
  echo "error: No entitlements file found. Archive and try again."
  exit 1
fi
echo "Entitlements: $XCENT"

# ── 3. Show entitlements for confirmation ─────────────────────────────────────
echo ""
echo "Entitlements to embed:"
cat "$XCENT"
echo ""

# ── 4. Re-sign — exact same command confirmed to fix validation ───────────────
echo "Re-signing ${APP_NAME}.app..."
codesign --force \
  --sign "$CERT" \
  --options runtime \
  --entitlements "$XCENT" \
  --timestamp \
  "$APP" 2>&1

echo ""
echo "Verifying signature:"
codesign -d -vvvv "$APP/Contents/MacOS/${APP_NAME}" 2>&1 \
  | grep -E "CodeDirectory|Authority|hashes|flags"

echo ""
echo "✅ Done. Archive is ready to validate in Organizer."
