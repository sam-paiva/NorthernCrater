#!/usr/bin/env bash
# Builds a downloadable NorthernCrater: a clean arm64 Release, signed locally (ad-hoc), packed as a .dmg and a
# .zip with SHA-256 checksums, in dist/.
#
#   usage: scripts/make_release.sh [version] [--publish]
#
#   --publish   also create the GitHub release with the three files and notes (needs the GitHub CLI:
#               brew install gh, then gh auth login; push your commits first). The GitHub Action in
#               .github/workflows/release.yml runs exactly this when you push a tag like v1.0.
#   DRY_RUN=1   with --publish: print what would be published instead of publishing.
#
# The app contains the engine SOURCES only. The engine is built on each user's Mac from their own game files
# (it contains game-derived code and must never be shipped).
#
# Signing: ad-hoc, so there is no Apple developer identity in the build. macOS will warn on first open
# (see README, "Opening it the first time"). A Developer ID signature and notarization would remove the warning
# but need a paid Apple Developer account in your name.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=""; PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) VERSION="$arg" ;;
  esac
done
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' NorthernCrater.xcodeproj/project.pbxproj | head -1)}"
VERSION="${VERSION#v}"                      # a tag like v1.0 gives 1.0
NAME="NorthernCrater-${VERSION}-arm64"
DIST="dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== Building NorthernCrater ${VERSION} (Release, arm64)"
xcodebuild -project NorthernCrater.xcodeproj -scheme NorthernCrater -configuration Release \
  -derivedDataPath "$WORK/dd" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- \
  MARKETING_VERSION="$VERSION" build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="$WORK/dd/Build/Products/Release/NorthernCrater.app"
[ -d "$APP" ] || { echo "the build produced no app" >&2; exit 1; }

echo "== Checking the app"
[ "$(lipo -archs "$APP/Contents/MacOS/NorthernCrater")" = "arm64" ] || { echo "not arm64-only" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
BUNDLE_ID="$(defaults read "$APP/Contents/Info" CFBundleIdentifier)"
APP_VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
[ "$APP_VERSION" = "$VERSION" ] || { echo "the app says version $APP_VERSION, expected $VERSION" >&2; exit 1; }
SIGNATURE="$(codesign -dv "$APP" 2>&1)"      # (captured first: grep -q closing a pipe would trip pipefail)
echo "   bundle id: $BUNDLE_ID | version $APP_VERSION | $(grep -E 'Signature|TeamIdentifier' <<<"$SIGNATURE" | tr '\n' ' ')"
# no developer identity may be inside the app
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
sed 's/^/   /' "$DIST/${NAME}.sha256"

if [ "$PUBLISH" = 1 ]; then
  echo "== Publishing the GitHub release v${VERSION}"
  NOTES="$WORK/notes.md"
  sed "s/{{VERSION}}/${VERSION}/g" .github/release-notes.md > "$NOTES"
  { echo; echo "SHA-256:"; echo '```'; cat "$DIST/${NAME}.sha256"; echo '```'; } >> "$NOTES"
  CMD=(gh release create "v${VERSION}" "$DIST/${NAME}.dmg" "$DIST/${NAME}.zip" "$DIST/${NAME}.sha256"
       --title "NorthernCrater ${VERSION}" --notes-file "$NOTES")
  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '   would run:'; printf ' %q' "${CMD[@]}"; echo; echo "   --- release notes ---"; sed 's/^/   /' "$NOTES"
  else
    command -v gh >/dev/null || { echo "install the GitHub CLI first: brew install gh, then gh auth login" >&2; exit 1; }
    "${CMD[@]}"
  fi
fi
