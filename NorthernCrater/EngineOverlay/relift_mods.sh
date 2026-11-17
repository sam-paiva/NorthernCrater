#!/usr/bin/env bash
# Re-lifts the engine so the enabled mods' code patches run natively (not in the slow interpreter).
# usage: relift_mods.sh <build dir> <profile.xml>
# Takes the same lock as build_engine.sh: only one engine build at a time (exit code 75 = another is running).
set -euo pipefail

ENGINE="$1"; PROFILE="$2"
export PATH="$ENGINE/venv/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
[ -f "$ENGINE/src/tools/relift_mods_mac.sh" ] || { echo "the engine is not built yet: $ENGINE" >&2; exit 1; }

LOCK="$ENGINE/.build.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  other="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
    echo "another engine build is already running (pid $other); wait for it to finish" >&2
    exit 75
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

cd "$ENGINE/src"
bash tools/relift_mods_mac.sh "$PROFILE"
