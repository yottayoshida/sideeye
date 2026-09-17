#!/bin/sh
# What a whole exploration costs on real targets, and how much of it the verdict needed.
#
# `measure.sh` beside this file measured one world against the size of the state tree and
# said what it could not say: "Nothing about a total. The number of crash points is the
# number of state-changing operations the recording saw, which the operation sets; a run
# costs the per-world figure times crash points plus one, and the file count does not
# predict the multiplier." `corpus.py` reads the multiplier off every committed report.
# This measures the product of the two on targets that are here, with a clock.
#
# A record, not a check (ADR 0039): these are one laptop's figures under one load.
#
#   sh spike/explore-cost/measure-targets.sh [rundir]
#
# Each row is one `sideeye explore` of a define this repository has already committed
# somewhere, re-pathed for this host and named beside its source:
#
#   toy-fixed     spike/toys/toy.c, the fixed build   -- measure.sh's own target, for continuity
#   toy-bug       spike/toys/toy.c, the planted bug   -- `sideeye demo`'s target
#   timew-plain   spike/dogfood-timew.sh, leg (a)     -- no checker
#   timew-undo    spike/dogfood-timew.sh, leg (b)     -- timewarrior's undo contract
#   jpegtran      spike/dogfood/2026-09-06-userview-2/apparatus/run-slate3.sh
#   bsdtar        spike/dogfood/2026-09-06-userview-2/apparatus/run-slate2.sh
#   xz            spike/dogfood/2026-09-16-crossed-walls/apparatus/{screen3,explore}.sh
#
# Three things about the comparison, said here rather than left to be worked out.
#
# The committed runs of these defines were made in a Linux container with `--oracle
# /usr/bin/strace`. There is no strace on macOS and `--oracle-fs-usage` needs a privilege
# this script will not ask for, so every row here is `--allow-unverified`: the engine does
# the same work minus the second witness, and the crash-point count can differ from the
# committed one because the tool is a different build. This script prints only its own
# count; the record compares it with the committed one, and a row whose count differs is a
# fact about the two hosts, not an error.
#
# The clock wraps the engine process, as in `measure.sh`, so per-world is an upper bound:
# start-up, `setup`, the recording run and the snapshots around it are in the total and are
# not worlds.
#
# A row is counted only when the engine reached a verdict and wrote its report: exit 0 or 1
# with `explored == crash_points + 1`. Anything else prints `not-counted` with the rc, so a
# refusal cannot be read as a cheap exploration.
#
# Needs: `zig build` (engine + shim), and on PATH: python3, timew, jpegtran, cjpeg, djpeg,
# xz, bsdtar. Exit 2 names whichever is missing. The toys are built here if absent.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ENGINE="$ROOT/zig-out/bin/sideeye"
case "$(uname -s)" in
    Darwin) SHIM="$ROOT/zig-out/lib/libsideeye_shim.dylib" ;;
    *)      SHIM="$ROOT/zig-out/lib/libsideeye_shim.so" ;;
esac

[ -x "$ENGINE" ] || { echo "measure-targets.sh: $ENGINE is missing -- run \`zig build\` first" >&2; exit 2; }
[ -f "$SHIM" ]   || { echo "measure-targets.sh: $SHIM is missing -- run \`zig build\` first" >&2; exit 2; }
for t in python3 timew jpegtran cjpeg djpeg xz bsdtar; do
    command -v "$t" >/dev/null 2>&1 || { echo "measure-targets.sh: $t is not on PATH" >&2; exit 2; }
done
# On macOS the `bsdtar` on PATH is /usr/bin/bsdtar, a platform binary: dyld drops the
# insert before it starts, the run has no shim marker and the define cannot be measured
# here at all (that refusal is the record's, not a fault of this script). Homebrew's
# libarchive ships the same program as an ordinary binary, so it is preferred when present.
BSDTAR=$(command -v bsdtar)
[ -x /opt/homebrew/opt/libarchive/bin/bsdtar ] && BSDTAR=/opt/homebrew/opt/libarchive/bin/bsdtar

RUN=${1:-$(mktemp -d)}
mkdir -p "$RUN" || exit 2
TOYDIR="$ROOT/spike/out"
mkdir -p "$TOYDIR"
for pair in "toy-fixed:" "toy-bug:-DBUGGY=1"; do
    name=${pair%%:*}; flag=${pair#*:}
    if [ ! -x "$TOYDIR/$name" ]; then
        # shellcheck disable=SC2086
        cc -O0 $flag -o "$TOYDIR/$name" "$ROOT/spike/toys/toy.c" -lpthread 2>/dev/null ||
            { echo "measure-targets.sh: could not build $name from spike/toys/toy.c" >&2; exit 2; }
    fi
done

echo "# explore-cost/targets: $(uname -sm), $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo untracked), zig $(zig version 2>/dev/null || echo '?'), $(date -u +%Y-%m-%dT%H:%MZ)"
case "$(uname -s)" in
    Darwin) echo "# host: macOS $(sw_vers -productVersion 2>/dev/null), $(sysctl -n machdep.cpu.brand_string 2>/dev/null), $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GiB" ;;
    *)      echo "# host: $(uname -r), $(nproc 2>/dev/null || echo '?') cpus" ;;
