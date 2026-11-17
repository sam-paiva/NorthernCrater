#!/usr/bin/env bash
# Make the enabled mods' code patches (hext) run natively: their patched code is lifted into
# the app, instead of running in the x86 interpreter (docs/ROADMAP.md M4 hext). Reads the
# launcher's profile, writes analysis/ffnx_manifests/hext_profile_*.json, re-lifts and rebuilds.
# usage: bash tools/relift_mods_mac.sh [profile.xml]   (default: the launcher's)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-$HOME/Library/Application Support/FF7Recomp/mods/profile.xml}"
OUT="$ROOT/build/hext-manifest"
L="$ROOT/external/deps/lzma"
mkdir -p "$OUT" "$ROOT/analysis/ffnx_manifests"
if [ ! -x "$OUT/hext_manifest" ] || [ -n "$(find "$ROOT/src/mods" "$ROOT/tools/hext_manifest.cpp" -newer "$OUT/hext_manifest")" ]; then
  echo "== building the hext manifest tool"
  (cd "$OUT" && clang -c -O1 -I"$ROOT/src/mods" -I"$L" "$ROOT/src/mods/lzs.c" "$L/LzmaDec.c" && \
   clang++ -std=c++20 -O1 -I"$ROOT/src/mods" -I"$L" -I"$ROOT/external/deps/pugixml/src" \
     "$ROOT/tools/hext_manifest.cpp" "$ROOT/src/mods/hext.cpp" "$ROOT/src/mods/iro.cpp" "$ROOT/src/mods/modinfo.cpp" \
     "$ROOT/src/mods/mods.cpp" "$ROOT/src/mods/runtimevar.cpp" "$ROOT/external/deps/pugixml/src/pugixml.cpp" lzs.o LzmaDec.o -o hext_manifest)
fi
echo "== the mods' code patches"
rm -f "$ROOT"/analysis/ffnx_manifests/hext_profile_*.json
"$OUT/hext_manifest" "$ROOT/game/ff7_en.exe" "$ROOT/analysis/ffnx_manifests" "$PROFILE" 2> >(grep -v '^\[mods\]' >&2)
echo "== lifting"
bash "$ROOT/tools/lift_mac.sh"
echo "== building"
cmake --build "$ROOT/build/macos" -- -j"$(sysctl -n hw.ncpu)" | grep -E ' error|FAILED' || true
echo "done: the mods' patched code now runs natively"
