#!/bin/sh
# Package ANC.app into a polished ANC.dmg: background image, sized window,
# hidden toolbar, and app + Applications icons positioned for drag-to-install.
#
# Env (all optional):
#   SIGN_ID              Developer ID Application identity → code sign the bundle
#   NOTARY_PROFILE       stored notarytool profile → notarize + staple app and DMG
#   ALLOW_UNSTYLED_DMG   set to ship even if the Finder layout step didn't record
set -e
cd "$(dirname "$0")"

command -v swiftc >/dev/null || { echo "missing tool: swiftc — install the Xcode Command Line Tools"; exit 1; }
[ -n "$SIGN_ID" ] && ! command -v codesign >/dev/null && { echo "SIGN_ID set but codesign not found"; exit 1; }
[ -n "$NOTARY_PROFILE" ] && ! command -v xcrun >/dev/null && { echo "NOTARY_PROFILE set but xcrun not found"; exit 1; }

MNT=""; TMPDMG=""; ZIP=""
cleanup() {
    [ -n "$MNT" ] && [ -d "$MNT" ] && hdiutil detach "$MNT" -force -quiet 2>/dev/null || true
    [ -n "$TMPDMG" ] && rm -f "$TMPDMG"
    [ -n "$ZIP" ] && rm -f "$ZIP"
}
trap cleanup EXIT

./build-app.sh

# Background image: regenerate when its generator is newer (or it's missing).
if [ ! -f dmg-bg.png ] || [ dmgbg.swift -nt dmg-bg.png ]; then
    TMPBIN=$(mktemp -d); swiftc -O dmgbg.swift -o "$TMPBIN/mkbg" && "$TMPBIN/mkbg" dmg-bg.png; rm -rf "$TMPBIN"
fi

# Sign nested binaries first, then the bundle, all with the hardened runtime (notarization requires it).
if [ -n "$SIGN_ID" ]; then
    echo "Signing with: $SIGN_ID"
    codesign --force --options runtime --timestamp -s "$SIGN_ID" ANC.app/Contents/MacOS/anc
    codesign --force --options runtime --timestamp -s "$SIGN_ID" ANC.app/Contents/MacOS/ancbar
    codesign --force --options runtime --timestamp -s "$SIGN_ID" ANC.app
    codesign --verify --strict --verbose=2 ANC.app
fi

# Notarize + staple the APP itself (via a zip) before packaging, so it carries its own ticket and
# opens offline once dragged out of the DMG. The DMG is notarized separately below.
if [ -n "$NOTARY_PROFILE" ]; then
    echo "Notarizing ANC.app …"
    ZIP=$(mktemp -u).zip
    ditto -c -k --keepParent ANC.app "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP"; ZIP=""
    xcrun stapler staple ANC.app
    spctl -a -vvv --type exec ANC.app   # Gatekeeper gate: must print "accepted / Notarized Developer ID"
fi

VOL="ANC"
TMPDMG=$(mktemp -u).dmg
rm -f ANC.dmg

# The Finder layout step addresses the volume by name ("disk ANC"), so it must live at /Volumes/ANC.
# Never force-unmount a pre-existing volume of that name — it could be the user's real data — abort instead.
if [ -e "/Volumes/$VOL" ]; then
    echo "A volume named '$VOL' is already mounted at /Volumes/$VOL. Unmount it and retry."; exit 1
fi
hdiutil create -volname "$VOL" -size 20m -fs HFS+ -ov -quiet "$TMPDMG"
hdiutil attach "$TMPDMG" -noautoopen -quiet
MNT="/Volumes/$VOL"
[ -d "$MNT" ] || { echo "expected volume at $MNT not found after attach; aborting"; exit 1; }
cp -R ANC.app "$MNT/"
ln -s /Applications "$MNT/Applications"
mkdir "$MNT/.background"
cp dmg-bg.png "$MNT/.background/bg.png"

# Finder layout — needs a GUI login session with Automation permission for Finder.
osascript <<'APPLESCRIPT' || echo "warning: Finder layout step failed (grant Automation access to Finder)"
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

# Gate: refuse to ship an unstyled DMG unless explicitly allowed (a 0-exit unstyled artifact is worse
# than a failed build). .DS_Store existence means Finder recorded the layout.
if [ ! -f "$MNT/.DS_Store" ]; then
    [ -n "$ALLOW_UNSTYLED_DMG" ] && echo "warning: shipping unstyled DMG (ALLOW_UNSTYLED_DMG set)" \
        || { echo "DMG layout was not recorded. Fix Finder Automation permission, or set ALLOW_UNSTYLED_DMG=1 to ship anyway."; exit 1; }
fi

sync
hdiutil detach "$MNT" -quiet; MNT=""
hdiutil convert "$TMPDMG" -format UDZO -o ANC.dmg -ov -quiet
rm -f "$TMPDMG"; TMPDMG=""

# Sign the DMG container too (belt-and-suspenders; the app inside is already signed).
[ -n "$SIGN_ID" ] && codesign --force --timestamp -s "$SIGN_ID" ANC.dmg

if [ -n "$NOTARY_PROFILE" ]; then
    echo "Notarizing ANC.dmg (this can take a few minutes) …"
    xcrun notarytool submit ANC.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple ANC.dmg
    xcrun stapler validate ANC.dmg   # confirms the DMG's own stapled ticket (the app was gated above)
fi
echo "Built ANC.dmg ($(du -h ANC.dmg | cut -f1))"
