#!/usr/bin/env bash
# Lift game/ff7_en.exe to C (generated/recomp) with every patch manifest: FFNx's
# (config/ffnx_manifests) and the mods' hext ones (analysis/ffnx_manifests, tools/relift_mods_mac.sh).
# Writes into generated/recomp.new and swaps it in only when the lift completed.
# usage: bash tools/lift_mac.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PYTHONPATH="$ROOT/external/deps/pefile${PYTHONPATH:+:$PYTHONPATH}"
N=$(sysctl -n hw.ncpu); [ "$N" -gt 8 ] && N=8
NEW=generated/recomp.new
rm -rf "$NEW" && mkdir -p "$NEW" build
M=$( (ls config/ffnx_manifests/*.json analysis/ffnx_manifests/*.json 2>/dev/null || true) | tr "\n" "," | sed "s/,$//")
pids=()
for i in $(seq 0 $((N - 1))); do
  python3 tools/run_lift.py lift game/ff7_en.exe config/catalog.json.gz "$NEW" --shard "$i/$N" --chunk-bytes 4000000 \
    --manifests "$M" > "build/lift_$i.log" 2>&1 & pids+=($!)
done
FF7_CATALOG=config/catalog.json.gz FF7_EXE=game/ff7_en.exe FF7_RETN_OUT="$NEW/recomp_retn.c" python3 tools/gen_retn_table.py > build/retn.log 2>&1
for p in "${pids[@]}"; do wait "$p" || { echo "lift failed: see build/lift_*.log" >&2; exit 1; }; done
grep -h 'FFNx manifests' build/lift_0.log || true
python3 tools/gen_extents.py "$NEW" | tail -1
[ -f "$NEW/recomp_dispatch.c" ] && [ -f "$NEW/recomp_retn.c" ] && [ -f "$NEW/recomp_extents.c" ] || { echo "the lift wrote no code" >&2; exit 1; }
rm -rf generated/recomp && mv "$NEW" generated/recomp
echo "lifted: $(ls generated/recomp | wc -l | tr -d ' ') files"
