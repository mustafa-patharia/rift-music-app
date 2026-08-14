#!/bin/bash
# Build Rift.app (Release) and pack it into a styled drag-to-Applications DMG.
#
#   ./scripts/make-dmg.sh            → build/Rift.dmg
#
# Styled window: app icon on the left, Applications folder on the right,
# drag-across layout (the classic "install" screen).
#
# ponytail: unsigned + un-notarized — fine for dev/side-loading (users
# right-click → Open once). Add codesign + notarytool before a public release.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Rift"
BUILD_DIR="build/dmg"
DERIVED="build/DerivedData"
VOL="$APP_NAME"
RW_DMG="build/${APP_NAME}-rw.dmg"
FINAL_DMG="build/${APP_NAME}.dmg"

echo "▸ building Release…"
xcodebuild -project Rift.xcodeproj -scheme Rift \
  -configuration Release -derivedDataPath "$DERIVED" build | grep -E "error:|BUILD" || true

APP_PATH=$(ls -td "$DERIVED"/Build/Products/Release/*.app | head -1)
[ -d "$APP_PATH" ] || { echo "✗ no .app produced"; exit 1; }

echo "▸ rendering background…"
swift scripts/dmg-bg.swift build/dmg-bg.png

echo "▸ staging…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/.background"
cp -R "$APP_PATH" "$BUILD_DIR/$APP_NAME.app"
cp build/dmg-bg.png "$BUILD_DIR/.background/bg.png"
ln -s /Applications "$BUILD_DIR/Applications"

# --- build a read-write DMG we can decorate via Finder --------------------
echo "▸ creating writable dmg…"
rm -f "$RW_DMG" "$FINAL_DMG"
hdiutil create -volname "$VOL" -srcfolder "$BUILD_DIR" \
  -ov -format UDRW "$RW_DMG"

echo "▸ mounting…"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | \
      grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOL"

# Finder needs a beat after attach before it sees the volume.
osascript -e 'delay 1'

echo "▸ styling window…"
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background picture of viewOptions to POSIX file "$MOUNT/.background/bg.png"
    set position of item "$APP_NAME.app" of container window to {150, 200}
    set position of item "Applications" of container window to {450, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync

echo "▸ detaching…"
hdiutil detach "$DEV" || hdiutil detach "$DEV" -force

echo "▸ compressing…"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$RW_DMG"

echo "✓ $FINAL_DMG"
