#!/bin/bash
# Baut die Swift-App als .app-Bundle und verpackt sie in ein DMG-Installationsimage.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Desktop Profile Manager"
DMG_NAME="DesktopProfileManager-Swift"
VERSION="1.2.0"

APP_PATH="$SCRIPT_DIR/dist/${APP_NAME}.app"
DMG_DIR="$SCRIPT_DIR/dmg_staging"
DMG_OUTPUT="$SCRIPT_DIR/${DMG_NAME}-${VERSION}.dmg"

echo "═══════════════════════════════════════════════"
echo " Desktop Profile Manager – DMG"
echo "═══════════════════════════════════════════════"

# 1. App-Bundle bauen
"$SCRIPT_DIR/build_app.sh"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App-Bundle nicht gefunden: $APP_PATH"
    exit 1
fi

# 2. DMG erstellen
echo "📦 Erstelle DMG-Installationsimage..."
rm -rf "$DMG_DIR" "$DMG_OUTPUT"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT"

rm -rf "$DMG_DIR"

echo ""
echo "═══════════════════════════════════════════════"
echo " ✅ Fertig!"
echo "═══════════════════════════════════════════════"
echo " App:  $APP_PATH"
echo " DMG:  $DMG_OUTPUT"
echo " Größe: $(du -h "$DMG_OUTPUT" | cut -f1)"
