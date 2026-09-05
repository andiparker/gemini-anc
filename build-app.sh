#!/bin/sh
# Build ANC.app — a double-clickable menu-bar app (no Terminal, no Dock icon).
set -e
cd "$(dirname "$0")"
APP=ANC.app
MACOS="$APP/Contents/MacOS"
rm -rf "$APP"
mkdir -p "$MACOS"
swiftc -O anc.swift    -o "$MACOS/anc"       # CLI, resolved as a sibling by ancbar
swiftc -O ancbar.swift -o "$MACOS/ancbar"    # menu-bar front end (CFBundleExecutable)
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ancbar</string>
  <key>CFBundleIdentifier</key><string>dev.andi.ancbar</string>
  <key>CFBundleName</key><string>ANC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "Built $APP — double-click it, or run: open $APP"
