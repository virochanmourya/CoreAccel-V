#!/bin/bash
# Multi-run timing measurement: synthesise once, then implement the same
# netlist with several place/route directive pairs in parallel, and summarise
# min / median WNS, TNS and failing endpoints across the runs.
#
# usage: scripts/timing_sweep.sh <out_dir> <imem_hex>
#   imem_hex: IMEM image (IMEM is LUT-ROM, so keep it fixed when comparing).
#   RUNS:     space-separated place:route pairs (default: three below).
#   Results:  <out_dir>/summary.txt, <out_dir>/run<N>/{result,paths}.csv
#             and the usual Vivado reports in each run directory.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(realpath -m "$1")
IMEM=$(realpath "$2")
VIVADO_SETTINGS=${VIVADO_SETTINGS:-/tools/Xilinx/2026.1/settings64.sh}
RUNS=${RUNS:-"Default:Default Explore:Explore ExtraNetDelay_high:AggressiveExplore"}
TCL=$ROOT/scripts/vivado_sweep.tcl

# settings64.sh returns non-zero even on success, so do not chain it with &&
source "$VIVADO_SETTINGS" >/dev/null 2>&1
mkdir -p "$OUT"

( cd "$OUT" && vivado -mode batch -nojournal -log synth.log -source "$TCL" \
      -tclargs synth "$ROOT" "$OUT" "$IMEM" > /dev/null 2>&1 )
[ -f "$OUT/post_synth.dcp" ] || { echo "synthesis failed: see $OUT/synth.log"; exit 1; }

n=0; pids=()
for r in $RUNS; do
    n=$((n + 1)); d=$OUT/run$n; mkdir -p "$d"
    ( cd "$d" && vivado -mode batch -nojournal -log impl.log -source "$TCL" \
          -tclargs impl "$OUT/post_synth.dcp" "$d" "${r%%:*}" "${r##*:}" > /dev/null 2>&1 ) &
    pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

python3 -I - "$OUT" "$n" <<'EOF' | tee "$OUT/summary.txt"
import csv, statistics, sys, os
out, n = sys.argv[1], int(sys.argv[2])
rows = []
for i in range(1, n + 1):
    f = os.path.join(out, f"run{i}", "result.csv")
    if not os.path.exists(f):
        print(f"run{i}: FAILED (no result.csv)"); continue
    r = next(csv.DictReader(open(f)))
    rows.append(r)
    print(f"run{i} {r['place']:>17}/{r['route']:<18} WNS {float(r['wns']):7.3f}  "
          f"TNS {float(r['tns']):8.3f}  fail {int(r['fail_endpoints']):4d}  "
          f"WHS {float(r['whs']):6.3f}  LUT {r['luts']} FF {r['ffs']}")
    for p in list(csv.DictReader(open(os.path.join(out, f"run{i}", "paths.csv"))))[:3]:
        print(f"     {float(p['slack']):7.3f} L{p['levels']:>2} logic {p['logic_ns']} net {p['net_ns']}  "
              f"{p['start']} -> {p['end']}")
if rows:
    w = [float(r['wns']) for r in rows]
    t = [float(r['tns']) for r in rows]
    e = [int(r['fail_endpoints']) for r in rows]
    h = [float(r['whs']) for r in rows]
    print(f"SUMMARY runs={len(rows)}/{n}  WNS min {min(w):.3f} median {statistics.median(w):.3f} "
          f"max {max(w):.3f}  TNS min {min(t):.3f} median {statistics.median(t):.3f}  "
          f"fail_endpoints max {max(e)} median {statistics.median(e):g}  WHS min {min(h):.3f}  "
          f"CLOSED={'yes' if min(w) >= 0 and min(h) >= 0 and len(rows) == n else 'no'}")
EOF
