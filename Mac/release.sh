#!/bin/bash
# Usage: ./release.sh [version]
#   e.g. ./release.sh 1.2.0
# Builds MinimalReport and packages it as a .dmg and .zip for GitHub releases.
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP_NAME="MinimalReport"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
STAGING="dist/staging"
OUTPUT="dist"

echo "▸ Building ${APP_NAME} ${VERSION}…"

# --- 1. Patch version into Info.plist ---
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" Resources/Info.plist

# --- 2. Compile (universal binary: arm64 + x86_64) ---
echo "▸ Compiling arm64…"
swift build -c release --arch arm64   2>&1 | grep -v "^Build complete"
echo "▸ Compiling x86_64…"
swift build -c release --arch x86_64  2>&1 | grep -v "^Build complete"
echo "▸ Creating universal binary with lipo…"
mkdir -p ".build/release-universal"
lipo -create -output ".build/release-universal/${APP_NAME}" \
    ".build/arm64-apple-macosx/release/${APP_NAME}" \
    ".build/x86_64-apple-macosx/release/${APP_NAME}"
echo "  ✓ Universal binary ready"

# --- 3. Bundle .app ---
pkill -x "${APP_NAME}" 2>/dev/null || true
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"
cp ".build/release-universal/${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_NAME}.app/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_NAME}.app/Contents/Resources/AppIcon.icns"
echo "  ✓ App bundle created"

# --- 4. Quarantine workaround ---
# Strip the com.apple.quarantine attribute from the binary so users don't
# have to right-click → Open on first launch (self-built app, no notarization).
xattr -cr "${APP_NAME}.app" 2>/dev/null || true

# --- 5. Prepare output folder ---
rm -rf "${OUTPUT}"
mkdir -p "${STAGING}"

cp -R "${APP_NAME}.app" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"

# --- 6. Create DMG ---
echo "▸ Creating ${DMG_NAME}…"
TEMP_DMG="${OUTPUT}/temp.dmg"

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${STAGING}" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "${TEMP_DMG}" \
    > /dev/null

# Mount with an explicit mountpoint so detach is reliable
MOUNT_POINT="${OUTPUT}/mnt_$$"
mkdir -p "${MOUNT_POINT}"
hdiutil attach "${TEMP_DMG}" -mountpoint "${MOUNT_POINT}" -nobrowse -quiet

# Set a decent window size via osascript (best effort — skip if it times out)
osascript -e "
tell application \"Finder\"
    tell disk \"${APP_NAME} ${VERSION}\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 680, 420}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item \"${APP_NAME}.app\" of container window to {160, 175}
        set position of item \"Applications\" of container window to {460, 175}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
" 2>/dev/null || true

sync; sleep 1
hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
rmdir "${MOUNT_POINT}" 2>/dev/null || true

# Convert to compressed read-only DMG
hdiutil convert "${TEMP_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${OUTPUT}/${DMG_NAME}" \
    > /dev/null

rm -f "${TEMP_DMG}"
echo "  ✓ ${DMG_NAME}"

# --- 7. Create ZIP ---
echo "▸ Creating ${ZIP_NAME}…"
(cd dist && ditto -c -k --keepParent "staging/${APP_NAME}.app" "${ZIP_NAME}")
echo "  ✓ ${ZIP_NAME}"

# --- 8. Cleanup staging ---
rm -rf "${STAGING}"

# --- 9. Summary ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Release artifacts in dist/"
ls -lh dist/*.dmg dist/*.zip 2>/dev/null | awk '{print "  " $5 "  " $9}'
echo ""
echo "  GitHub release steps:"
echo "  1. git tag v${VERSION} && git push origin v${VERSION}"
echo "  2. gh release create v${VERSION} \\"
echo "       dist/${DMG_NAME} \\"
echo "       dist/${ZIP_NAME} \\"
echo "       --title \"MinimalReport v${VERSION}\" \\"
echo "       --notes \"See README for install instructions.\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
