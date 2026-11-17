#!/usr/bin/env bash
# Builds the native macOS FF7 engine from the sources in this app's engine/ folder (a copy of
# GJ Materia's engine, GPL-3.0: see engine/NOTICE.md) and the player's own copy of the game.
# Driven by RecompilationService; safe to re-run (finished steps are skipped).
#
# usage: build_engine.sh <engine sources> <build dir (no spaces in the path)> <FINAL FANTASY VII Steam Edition folder> <game dir>
# result: <build dir>/src/build/macos/NorthernCrater Engine.app and a staged game folder at <game dir>
set -euo pipefail

SOURCES="$1"; ENGINE="$2"; STEAM="$3"; GAME="$4"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

say() { printf '▶ %s\n' "$*"; }
case "$ENGINE" in *" "*) echo "the build folder's path must not contain spaces: $ENGINE" >&2; exit 1 ;; esac
[ -f "$SOURCES/tools/build_mac.sh" ] || { echo "engine sources not found at: $SOURCES" >&2; exit 1; }
mkdir -p "$ENGINE"

# One build at a time per build folder: two at once corrupt the git checkouts and the build tree.
LOCK="$ENGINE/.build.lock"
acquire_lock() {
  if mkdir "$LOCK" 2>/dev/null; then echo $$ > "$LOCK/pid"; return 0; fi
  local other; other="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
    echo "another engine build is already running (pid $other); wait for it to finish" >&2
    exit 75
  fi
  rm -rf "$LOCK"   # left behind by a build that was killed
  mkdir "$LOCK" && echo $$ > "$LOCK/pid"
}
acquire_lock
trap 'rm -rf "$LOCK"' EXIT

# 1. The sources go to a path without spaces (their scripts need that). rsync copies only what changed,
#    so unchanged files keep their timestamps and the build stays incremental; the build's own folders
#    (downloaded toolkits, the lift, the compiled app) are kept.
SRC="$ENGINE/src"
say "Syncing the engine sources"
mkdir -p "$SRC"
rsync -a --delete \
  --exclude '/external/' --exclude '/generated/' --exclude '/build/' --exclude '/game/' --exclude '/analysis/' \
  --exclude '/.git/' --exclude '/.prepared' \
  "$SOURCES/" "$SRC/"
mkdir -p "$SRC/game"

# 2. Python tools for the lift live in a private virtual environment (nothing is installed system-wide)
say "Preparing the lifter's Python environment"
[ -x "$ENGINE/venv/bin/python" ] || python3 -m venv "$ENGINE/venv"
"$ENGINE/venv/bin/python" -c 'import capstone, pefile' 2>/dev/null || "$ENGINE/venv/bin/pip" install -q capstone pefile
export PATH="$ENGINE/venv/bin:$PATH"

# 3. GJ Materia's own build: sources -> lift -> FFmpeg -> shaders -> app (15-30 minutes the first time)
say "Building the engine (the first time takes 15-30 minutes: lift, FFmpeg, shaders, compile)"
cd "$SRC"
bash tools/build_mac.sh "$STEAM"

# 4. The game folder the engine runs from: the exe, a link to the game data, FFNx settings, shaders
rm -f "$ENGINE/.relifted-mods"   # the build lifts without the mods' patches: the next Play re-lifts for them
say "Staging the game folder"
FF7_GAME_DIR="$GAME" bash tools/stage_game_mac.sh

APP="$SRC/build/macos/NorthernCrater Engine.app"
[ -x "$APP/Contents/MacOS/NorthernCrater Engine" ] || { echo "the engine app was not produced" >&2; exit 1; }
# The app's post-build step copies its shaders and config into the bundle: a build that skipped it looks fine but cannot run.
[ -n "$(ls "$APP/Contents/Resources/ffnx/shaders" 2>/dev/null)" ] || { echo "the engine app has no shaders in its bundle (its post-build step failed)" >&2; exit 1; }
say "Engine ready: $APP"
