# Clean My Crap

Your Mac is full of crap. Let's find it, sort it, and flush it.

A free Mac cleaner with a sense of humor. It sorts what it finds by risk (Definitely Crap, Probably Crap, Might Be Treasure), only preselects the safe stuff, and never deletes anything until you say so.

**[Download for Mac](https://musabshareef.github.io/CleanMyCrap/)** · macOS 26 or later · Apple silicon and Intel · signed and notarized · updates itself

## What it does

- **Crap:** caches, logs, Xcode and simulator leftovers, Docker, `node_modules` and other build junk, package caches, old installers, screenshots, forgotten downloads, iPhone backups, AI models and more
- **Evict an App:** drop an app on the window (or the Dock icon) and it goes to the Trash along with everything it scattered around your Mac
- **Apps You Forgot You Had:** apps you haven't opened in six months
- **Ghosts of Apps Past:** leftovers of apps you already deleted
- **`crap`:** the same engine on the command line, with `--json` for scripts and AI agents

## Command line

Install it from **Clean My Crap → Install Command Line Tool…**, then run `crap --help`.

```bash
crap scan --items          # every item, with an ID
crap flush --safe          # dry run; add --yes to do it
crap evict Blender --yes   # app + leftovers → Trash
```

Nothing is removed without `--yes`, and High Risk items also need `--include-high-risk`.

## Feedback

**Help → Send Feedback…** in the app, or [open an issue](https://github.com/musabshareef/CleanMyCrap/issues/new).

## Building

```bash
./scripts/build-app.sh --open    # build/Clean My Crap.app (ad-hoc signed)
swift run crap scan              # the CLI, straight from source
```

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`
2. Write `release-notes/<version>.md`
3. `./scripts/release.sh`: builds, signs with Developer ID, notarizes and staples the DMG
4. Test the DMG, then `./scripts/publish.sh`: GitHub release + Sparkle update feed (`docs/appcast.xml`)

Updates are signed with an EdDSA key kept in the release machine's keychain (Sparkle's `generate_keys`). Back it up: losing it means existing installs can't be updated.
