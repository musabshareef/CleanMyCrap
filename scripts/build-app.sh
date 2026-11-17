#!/bin/zsh
# Builds build/Clean My Crap.app (universal: Apple silicon + Intel).
#   --open           launch it afterwards
#   SIGN_IDENTITY    codesign identity; defaults to ad-hoc ("-") for local builds
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/CleanMyCrap"

APP="build/Clean My Crap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CleanMyCrap"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Compile the Icon Composer icon (Resources/AppIcon.icon) into Assets.car + a legacy .icns.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target 26.0 --target-device mac \
  --output-partial-info-plist build/icon-partial.plist >/dev/null

IDENTITY="${SIGN_IDENTITY:--}"
if [[ $IDENTITY == - ]]; then
  codesign --force --sign - "$APP" >/dev/null
else
  # Hardened runtime + secure timestamp are required for notarization.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Built $APP"
[[ ${1:-} == --open ]] && open "$APP"
exit 0
