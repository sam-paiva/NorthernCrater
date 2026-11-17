#!/usr/bin/env bash
# FFmpeg n9.0.2 (FFNx's pin) for macOS x86_64 (tools/build_ffmpeg_android.sh for the Mac):
# FF7's movies are Matroska with VP8 video and Vorbis audio.
# Output: build/ffmpeg-mac/{include,lib}
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/external/deps/ffmpeg"
ARCH="${FF7_ARCH:-x86_64}"                     # FF7_ARCH=arm64: the native Apple silicon build
OUT="$ROOT/build/ffmpeg-mac$([ "$ARCH" = arm64 ] && echo -arm64)"
[ -d "$SRC" ] || git -c advice.detachedHead=false clone -q --depth 1 -b n9.0.2 https://github.com/FFmpeg/FFmpeg.git "$SRC"
mkdir -p "$OUT/build"
# FFmpeg's configure can't build from a path with spaces ("Out of tree builds are impossible with
# whitespace in source path"): work through links without them
case "$ROOT" in *" "*)
  LINKS="$(mktemp -d /tmp/gjm-ffmpeg.XXXXXX)"
  ln -s "$SRC" "$LINKS/src"; ln -s "$OUT" "$LINKS/out"
  SRC="$LINKS/src"; OUT="$LINKS/out" ;;
esac
cd "$OUT/build"
"$SRC/configure" \
  --prefix="$OUT" \
  --arch=$ARCH --enable-cross-compile --target-os=darwin \
  --cc="clang -arch $ARCH -mmacosx-version-min=12.0" --cxx="clang++ -arch $ARCH -mmacosx-version-min=12.0" \
  --pkg-config=false \
  --enable-static --disable-shared --enable-pic \
  --disable-programs --disable-doc --disable-debug --disable-avdevice --disable-avfilter \
  --disable-everything --disable-x86asm \
  --disable-videotoolbox --disable-audiotoolbox --disable-securetransport --disable-iconv --disable-lzma --disable-bzlib \
  --enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample \
  --enable-protocol=file \
  --enable-demuxer=matroska,ogg,avi,mov,mp3,wav \
  --enable-decoder=vp8,vp9,vorbis,opus,h264,mpeg4,aac,mp3,pcm_s16le,adpcm_ms \
  --enable-parser=vp8,vp9,vorbis,opus,h264,mpeg4video,aac,mpegaudio \
  --extra-cflags="-O2 -fPIC" > "$OUT/configure.log" 2>&1 || { tail -30 "$OUT/configure.log"; exit 1; }
make -j"$(sysctl -n hw.ncpu)" > "$OUT/make.log" 2>&1 || { tail -30 "$OUT/make.log"; exit 1; }
make install > "$OUT/install.log" 2>&1
ls -la "$OUT/lib"
