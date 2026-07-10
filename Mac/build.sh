#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building MinimalReport..."
swift build -c release

echo "Packaging into app bundle..."
pkill -x MinimalReport 2>/dev/null || true
rm -rf MinimalReport.app
mkdir -p MinimalReport.app/Contents/MacOS
mkdir -p MinimalReport.app/Contents/Resources
cp .build/release/MinimalReport MinimalReport.app/Contents/MacOS/MinimalReport
cp Resources/Info.plist MinimalReport.app/Contents/Info.plist
cp Resources/AppIcon.icns MinimalReport.app/Contents/Resources/AppIcon.icns

# Ad-hoc sign so macOS gives the app a stable identity — required for the
# Accessibility (auto-paste) permission to stick.
codesign --force --deep --sign - MinimalReport.app 2>/dev/null || true

echo ""
echo "Done! Run with:  open MinimalReport.app"
