#!/bin/sh
# Build ANC.app — a double-clickable menu-bar app (no Terminal, no Dock icon).
set -e
cd "$(dirname "$0")"

for t in swiftc sips iconutil lipo; do
    command -v "$t" >/dev/null || { echo "missing tool: $t — install the Xcode Command Line Tools (xcode-select --install)"; exit 1; }
done

# Version is derived from the latest git tag (single source of truth); build number from commit count.
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); [ -n "$VERSION" ] || VERSION=0.0.0
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)

APP=ANC.app
MACOS="$APP/Contents/MacOS"
rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources"

# Universal (arm64 + x86_64), pinned to the advertised macOS floor — not the build host's OS.
for b in anc ancbar; do
    swiftc -O -target arm64-apple-macos13.0  "$b.swift" -o "$MACOS/$b.arm64"
    swiftc -O -target x86_64-apple-macos13.0 "$b.swift" -o "$MACOS/$b.x86_64"
    lipo -create "$MACOS/$b.arm64" "$MACOS/$b.x86_64" -o "$MACOS/$b"
    rm "$MACOS/$b.arm64" "$MACOS/$b.x86_64"
done

# Icon: regenerate icon.png when its generator is newer (or it's missing), then build AppIcon.icns.
if [ ! -f icon.png ] || [ icon.swift -nt icon.png ]; then
    TMPBIN=$(mktemp -d); swiftc -O icon.swift -o "$TMPBIN/mkicon" && "$TMPBIN/mkicon" icon.png; rm -rf "$TMPBIN"
fi
ICONSETDIR=$(mktemp -d); ICONSET="$ICONSETDIR/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s        icon.png --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSETDIR"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ancbar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.andi.ancbar</string>
  <key>CFBundleName</key><string>ANC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>ANC controls your Devialet Gemini II earbuds over Bluetooth.</string>
</dict></plist>
PLIST
echo "Built $APP $VERSION ($BUILD) — double-click it, or run: open $APP"
