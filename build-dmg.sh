#!/bin/sh
# Package ANC.app into a polished ANC.dmg: background image, sized window,
# hidden toolbar, and app + Applications icons positioned for drag-to-install.
set -e
cd "$(dirname "$0")"
./build-app.sh

# Background image (regenerate from dmgbg.swift if missing).
[ -f dmg-bg.png ] || { TMPBIN=$(mktemp -d); swiftc -O dmgbg.swift -o "$TMPBIN/mkbg" && "$TMPBIN/mkbg" dmg-bg.png; rm -rf "$TMPBIN"; }

VOL="ANC"
TMPDMG=$(mktemp -u).dmg
rm -f ANC.dmg

# Build a writable DMG, populate it, then let Finder record the layout.
hdiutil create -volname "$VOL" -size 20m -fs HFS+ -ov -quiet "$TMPDMG"
hdiutil attach "$TMPDMG" -noautoopen -quiet
MNT="/Volumes/$VOL"
cp -R ANC.app "$MNT/"
ln -s /Applications "$MNT/Applications"
mkdir "$MNT/.background"
cp dmg-bg.png "$MNT/.background/bg.png"

# Finder layout — best effort; needs Automation permission for Finder.
# If it fails (e.g. TCC-blocked), the DMG still builds without the styling.
osascript <<'APPLESCRIPT' || echo "warning: Finder layout step failed — DMG built without custom layout (grant Automation access to Finder to enable it)"
tell application "Finder"
  tell disk "ANC"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 840, 550}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 12
    set background picture of opts to file ".background:bg.png"
    set position of item "ANC.app" of container window to {160, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MNT" -quiet
hdiutil convert "$TMPDMG" -format UDZO -o ANC.dmg -ov -quiet
rm -f "$TMPDMG"
# ponytail: unsigned/un-notarized — recipients must right-click > Open once.
# To sign for real distribution, before hdiutil convert:
#   codesign --deep --options runtime -s "Developer ID Application: NAME (TEAMID)" "$MNT/ANC.app"
#   (then notarize ANC.dmg with: xcrun notarytool submit … && xcrun stapler staple ANC.dmg)
echo "Built ANC.dmg ($(du -h ANC.dmg | cut -f1))"
