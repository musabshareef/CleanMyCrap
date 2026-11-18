#!/bin/zsh
# Builds build/Clean My Crap.app (universal: Apple silicon + Intel).
#   --open           launch it afterwards
#   SIGN_IDENTITY    codesign identity; defaults to ad-hoc ("-") for local builds
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BINDIR="$(swift build -c release $ARCHS --show-bin-path)"

APP="build/Clean My Crap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" "$APP/Contents/Frameworks"
cp "$BINDIR/CleanMyCrap" "$APP/Contents/MacOS/CleanMyCrap"
# The `crap` command-line tool rides along; the app's menu links it into /usr/local/bin.
cp "$BINDIR/crap" "$APP/Contents/Helpers/crap"
# Sparkle (in-app updates). ditto keeps the framework's internal symlinks intact.
ditto "$BINDIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Compile the Icon Composer icon (Resources/AppIcon.icon) into Assets.car + a legacy .icns.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target 26.0 --target-device mac \
  --output-partial-info-plist build/icon-partial.plist >/dev/null

IDENTITY="${SIGN_IDENTITY:--}"
# Sign inside-out: nested code first, then the bundle that seals it.
# Hardened runtime + secure timestamp are required for notarization (skipped for ad-hoc local builds).
if [[ $IDENTITY == - ]]; then FLAGS=(--force --sign -); else FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY"); fi
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sparkle's own order (https://sparkle-project.org/documentation/sandboxing/#code-signing).
codesign $FLAGS "$SP/XPCServices/Installer.xpc"
codesign $FLAGS --preserve-metadata=entitlements "$SP/XPCServices/Downloader.xpc"
codesign $FLAGS "$SP/Autoupdate"
codesign $FLAGS "$SP/Updater.app"
codesign $FLAGS "$APP/Contents/Frameworks/Sparkle.framework"
codesign $FLAGS --identifier com.cleanmycrap.crap "$APP/Contents/Helpers/crap"
codesign $FLAGS "$APP"
echo "Built $APP"
[[ ${1:-} == --open ]] && open "$APP"
exit 0
