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

# Icon: icon.png -> AppIcon.icns (regenerate icon.png with icon.swift if missing).
mkdir -p "$APP/Contents/Resources"
[ -f icon.png ] || { TMPBIN=$(mktemp -d); swiftc -O icon.swift -o "$TMPBIN/mkicon" && "$TMPBIN/mkicon" icon.png; rm -rf "$TMPBIN"; }
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s        icon.png --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ancbar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.andi.ancbar</string>
  <key>CFBundleName</key><string>ANC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "Built $APP — double-click it, or run: open $APP"
