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

ICNS=build/AppIcon.icns
if [[ ! -f $ICNS || scripts/make-icon.swift -nt $ICNS ]]; then
  SET=build/AppIcon.iconset
  rm -rf $SET && mkdir -p $SET
  swift scripts/make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out $SET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $SET -o $ICNS
fi
cp $ICNS "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
[[ ${1:-} == --open ]] && open "$APP"
exit 0
