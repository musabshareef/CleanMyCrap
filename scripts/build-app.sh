#!/bin/zsh
# Builds build/Clean My Crap.app. Pass --open to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Clean My Crap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CleanMyCrap "$APP/Contents/MacOS/CleanMyCrap"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Compile the Icon Composer icon (Resources/AppIcon.icon) into Assets.car + a legacy .icns.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target 26.0 --target-device mac \
  --output-partial-info-plist build/icon-partial.plist >/dev/null

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
[[ ${1:-} == --open ]] && open "$APP"
exit 0
