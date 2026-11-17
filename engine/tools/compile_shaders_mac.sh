#!/usr/bin/env bash
# FFNx's shaders for bgfx's Metal renderer (tools/compile_shaders.sh for macOS):
# build/shaders-mtl/<shader>.<flat|smooth>.mtl.<frag|vert>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHADERC="$ROOT/external/bgfx/.build/osx-arm64/bin/shadercRelease"
[ -x "$SHADERC" ] || SHADERC="$ROOT/external/bgfx/.build/osx-x64/bin/shadercRelease"
SRC="$ROOT/external/FFNx/misc"
INC="$ROOT/build/shader_include"
mkdir -p "$INC/bgfx" && cp "$ROOT"/external/bgfx/src/bgfx_*.sh "$INC/bgfx/"
OUT="$ROOT/build/shaders-mtl"
mkdir -p "$OUT"
FLAGS=(--platform osx --profile metal)
SHADERS="FFNx FFNx.lighting FFNx.shadowmap FFNx.field.shadow FFNx.overlay FFNx.post FFNx.post.ntscj FFNx.blit FFNx.yuvmovie FFNx.yuvmovie.truecolor"
SKINNED="FFNx FFNx.lighting FFNx.shadowmap"
n=0
for s in $SHADERS; do
  for varying in flat smooth; do
    for stage in frag vert; do
      "$SHADERC" -i "$INC" -f "$SRC/$s.$stage" -o "$OUT/$s.$varying.mtl.$stage" \
        --type ${stage:0:1} --varyingdef "$SRC/FFNx.varying.$varying.def.sc" "${FLAGS[@]}" \
        || { echo "FAILED: $s.$varying.mtl.$stage"; exit 1; }
      n=$((n+1))
    done
  done
done
for s in $SKINNED; do
  "$SHADERC" -i "$INC" -f "$SRC/$s.vert" -o "$OUT/$s.skinned.smooth.mtl.vert" \
    --type v --varyingdef "$SRC/FFNx.varying.smooth.def.sc" --define SMOOTH_SKINNING "${FLAGS[@]}" \
    || { echo "FAILED: $s.skinned.smooth.mtl.vert"; exit 1; }
  n=$((n+1))
done
echo "$n shaders -> build/shaders-mtl"