esac
echo "# engine: $("$ENGINE" version)  mode: --observe wrappers (the default), --allow-unverified (no oracle on this host)"
echo "# tools: timew $(timew --version 2>/dev/null), xz $(xz --version 2>/dev/null | head -1 | awk '{print $NF}'), $(jpegtran -version 2>&1 | head -1), $("$BSDTAR" --version | head -1)"
echo "# load at start: $(uptime | sed 's/.*load average[s]*: */load average /')"
echo "#"
printf '%-12s %-9s %-3s %-8s %-6s %-6s %-5s %-8s %-9s %s\n' \
    target language rc verdict cps worlds viol earliest engine per-world

# run <label> <language> <statedir> <setup> <operation> [check]
run() {
    label=$1; lang=$2; sd=$3; setup=$4; op=$5; check=${6:-}
    d="$RUN/$label"
    mkdir -p "$d"
    # The define, in one place, for `collapse.sh` to re-materialise single worlds from.
    # Written by the same code that runs it, so the two cannot drift apart.
    # Every value is single-quoted: an operation is a command line with spaces in it, and
    # an unquoted `SETUP=/path/toy-bug init` runs `init` when the file is sourced.
    {
        echo "SD='$sd'"
        echo "SETUP='$setup'"
        echo "OP='$op'"
        echo "CHECK='$check'"
        echo "TOY_STATE='${TOY_STATE:-}'"
        echo "TIMEWARRIORDB='${TIMEWARRIORDB:-}'"
    } > "$d/define.env"
    set -- "$ENGINE" explore --state "$sd" --setup "$setup" --operation "$op" \
        --shim "$SHIM" --work "$d/work" --json "$d/report.json" --allow-unverified
    [ -n "$check" ] && set -- "$@" --check "$check"
    timed=$(python3 - "$d/out.txt" "$@" <<'PY'
import subprocess, sys, time
out = open(sys.argv[1], "wb")
s = time.time()
rc = subprocess.call(sys.argv[2:], stdout=out, stderr=subprocess.STDOUT)
print("%d %.3f" % (rc, time.time() - s))
PY
    )
    rc=${timed%% *}; secs=${timed#* }
    python3 - "$label" "$lang" "$rc" "$secs" "$d/report.json" <<'PY'
import json, sys
label, lang, rc, secs, path = sys.argv[1:]
total = float(secs)
try:
    with open(path, encoding="utf-8") as fh:
        d = json.load(fh)
except (OSError, ValueError):
    d = {}
verdict = d.get("verdict", "-")
cps = d.get("crash_points")
worlds = d.get("explored")
viol = d.get("violations")
earliest = (d.get("earliest") or {}).get("crash_point")
ok = verdict in ("PASS", "FAIL") and isinstance(cps, int) and worlds == cps + 1 and cps > 0
per = "%.3fs" % (total / worlds) if ok else "not-counted"
print("%-12s %-9s %-3s %-8s %-6s %-6s %-5s %-8s %-9s %s" % (
    label, lang, rc, verdict, cps if cps is not None else "-", worlds if worlds is not None else "-",
    viol if viol is not None else "-", earliest if earliest is not None else "-", "%.1fs" % total, per))
PY
    [ "$rc" = 0 ] || [ "$rc" = 1 ] || { printf '#   '; head -2 "$d/out.txt" | tr '\n' ' ' | cut -c1-140; echo ""; }
}

# ---- the toys: the same define measure.sh used, so the two records meet ----------------
for toy in toy-fixed toy-bug; do
    sd="$RUN/$toy/state"; mkdir -p "$sd"
    TOY_STATE="$sd" run "$toy" c "$sd" "$TOYDIR/$toy init" "$TOYDIR/$toy rotate"
done

# ---- timewarrior: spike/dogfood-timew.sh, both legs ------------------------------------
# TIMEWARRIORDB is the whole state and the engine hands it to setup, operation and checker
# through its own environment, as that script does.
for leg in plain undo; do
    d="$RUN/timew-$leg"; sd="$d/state"; mkdir -p "$sd"
    cat > "$d/setup.sh" <<'SETUP'
#!/bin/sh
set -eu
timew track 2020-01-01T10:00 - 2020-01-01T11:00 alpha :yes >/dev/null
SETUP
    cp "$ROOT/spike/explore-cost/check-timew-undo.sh" "$d/check.sh"
    chmod +x "$d/setup.sh" "$d/check.sh"
    if [ "$leg" = plain ]; then
        TIMEWARRIORDB="$sd" run "timew-$leg" c++ "$sd" "$d/setup.sh" \
            "timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes"
    else
        TIMEWARRIORDB="$sd" run "timew-$leg" c++ "$sd" "$d/setup.sh" \
            "timew track 2020-01-02T10:00 - 2020-01-02T11:00 beta :yes" "$d/check.sh"
    fi
done

# ---- jpegtran: run-slate3.sh's define, re-pathed ---------------------------------------
d="$RUN/jpegtran"; sd="$d/state"; mkdir -p "$sd"
cat > "$d/setup.sh" <<SETUP
#!/bin/sh
set -eu
python3 - "$d/src.ppm" <<'PY'
import sys
w = h = 32
with open(sys.argv[1], 'wb') as f:
    f.write(b'P6\n%d %d\n255\n' % (w, h))
    f.write(bytes([(x * 7 + y * 3) % 256 for y in range(h) for x in range(w) for _ in range(3)]))
PY
cjpeg -quality 80 -outfile "$sd/a.jpg" "$d/src.ppm"
SETUP
cat > "$d/check.sh" <<CHECK
#!/bin/sh
f="$sd/a.jpg"
[ -f "\$f" ] || { echo "a.jpg is gone"; exit 1; }
out=\$(djpeg -pnm "\$f" 2>/dev/null | head -c 32) || {
  echo "djpeg cannot read a.jpg (\$(wc -c < "\$f") bytes)"; exit 1; }
[ -n "\$out" ] || { echo "no pixels come out of a.jpg (\$(wc -c < "\$f") bytes)"; exit 1; }
exit 0
CHECK
chmod +x "$d/setup.sh" "$d/check.sh"
run jpegtran c "$sd" "$d/setup.sh" "jpegtran -copy all -optimize -outfile $sd/a.jpg $sd/a.jpg" "$d/check.sh"

# ---- bsdtar: run-slate2.sh's define, re-pathed -----------------------------------------
d="$RUN/bsdtar"; sd="$d/state"; mkdir -p "$sd" "$d/src"
printf 'one\n' > "$d/src/f1.txt"; printf 'two\n' > "$d/src/f2.txt"; printf 'three\n' > "$d/src/f3.txt"
cat > "$d/setup.sh" <<SETUP
#!/bin/sh
set -eu
"$BSDTAR" -cf "$sd/a.tar" -C "$d/src" f1.txt f2.txt
SETUP
cat > "$d/check.sh" <<CHECK
#!/bin/sh
a="$sd/a.tar"
[ -f "\$a" ] || { echo "a.tar is gone"; exit 1; }
list=\$("$BSDTAR" -tf "\$a" 2>/dev/null) || {
  echo "bsdtar cannot read a.tar (\$(wc -c < "\$a") bytes)"; exit 1; }
for n in f1.txt f2.txt; do
  echo "\$list" | grep -qx "\$n" || { echo "a.tar lost its original entry \$n"; exit 1; }
done
exit 0
CHECK
chmod +x "$d/setup.sh" "$d/check.sh"
run bsdtar c "$sd" "$d/setup.sh" "$BSDTAR -uf $sd/a.tar -C $d/src f3.txt" "$d/check.sh"

# ---- xz: screen3.sh's setup and explore.sh's checker, re-pathed ------------------------
d="$RUN/xz"; sd="$d/state"; mkdir -p "$sd"
cat > "$d/setup.sh" <<SETUP
#!/bin/sh
set -eu
for f in "$sd"/*; do [ -e "\$f" ] && rm -f "\$f"; done
python3 - "$sd/f.bin" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(250000):
        f.write(b"MARKER-%07d-payload\n" % i)
PY
cp "$sd/f.bin" "$d/xz.orig"
SETUP
cat > "$d/check.sh" <<CHECK
#!/bin/sh
orig="$d/xz.orig"
if [ -f "$sd/f.bin" ]; then
  cmp -s "$sd/f.bin" "\$orig" && exit 0
  echo "f.bin is present but differs (\$(wc -c < "$sd/f.bin") bytes)"; exit 1
fi
if [ -f "$sd/f.bin.xz" ]; then
  xz -q -d -c "$sd/f.bin.xz" > "$d/xz-out.bin" 2>"$d/xz-err.txt" || {
    echo "f.bin is gone and f.bin.xz does not decompress (\$(wc -c < "$sd/f.bin.xz") bytes)"; exit 1; }
  cmp -s "$d/xz-out.bin" "\$orig" && exit 0
  echo "f.bin is gone and f.bin.xz decompresses to something else"; exit 1
fi
echo "neither f.bin nor f.bin.xz is present"; exit 1
CHECK
chmod +x "$d/setup.sh" "$d/check.sh"
run xz c "$sd" "$d/setup.sh" "xz -q -T2 --block-size=1MiB $sd/f.bin" "$d/check.sh"

echo "# load at end: $(uptime | sed 's/.*load average[s]*: */load average /')"
echo "# reports and engine output under $RUN/<target>/"
