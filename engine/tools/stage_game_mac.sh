#!/usr/bin/env bash
# Make the game folder the macOS app runs from (src/mac/ff7_mac_main.mm):
#   ~/Library/Application Support/FF7Recomp/game/
#     ff7_en.exe      the player's exe (game/ff7_en.exe, from tools/import_game.py)
#     data -> ...     the install's ff7/workingdir/data (a link, not a copy)
#     FFNx*.toml      FFNx's settings and data tables
#     shaders/        Metal shaders (tools/compile_shaders_mac.sh)
#     save/           the game's saves
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${FF7_GAME_DIR:-$HOME/Library/Application Support/FF7Recomp/game}"
MISC="$ROOT/external/FFNx/misc"
mkdir -p "$DEST/shaders" "$DEST/save"
cp "$ROOT/game/ff7_en.exe" "$DEST/ff7_en.exe"
data="$(cd "$ROOT/game/data" && pwd -P)"
[ -L "$DEST/data" ] || ln -s "$data" "$DEST/data"
cp "$MISC"/FFNx.*.toml "$DEST/"
cp "$ROOT"/build/shaders-mtl/* "$DEST/shaders/"
cp "$MISC"/glut_*.png "$DEST/shaders/"   # NTSC-J colour LUTs (enable_ntscj_gamut_mode)
# FFNx's defaults: the launcher writes FFNx.toml from this with its settings at each Play
cp "$MISC/FFNx.toml" "$DEST/FFNx.template.toml"
[ -f "$DEST/FFNx.toml" ] || cp "$MISC/FFNx.toml" "$DEST/FFNx.toml"
echo "game folder: $DEST"
