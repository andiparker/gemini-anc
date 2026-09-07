#!/bin/sh
# Package ANC.app into a polished ANC.dmg: background image, sized window,
# hidden toolbar, and app + Applications icons positioned for drag-to-install.
set -e
cd "$(dirname "$0")"
./build-app.sh

# Background image (regenerate from dmgbg.swift if missing).
[ -f dmg-bg.png ] || { TMPBIN=$(mktemp -d); swiftc -O dmgbg.swift -o "$TMPBIN/mkbg" && "$TMPBIN/mkbg" dmg-bg.png; rm -rf "$TMPBIN"; }

# Optional code signing for distribution. Set SIGN_ID to your Developer ID Application
# identity, e.g. SIGN_ID="Developer ID Application: Andrew Parker (LZNV892WN2)".
# Sign nested binaries first, then the bundle, all with the hardened runtime (notarization requires it).
if [ -n "$SIGN_ID" ]; then
    echo "Signing with: $SIGN_ID"
    codesign --force --options runtime --timestamp -s "$SIGN_ID" ANC.app/Contents/MacOS/anc
    codesign --force --options runtime --timestamp -s "$SIGN_ID" ANC.app/Contents/MacOS/ancbar
    codesign --force --options runtime --timestamp -s "$SIGN_ID" ANC.app
    codesign --verify --strict --verbose=2 ANC.app
fi

# Notarize + staple the APP itself (via a zip) before packaging, so the app carries its own
# ticket and opens offline once dragged out of the DMG. The DMG is notarized separately below.
if [ -n "$NOTARY_PROFILE" ]; then
    echo "Notarizing ANC.app …"
    ZIP=$(mktemp -u).zip
    ditto -c -k --keepParent ANC.app "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP"
    xcrun stapler staple ANC.app
    spctl -a -vvv --type exec ANC.app   # Gatekeeper gate: must print "accepted / Notarized Developer ID"
fi

VOL="ANC"
TMPDMG=$(mktemp -u).dmg
rm -f ANC.dmg

# Build a writable DMG, populate it, then let Finder record the layout.
# Must mount in /Volumes so Finder can address the volume by name ("disk ANC").
hdiutil detach "/Volumes/$VOL" -force -quiet 2>/dev/null || true  # clear a stale mount of the same name
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

# Optional notarization. Requires SIGN_ID above (Gatekeeper rejects an unsigned notarized DMG)
# plus a stored notarytool credential profile named in NOTARY_PROFILE. Create it once with:
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>
if [ -n "$NOTARY_PROFILE" ]; then
    echo "Notarizing ANC.dmg (this can take a few minutes) …"
    xcrun notarytool submit ANC.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple ANC.dmg
    xcrun stapler validate ANC.dmg   # confirms the DMG's own stapled ticket (the app was gated above)
fi
echo "Built ANC.dmg ($(du -h ANC.dmg | cut -f1))"
