#!/usr/bin/env bash
# build_mac.sh - FF7Recomp for macOS from a fresh clone, in one command, from YOUR OWN copy of
# FINAL FANTASY VII (the Steam release). Nothing derived from the game leaves this Mac: the
# game's code is translated and compiled here, into build/macos/NorthernCrater Engine.app.
#
# usage: bash tools/build_mac.sh "/path/to/FINAL FANTASY VII Steam Edition"
#
# Needs: macOS 13+, Xcode or the Command Line Tools (xcode-select --install), cmake and ninja
# (brew install cmake ninja), Python 3 with capstone (python3 -m pip install --user capstone).
# Takes about 15-30 minutes the first time; re-running carries on where it stopped.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Spaces in the folder's path (an external drive called "My Drive") break the compiler flags and
# FFmpeg's configure: build through a link without them, ~/.northerncrater-engine, kept for later re-lifts
case "$ROOT" in *" "*)
  [ -n "${GJM_VIA_LINK:-}" ] && { echo "the folder still has a space in its path: $ROOT" >&2; exit 1; }
  LINK="$HOME/.gjmateria"
  case "$LINK" in *" "*) echo "move this folder to a path without spaces" >&2; exit 1 ;; esac
  ln -sfn "$ROOT" "$LINK"
  if [ -f "$ROOT/build/macos/CMakeCache.txt" ] && grep -q "CMAKE_HOME_DIRECTORY:INTERNAL=$ROOT/macos" "$ROOT/build/macos/CMakeCache.txt"; then
    rm -rf "${ROOT:?}/build/macos"   # configured through the spaced path before
  fi
  echo "building through $LINK (no spaces) -> $ROOT"
  GJM_VIA_LINK=1 exec bash "$LINK/tools/build_mac.sh" "$@" ;;
esac
cd "$ROOT"
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

