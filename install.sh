#!/bin/bash
# Builds SideNotes as a real .app, installs it in /Applications,
# adds it to Login Items so it starts every time you log in, then launches it.
set -e
cd "$(dirname "$0")"

echo "Building release..."
swift build -c release

APP="/Applications/SideNotes.app"
pkill -x SideNotes 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SideNotes "$APP/Contents/MacOS/SideNotes"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SideNotes</string>
  <key>CFBundleDisplayName</key><string>SideNotes</string>
  <key>CFBundleIdentifier</key><string>com.sidd.sidenotes</string>
  <key>CFBundleExecutable</key><string>SideNotes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>SideNotes copies your notes into Apple Notes when you ask it to.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Add to Login Items (skip if already there)
if ! osascript -e 'tell application "System Events" to get the name of every login item' | grep -q SideNotes; then
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP\", hidden:true}"
fi

open "$APP"
echo "Done. SideNotes is in /Applications, starts at login, and toggles with Option+Cmd+N."
