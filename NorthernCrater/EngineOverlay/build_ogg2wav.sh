#!/usr/bin/env bash
# Builds the ogg2wav helper (Ogg Vorbis -> WAV, for mod sound previews) from the libogg/libvorbis sources the
# engine build downloaded. usage: build_ogg2wav.sh <ogg2wav.c> <build dir>   -> <build dir>/bin/ogg2wav
set -euo pipefail
SRC="$1"; ENGINE="$2"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
DEPS="$ENGINE/src/external/deps"
OUT="$ENGINE/bin/ogg2wav"
[ -f "$DEPS/vorbis/lib/vorbisfile.c" ] && [ -f "$DEPS/ogg/src/bitwise.c" ] || { echo "the engine has not been built yet (no libvorbis sources)" >&2; exit 1; }
[ -x "$OUT" ] && [ "$OUT" -nt "$SRC" ] && exit 0
mkdir -p "$ENGINE/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/inc/ogg"
cat > "$T/inc/ogg/config_types.h" <<'H'
#ifndef OGG_CONFIG_TYPES_H
#define OGG_CONFIG_TYPES_H
#include <stdint.h>
typedef int16_t ogg_int16_t; typedef uint16_t ogg_uint16_t; typedef int32_t ogg_int32_t;
typedef uint32_t ogg_uint32_t; typedef int64_t ogg_int64_t; typedef uint64_t ogg_uint64_t;
#endif
H
cp "$DEPS"/ogg/include/ogg/ogg.h "$DEPS"/ogg/include/ogg/os_types.h "$T/inc/ogg/"
V="$DEPS/vorbis/lib"
clang -O2 -w -DHAVE_ALLOCA_H=0 -I"$T/inc" -I"$DEPS/vorbis/include" -I"$V" "$SRC" \
  "$DEPS/ogg/src/bitwise.c" "$DEPS/ogg/src/framing.c" \
  "$V/mdct.c" "$V/smallft.c" "$V/block.c" "$V/envelope.c" "$V/window.c" "$V/lsp.c" "$V/lpc.c" "$V/analysis.c" \
  "$V/synthesis.c" "$V/psy.c" "$V/info.c" "$V/floor1.c" "$V/floor0.c" "$V/res0.c" "$V/mapping0.c" "$V/registry.c" \
  "$V/codebook.c" "$V/sharedbook.c" "$V/lookup.c" "$V/bitrate.c" "$V/vorbisfile.c" \
  -o "$OUT"
echo "built $OUT"