GAME="${1:-}"
guide() {
  cat >&2 <<'TXT'
FINAL FANTASY VII (Steam) was not found on this Mac. Get your own copy's files first:
  a. On a Windows PC: Steam > right-click the game > Manage > Browse local files, and copy the
     "FINAL FANTASY VII Steam Edition" folder to this Mac (Downloads, or an external drive).
  b. On this Mac with CrossOver or Whisky: install Windows Steam in a bottle, then FF7.
  c. On this Mac with steamcmd (Valve's tool; it asks your password and Steam Guard code):
       mkdir -p ~/steamcmd && cd ~/steamcmd
       curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz" | tar zxf -
       ./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir ~/FF7 +login YOUR_STEAM_LOGIN +app_update 3837340 validate +quit
Then run this again (or pass the folder: bash tools/build_mac.sh "/path/to/FINAL FANTASY VII Steam Edition").
TXT
  exit 1
}
# No folder given: look where FF7's Steam folder usually is (as the launcher's search does).
find_game() {
  local c
  for c in "$HOME/Library/Application Support/Steam/steamapps/common"/FINAL\ FANTASY\ VII* \
           "$HOME/Library/Application Support/CrossOver/Bottles"/*/drive_c/Program\ Files*/Steam/steamapps/common/FINAL\ FANTASY\ VII* \
           "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"/*/drive_c/Program\ Files*/Steam/steamapps/common/FINAL\ FANTASY\ VII* \
           "$HOME/FF7" "$HOME"/{Downloads,Desktop,Documents,Games}/FINAL\ FANTASY\ VII* /Volumes/*/FINAL\ FANTASY\ VII* /Volumes/*/*/FINAL\ FANTASY\ VII*; do
    [ -f "$c/ff7/resources/ff7_1.02/ff7_en" ] && [ -d "$c/ff7/workingdir/data" ] && { echo "$c"; return; }
  done
  c=$(mdfind "kMDItemFSName == 'ff7_en'" 2>/dev/null | grep '/ff7/resources/ff7_1.02/ff7_en$' | head -1)
  [ -n "$c" ] && echo "${c%/ff7/resources/ff7_1.02/ff7_en}"
}
if [ -z "$GAME" ] && [ ! -f game/ff7_en.exe ]; then
  GAME="$(find_game || true)"
  [ -n "$GAME" ] || guide
  echo "found FINAL FANTASY VII: $GAME"
fi

# Apple silicon builds native arm64 (the game's memory at an offset); Intel builds x86_64.
# FF7_ARCH=x86_64 forces the Intel build (Rosetta 2 on Apple silicon). sysctl, not uname: a shell
# running under Rosetta reports x86_64.
ARCH="${FF7_ARCH:-$([ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && echo arm64 || echo x86_64)}"
FFMPEG_DIR="build/ffmpeg-mac$([ "$ARCH" = arm64 ] && echo -arm64 || true)"

step "1/8 checking the tools"
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools are missing: run  xcode-select --install"
command -v cmake >/dev/null || die "cmake is missing: brew install cmake"
command -v ninja >/dev/null || die "ninja is missing: brew install ninja"
command -v python3 >/dev/null || die "python3 is missing"
python3 -c 'import capstone' 2>/dev/null || die "Python's capstone is missing: python3 -m pip install --user capstone"
[ "$ARCH" = x86_64 ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && { arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta 2 is missing: softwareupdate --install-rosetta --agree-to-license"; }
echo "ok (building for $ARCH)"

step "2/8 toolkits and libraries (pinned, patched)"
bash tools/fetch_deps_mac.sh | tail -1        # first: setup's FFNx edits touch a library header too
# The stamp holds a hash of everything setup applies, so a changed edit script or patch re-runs it
# (a bare "done" file once hid a fix from every engine that was already built).
SETUP_HASH="$(cat tools/setup_mac.sh tools/ffnx_*.py tools/ffnx_offset_edits.json patches/pcrecomp/* patches/ffnx/* patches/bgfx/* 2>/dev/null | shasum | cut -d' ' -f1)"
if [ -d external/FFNx/.git ] && [ "$(cat external/.setup-mac-done 2>/dev/null)" = "$SETUP_HASH" ]; then :; else
  bash tools/setup_mac.sh; echo "$SETUP_HASH" > external/.setup-mac-done
fi

step "3/8 your game files"
if [ -n "$GAME" ]; then python3 -I tools/import_game.py "$GAME"; fi
python3 -I tools/check_inputs.py | tail -1

step "4/8 translating the game's code (the lift)"
[ -f generated/recomp/recomp_dispatch.c ] || bash tools/lift_mac.sh

step "5/8 FFmpeg (movies)"
[ -f "$FFMPEG_DIR/lib/libavcodec.a" ] || FF7_ARCH=$ARCH bash tools/build_ffmpeg_mac.sh | tail -1

step "6/8 shaders (bgfx shaderc, Metal)"
if [ ! -x external/bgfx/.build/osx-arm64/bin/shadercRelease ] && [ ! -x external/bgfx/.build/osx-x64/bin/shadercRelease ]; then
  (cd external/bgfx && xattr -d com.apple.quarantine ../bx/tools/bin/darwin/genie 2>/dev/null || true
   HOSTARCH=$([ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && echo osx-arm64 || echo osx-x64)   # an Intel Mac builds x64
   ../bx/tools/bin/darwin/genie --with-tools --gcc=$HOSTARCH gmake >/dev/null
   make -C .build/projects/gmake-$HOSTARCH config=release shaderc -j"$(sysctl -n hw.ncpu)" >/dev/null)
fi
[ -f build/shaders-mtl/FFNx.flat.mtl.frag ] || bash tools/compile_shaders_mac.sh | tail -1

step "7/8 compiling the app (the first time takes a while)"
# a folder built for the other architecture starts over (its libraries are the wrong kind)
if [ -f build/macos/CMakeCache.txt ] && ! grep -q "^FF7_ARCH:STRING=$ARCH$" build/macos/CMakeCache.txt; then
  rm -rf "${ROOT:?}/build/macos"
fi
cmake -S "$ROOT/macos" -B "$ROOT/build/macos" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DFF7_ARCH="$ARCH" >/dev/null
cmake --build "$ROOT/build/macos" -- -j"$(sysctl -n hw.ncpu)" | grep -E ' error|FAILED' && die "the build failed (see above)" || true
[ -x "build/macos/NorthernCrater Engine.app/Contents/MacOS/NorthernCrater Engine" ] || die "the build failed"

step "8/8 done"
echo "App: $ROOT/build/macos/NorthernCrater Engine.app"
echo "It has no launcher of its own: NorthernCrater starts it (FF7_GAME_DIR, FF7_HOME, FF7_QUICKBOOT; see engine/NOTICE.md)."
echo "Run it with:  open \"$ROOT/build/macos/NorthernCrater Engine.app\""
echo "(Keep this folder: it is used to re-lift mods.)"
