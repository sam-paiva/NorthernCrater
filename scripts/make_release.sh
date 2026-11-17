#!/usr/bin/env bash
# Builds a downloadable NorthernCrater: a clean arm64 Release, signed locally (ad-hoc), packed as a .dmg and a
# .zip with SHA-256 checksums, in dist/.  usage: scripts/make_release.sh [version]
#
# The app contains the engine SOURCES only. The engine is built on each user's Mac from their own game files
# (it contains game-derived code and must never be shipped).
#
# Signing: ad-hoc, so there is no Apple developer identity in the build. macOS will warn on first open
# (see README, "Opening it the first time"). A Developer ID signature and notarization would remove the warning
# but need a paid Apple Developer account in your name.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' NorthernCrater.xcodeproj/project.pbxproj | head -1)}"
NAME="NorthernCrater-${VERSION}-arm64"
DIST="dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== Building NorthernCrater ${VERSION} (Release, arm64)"
xcodebuild -project NorthernCrater.xcodeproj -scheme NorthernCrater -configuration Release \
  -derivedDataPath "$WORK/dd" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="$WORK/dd/Build/Products/Release/NorthernCrater.app"
[ -d "$APP" ] || { echo "the build produced no app" >&2; exit 1; }

echo "== Checking the app"
[ "$(lipo -archs "$APP/Contents/MacOS/NorthernCrater")" = "arm64" ] || { echo "not arm64-only" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
BUNDLE_ID="$(defaults read "$APP/Contents/Info" CFBundleIdentifier)"
echo "   bundle id: $BUNDLE_ID | $(codesign -dv "$APP" 2>&1 | grep -E 'Signature|TeamIdentifier' | tr '\n' ' ')"
# no developer identity may be inside the app
SIGNATURE="$(codesign -dv "$APP" 2>&1)"      # (captured first: grep -q closing a pipe would trip pipefail)
grep -q "TeamIdentifier=not set" <<<"$SIGNATURE" || { echo "the app carries a developer team identifier" >&2; exit 1; }

echo "== Packing into ${DIST}/"
mkdir -p "$DIST"
rm -f "$DIST/${NAME}.dmg" "$DIST/${NAME}.zip" "$DIST/${NAME}.sha256"
STAGE="$WORK/stage"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NorthernCrater ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DIST/${NAME}.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/${NAME}.zip"
( cd "$DIST" && shasum -a 256 "${NAME}.dmg" "${NAME}.zip" > "${NAME}.sha256" )

echo "== Done"
ls -lh "$DIST/${NAME}".* | awk '{print "   " $5 "  " $9}'
cat "$DIST/${NAME}.sha256" | sed 's/^/   /'
