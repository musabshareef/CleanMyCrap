#!/bin/zsh
# Builds a Developer ID–signed, notarized, stapled DMG in build/.
#
# One-time setup (stores your notary credentials in the login keychain):
#   xcrun notarytool store-credentials notary \
#     --apple-id <your Apple ID> --team-id <team ID> --password <app-specific password>
#
# Env:
#   NOTARY_PROFILE   keychain profile name (default: notary — shared across all your apps)
#   SIGN_IDENTITY    defaults to the first "Developer ID Application" identity in the keychain
#   SKIP_NOTARIZE=1  sign and package only
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[[ -n $IDENTITY ]] || { echo "No Developer ID Application certificate found." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="build/Clean My Crap.app"
DMG="build/Clean-My-Crap-$VERSION.dmg"

echo "› Building and signing with: $IDENTITY"
SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh
codesign --verify --strict --deep "$APP"

if [[ ${SKIP_NOTARIZE:-} != 1 ]]; then
  # Staple the app itself, not just the DMG: once it's copied to /Applications the DMG's ticket
  # is gone, and without its own ticket a Mac that can't reach Apple's servers refuses to open it.
  echo "› Notarizing the app (usually a few minutes)"
  ZIP=$(mktemp -d)/app.zip
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

echo "› Packaging $DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Clean My Crap" -srcfolder "$STAGE" -fs APFS -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ ${SKIP_NOTARIZE:-} == 1 ]]; then
  echo "Signed (not notarized): $DMG"
  exit 0
fi

echo "› Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Ready to ship: $DMG"
