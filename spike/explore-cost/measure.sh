#!/bin/sh
# Per-world exploration cost on the host, by file count and by bytes (#262, ADR 0042).
#
# A record, not a check: these are one laptop's figures, and ADR 0039 holds quoted
# figures by review rather than by CI. Each row is one `sideeye explore` of the fixed toy
# (one file of its own, two during the operation, four crash points) over a padding
# directory the operation never touches, so the per-world cost is the engine's own work —
# restore the whole tree, run, snapshot the whole tree — and nothing the target does. No
# oracle, no checker, no forking target. Every padding file holds the same random bytes;
# only their number and size vary.
#
# `per-world` is the engine's wall-clock time divided by the number of worlds it reports.
# The wall clock also covers engine start-up, `setup`, the recording run and the two
# snapshots around it, none of which is a world, so the figure is an upper bound on one
# world: on this toy the extra is roughly two full-tree reads on top of the ten passes
# (five restores, five snapshots) the five worlds cost. The timer wraps the engine
# process only; the padding is built before it starts.
#
# A row is counted only when the engine says it ran a full exploration: exit code 0 and
# its own line `explored N worlds (crash points K + 1 baseline)` with N = K + 1. Any other
# outcome prints `not-counted` and no figure — a refusal (UNKNOWN; the snapshot ceiling is
# the one this measurement could hit), a FAIL, or a recording that saw no state-changing
# operation, which the engine reports with a different line (docs/report-schema.md,
# `explored`). The first draft of this table carried a row that was suspected of measuring
# the ceiling's refusal instead of an exploration, and nothing in the draft could say which.
#
#   sh spike/explore-cost/measure.sh [tmpdir]
#
# Needs: zig-out/bin/sideeye and the shim (`zig build`); spike/out/toy-fixed built for
# THIS host (`spike/build-toys.sh`, or `cc -O0 -o spike/out/toy-fixed spike/toys/toy.c
# -lpthread`); python3, which runs the engine and times it (macOS `date` has no %N); and
# `file`, which checks the toy is a binary for this host. Exit 2 names whichever is
# missing. The padding trees are built under tmpdir (default: mktemp -d) and left there;
# the largest is 20,000 files. The header names the binaries relative to the checkout and
# does not record tmpdir, so a run log carries no local absolute path; it does record the
# load average, because the constants depend on it.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENGINE="$ROOT/zig-out/bin/sideeye"
TOY="$ROOT/spike/out/toy-fixed"
case "$(uname -s)" in
    Darwin) SHIM="$ROOT/zig-out/lib/libsideeye_shim.dylib"; want="Mach-O" ;;
    *)      SHIM="$ROOT/zig-out/lib/libsideeye_shim.so";    want="ELF" ;;
esac

[ -x "$ENGINE" ] || { echo "measure.sh: $ENGINE is missing — run \`zig build\` first" >&2; exit 2; }
[ -f "$SHIM" ]   || { echo "measure.sh: $SHIM is missing — run \`zig build\` first" >&2; exit 2; }
[ -x "$TOY" ]    || { echo "measure.sh: $TOY is missing — build it with spike/build-toys.sh (or cc, see the header)" >&2; exit 2; }
command -v file >/dev/null 2>&1    || { echo "measure.sh: \`file\` is needed to check the toy's architecture" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "measure.sh: python3 is needed to run and time the engine" >&2; exit 2; }
if ! file "$TOY" | grep -q "$want"; then
    echo "measure.sh: $TOY is not a $want binary for this host: $(file "$TOY" | cut -d: -f2-)" >&2
    echo "            rebuild it here with spike/build-toys.sh (a container build does not run on the host)" >&2
    exit 2
fi

TMP=${1:-$(mktemp -d)}
mkdir -p "$TMP" || exit 2

echo "# explore-cost: $(uname -sm), $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo untracked), zig $(zig version 2>/dev/null || echo '?'), $(date -u +%Y-%m-%dT%H:%MZ)"
case "$(uname -s)" in
    Darwin) echo "# host: macOS $(sw_vers -productVersion 2>/dev/null), $(sysctl -n machdep.cpu.brand_string 2>/dev/null), $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GiB" ;;
    *)      echo "# host: $(uname -r), $(nproc 2>/dev/null || echo '?') cpus" ;;
esac
echo "# load at start: $(uptime | sed 's/.*load average[s]*: */load average /')"
echo "# engine: ${ENGINE#"$ROOT"/}  shim: ${SHIM#"$ROOT"/}  toy: ${TOY#"$ROOT"/}  (paths relative to the checkout)"
echo "# per-world = engine wall clock / worlds; the clock includes start-up, setup, the recording run and its snapshots (an upper bound on one world)"
echo "#"
printf '%-12s %-9s %-7s %-7s %-3s %-7s %-6s %-9s %s\n' shape padfiles padsize du rc worlds cps engine per-world
# shape name : padding files : bytes per padding file
for spec in "small:20:1024" "f200-100k:200:102400" "f2000-10k:2000:10240" "f2000-50k:2000:51200" "f20000-1k:20000:1024"; do
    name=${spec%%:*}; rest=${spec#*:}; nfiles=${rest%%:*}; fsize=${rest#*:}
    d="$TMP/$name"
    mkdir -p "$d/state/pad" || exit 2
    python3 - "$d/state/pad" "$nfiles" "$fsize" <<'PY'
import os, sys
d, n, sz = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
blob = os.urandom(sz)
for i in range(n):
    with open(os.path.join(d, "f%05d.bin" % i), "wb") as f:
        f.write(blob)
PY
    size=$(du -sh "$d/state" | cut -f1)
    # python runs the engine and times just that process; its output goes to out.txt.
    timed=$(TOY_STATE="$d/state" python3 - "$d/out.txt" "$ENGINE" explore --state "$d/state" \
        --setup "$TOY init" --operation "$TOY rotate" \
        --shim "$SHIM" --work "$d/work" --allow-unverified <<'PY'
import subprocess, sys, time
out = open(sys.argv[1], "wb")
s = time.time()
rc = subprocess.call(sys.argv[2:], stdout=out, stderr=subprocess.STDOUT)
print("%d %.3f" % (rc, time.time() - s))
PY
    )
    rc=${timed%% *}; secs=${timed#* }
    # The engine's own account of what it ran: `explored N worlds (crash points K + 1 baseline)`.
    line=$(grep -o 'explored [0-9]* worlds (crash points [0-9]* + 1 baseline)' "$d/out.txt" | head -1)
    worlds=$(printf '%s' "$line" | awk '{print $2}')
    cps=$(printf '%s' "$line" | awk '{print $6}')
    python3 - "$name" "$nfiles" "$fsize" "$size" "$rc" "${worlds:-}" "${cps:-}" "$secs" <<'PY'
import sys
name, nfiles, fsize, size, rc, worlds, cps, secs = sys.argv[1:]
total = float(secs)
ok = rc == "0" and worlds.isdigit() and cps.isdigit() and int(worlds) == int(cps) + 1
per = "%.3fs" % (total / int(worlds)) if ok else "not-counted"
print("%-12s %-9s %-7s %-7s %-3s %-7s %-6s %-9s %s" % (name, nfiles, fsize, size, rc, worlds or "-", cps or "-", "%.1fs" % total, per))
PY
    [ "$rc" = 0 ] || { printf '#   '; head -1 "$d/out.txt" | cut -c1-120; }
done
echo "# load at end: $(uptime | sed 's/.*load average[s]*: */load average /')"
