#!/bin/sh
# Package ANC.app into ANC.dmg with the usual drag-to-Applications layout.
set -e
cd "$(dirname "$0")"
./build-app.sh
STAGE=$(mktemp -d)
cp -R ANC.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag ANC.app onto this
rm -f ANC.dmg
hdiutil create -volname "ANC" -srcfolder "$STAGE" -ov -format UDZO -quiet ANC.dmg
rm -rf "$STAGE"
# ponytail: unsigned/un-notarized — recipients must right-click > Open once.
# To sign for real distribution, before hdiutil:
#   codesign --deep --options runtime -s "Developer ID Application: NAME (TEAMID)" ANC.app
#   (then notarize ANC.dmg with: xcrun notarytool submit … && xcrun stapler staple ANC.dmg)
echo "Built ANC.dmg ($(du -h ANC.dmg | cut -f1))"
