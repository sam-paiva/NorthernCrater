#!/usr/bin/env bash
# setup_mac.sh: tools/setup.ps1 for macOS. Clones the pinned toolkits into external/ and
# re-applies our patches, then runs the FFNx header ports. Safe to re-run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$ROOT/external"
mkdir -p "$EXT"
PY="${PYTHON:-python3}"

pin() {   # pin <name> <url> <rev> <patch dir or ->
  local dir="$EXT/$1"
  [ -d "$dir" ] || git clone -q "$2" "$dir"
  git -C "$dir" fetch -q origin
  git -C "$dir" cat-file -e "$3^{commit}" 2>/dev/null || git -C "$dir" fetch -q origin "$3"
  git -C "$dir" reset -q --hard
  git -C "$dir" clean -qfd
  git -C "$dir" -c advice.detachedHead=false checkout -q "$3"
  if [ "$1" = FFNx ]; then   # the patches were made on an LF checkout; the repo stores CRLF
    git -C "$dir" ls-files --eol | awk '$1=="i/crlf"||$1=="i/mixed"{print $NF}' | \
      (cd "$dir" && while IFS= read -r f; do perl -pi -e 's/\r$//' "$f"; done)
  fi
  if [ "$4" != "-" ]; then
    for p in "$ROOT/$4"/*.patch; do       # (a glob, sorted, and safe with spaces in the path)
      [ -f "$p" ] || continue
      git -C "$dir" apply "$p"
      echo "  applied $1/$(basename "$p")"
    done
  fi
  echo "$1 @ $(git -C "$dir" rev-parse --short HEAD)"
}

pin pcrecomp         https://github.com/sp00nznet/pcrecomp.git        35548b8d0fd8aa853da67edcf7cd6134f6b9cdc7 patches/pcrecomp
pin FFNx             https://github.com/julianxhokaxhiu/FFNx.git      0adf0b32                                 patches/ffnx
pin nfsu2-recompiled https://github.com/codepdbh/nfsu2-recompiled.git main                                     -
pin bx               https://github.com/julianxhokaxhiu/bx.git        c99974204c15405b69647d5097af1102e6210c91 -
pin bimg             https://github.com/julianxhokaxhiu/bimg.git      671fe06dd7012a1ab85aa931019ed16112909756 -
pin bgfx             https://github.com/julianxhokaxhiu/bgfx.git      1f93b90898dcc492587b617b397e2d2285dcd0ec patches/bgfx

"$PY" -I "$ROOT/tools/ffnx_port.py" gptr
"$PY" -I "$ROOT/tools/ffnx_port.py" casts
"$PY" -I "$ROOT/tools/ffnx_port.py" calls
"$PY" -I "$ROOT/tools/ffnx_port.py" overrides
"$PY" -I "$ROOT/tools/ffnx_edit_android.py"
"$PY" -I "$ROOT/tools/ffnx_edit_mac.py"
echo "setup ok"
