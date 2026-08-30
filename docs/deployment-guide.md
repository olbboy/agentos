# AgeOS — Deployment Guide

## Local install (dev)
```bash
swift build -c release
mkdir -p ~/.ageos/bin && cp .build/release/ageos .build/release/ageos-mcp ~/.ageos/bin/
export PATH="$HOME/.ageos/bin:$PATH"        # add this to your shell rc
./scripts/generate-completions.sh            # zsh/bash/fish completions
```
The app: `cd apps/AgeOS && xcodegen generate && xcodebuild -scheme AgeOS -configuration Release build`
puts the `.app` in DerivedData — or use the release lane below.

## Test
```bash
swift test                                       # 69 tests, never touches your real $HOME
cd apps/AgeOS && xcodebuild -scheme AgeOS test   # app tests; see the TCC note below
```

The app has 24 swift-testing tests plus 3 XCTest, and three UI tests.

After changing any user-facing string in the app, sync the String Catalog:
```bash
./scripts/sync-string-catalog.sh
```
Xcode merges extracted strings into `Localizable.xcstrings` on every IDE build.
`xcodebuild` does not — it only writes `.stringsdata`, so without this step the
catalog drifts with no error and no warning.

### TCC bootstrap (once, persistent — needed to run tests from an agent harness)
1. **Developer Tools** for whichever app owns the process calling xcodebuild
   (Claude Code desktop = `/Applications/Claude.app`; a terminal = Terminal.app).
   Without it AgeOSTests hangs for 120s and then times out —
   `kTCCServiceDeveloperTool` denies silently, with no prompt. Open the right
   pane with:
   `open "x-apple.systempreferences:com.apple.preference.security?Privacy_DeveloperTool"`
2. **Accessibility** — a second, separate gate, and the one the UI tests need.
   Without it the test runner fails to initialize with "Timed out while enabling
   automation mode", and every UI test fails in a way that looks like a broken
   app rather than a missing grant.

## CI (GitHub Actions)
- `ci.yml`: push and PR → `swift build && swift test` plus an app build (macOS 26
  image; if GitHub does not offer one yet, move `runs-on` to the newest image
  with Xcode 26 and keep the app job out of the required checks).
- `release.yml`: a `v*` tag → runs the release lane and uploads artifacts and
  checksums to the GitHub Release.

## Release lane (`scripts/release-lane.sh`)
1. `swift build -c release` → tarball `ageos-cli-<ver>-arm64.tar.gz` (ageos,
   ageos-mcp, completions).
2. `xcodebuild -scheme AgeOS -configuration Release` → `AgeOS.app` → zip.
3. **Sign and notarize ONLY when the environment provides it**:
   `AGEOS_SIGN_IDENTITY` (Developer ID Application) and `AGEOS_NOTARY_PROFILE`
   (a notarytool keychain profile). Without them the release ships **unsigned**
   with instructions:
   ```bash
   xattr -dr com.apple.quarantine AgeOS.app   # or the ageos binary
   ```
4. SHA-256 checksums for every artifact.

A Sparkle appcast is deferred until there is a Developer ID, since Sparkle
requires signing. It did not block v0.1.0.

## Homebrew cask
The cask lives at `packaging/homebrew/ageos.rb` and is published to
`olbboy/homebrew-tap`. Learned from a real install on 2026-08-30 (Homebrew 2026
on macOS 26):
```bash
brew trust olbboy/tap        # REQUIRED: third-party taps must be trusted first
brew tap olbboy/tap
brew install --cask ageos    # Homebrew removed the --no-quarantine flag
# if Gatekeeper blocks it on open (macOS 26 dropped xattr -r):
find /Applications/AgeOS.app -exec xattr -d com.apple.quarantine {} \; 2>/dev/null
```

## Release state

v0.1.0 is published: tag `v0.1.0`, a GitHub release, and a cask carrying its
sha256. The bundle id is `io.github.olbboy.ageos`.

What is done: bundle id settled, repository public, tap repository created and
the cask pushed, `v0.1.0` tagged and released.

What remains, and is a decision rather than a task: an Apple Developer ID
($99/year) would let the lane sign and notarize, which in turn unblocks Sparkle
updates. Until then the build ships unsigned and users strip quarantine by hand.

### Cutting the next release
1. Bump `MARKETING_VERSION` in `apps/AgeOS/project.yml` and `version` in
   `packaging/homebrew/ageos.rb`.
2. `swift test` and the app tests green; sync the String Catalog if any string
   changed.
3. Tag `vX.Y.Z` and push the tag — `release.yml` runs the lane from there.
4. Update the cask sha256 from the released zip, and push the tap.
