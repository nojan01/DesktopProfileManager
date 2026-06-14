#!/bin/bash
# Baut die Swift-App und verpackt sie als .app-Bundle (Menüleisten-App).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Desktop Profile Manager"
BUNDLE_ID="com.desktopprofilemanager.swift"
VERSION="1.2.0"

echo "🔨 Baue Release-Binary..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/DesktopProfileManager"

APP_DIR="$SCRIPT_DIR/dist/${APP_NAME}.app"
echo "📦 Erstelle App-Bundle: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/DesktopProfileManager"

# App-Icon (Dock/Finder) und Menüleisten-Icon übernehmen
if [ -f "$SCRIPT_DIR/icon.icns" ]; then
    cp "$SCRIPT_DIR/icon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -f "$SCRIPT_DIR/icon.png" ]; then
    cp "$SCRIPT_DIR/icon.png" "$APP_DIR/Contents/Resources/icon.png"
fi

# Hilfe-Dateien (HTML, sprachabhängig) übernehmen
for help in "$SCRIPT_DIR/Resources/"help_*.html; do
    [ -f "$help" ] && cp "$help" "$APP_DIR/Contents/Resources/"
done

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>DesktopProfileManager</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Wird zum Speichern/Wiederherstellen von Icon-Positionen, Fenstern und Hintergrund benötigt.</string>
</dict>
</plist>
PLIST

echo "✅ Fertig: $APP_DIR"
echo "   Start:  open \"$APP_DIR\""
