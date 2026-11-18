#!/bin/zsh
# Publishes the DMG that release.sh built: a GitHub release, plus a new entry in the Sparkle update feed
# (docs/appcast.xml, served by GitHub Pages). Run release.sh first, and test the DMG before you publish.
#
#   1. Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist
#   2. Write release-notes/<version>.md (a few "- " bullet lines; shown in the update window and on GitHub)
#   3. ./scripts/release.sh   → builds, notarizes, staples build/Clean-My-Crap-<version>.dmg
#   4. ./scripts/publish.sh   → this
#
# Needs: gh (logged in), and the Sparkle signing key in your login keychain (made once by generate_keys).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="musabshareef/CleanMyCrap"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" Resources/Info.plist)
DMG="build/Clean-My-Crap-$VERSION.dmg"
NOTES="release-notes/$VERSION.md"
TAG="v$VERSION"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

[[ -f $DMG ]] || { echo "No $DMG. Run ./scripts/release.sh first." >&2; exit 1; }
[[ -f $NOTES ]] || { echo "Write $NOTES first (a few '- ' bullet lines)." >&2; exit 1; }
[[ -x $SIGN_UPDATE ]] || swift package resolve
xcrun stapler validate -q "$DMG" || { echo "$DMG isn't notarized and stapled." >&2; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "$TAG is already published. Bump the version first." >&2; exit 1
fi
[[ -z $(git status --porcelain) ]] || { echo "Commit your changes first, so the release matches the code." >&2; exit 1; }

echo "› Signing the update"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE=$("$SIGN_UPDATE" "$DMG")

echo "› Adding $VERSION to docs/appcast.xml"
URL="https://github.com/$REPO/releases/download/$TAG/Clean-My-Crap-$VERSION.dmg"
python3 - "$VERSION" "$BUILD" "$MIN_OS" "$URL" "$SIGNATURE" "$NOTES" <<'PY'
import sys, html, email.utils, pathlib
version, build, min_os, url, signature, notes_path = sys.argv[1:]
paragraphs, bullets = [], []
for line in pathlib.Path(notes_path).read_text().splitlines():
    line = line.strip()
    if line.startswith(("- ", "* ")):
        bullets.append(f"<li>{html.escape(line[2:])}</li>")
    elif line:
        paragraphs.append(f"<p>{html.escape(line)}</p>")
body = "".join(paragraphs) + (f"<ul>{''.join(bullets)}</ul>" if bullets else "")
item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <description><![CDATA[{body}]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature}/>
    </item>
"""
feed = pathlib.Path("docs/appcast.xml")
text = feed.read_text()
marker = "<!-- releases: newest first -->\n"
assert marker in text, "docs/appcast.xml is missing its marker line"
feed.write_text(text.replace(marker, marker + item, 1))
PY

echo "› Publishing the GitHub release"
git push origin HEAD
# The same file under a fixed name, so the download page can always link to the latest one.
cp "$DMG" build/Clean-My-Crap.dmg
gh release create "$TAG" "$DMG" build/Clean-My-Crap.dmg --repo "$REPO" \
  --title "Clean My Crap $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"

# The feed goes live last, so the app never hears about an update before it can be downloaded.
echo "› Updating the feed"
git add docs/appcast.xml
git commit -q -m "Appcast: $VERSION"
git push origin HEAD
echo "Published $VERSION. Apps pick it up on their next check (GitHub Pages can take a minute)."
