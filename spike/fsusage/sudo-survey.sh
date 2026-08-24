#!/bin/sh
# The privileged half of the fs_usage survey (#286, route F1).
#
# RUN AS ROOT, BY THE CI RUNNER OR BY THE OWNER'S OWN HAND. The assistant does
# not run this: the rule that keeps Claude away from sudo is a discipline, not
# a technical limit, and this header is where it is written down.
#
# Measures the four points the plan names — P1 attribution, P2 write
# granularity and order, P3 path fidelity, P4 failed attempts — plus a
# full-line census of every capture, against two ground truths: the probe's
# self-account and, where the leg runs under the shim, the shim's own binary
# trace. Verdicts come from classify.py; rc 1 from a judge is a measured DEAD
# and is NOT a broken apparatus, so it does not fail this script.
#
# Env:
#   OUT   directory for raw captures, accounts, traces (default: ./out)
#   SHIM  path to libsideeye_shim.dylib (default: ../../zig-out/lib/...)
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="${OUT:-$here/out}"
SHIM="${SHIM:-$here/../../zig-out/lib/libsideeye_shim.dylib}"
mkdir -p "$OUT"
# Canonical spelling on purpose. Round 1 (run 32687071111) handed the shim a
# state dir spelled /tmp/...; the shim resolves descriptors with F_GETPATH,
# which answers /private/tmp/..., and without SIDEEYE_STATE_DIR_ALT it judged
# every write out of scope and recorded only the opens. The engine passes both
# spellings; this harness passes the resolved one.
W=$(mktemp -d /private/tmp/se286f1.XXXXXX) || { echo "BROKEN: mktemp failed" >&2; exit 1; }
case "$W" in /private/tmp/se286f1.*) : ;; *) echo "BROKEN: unexpected workdir '$W'" >&2; exit 1 ;; esac
FAILS=0
DEAD=0
bad() { echo "BROKEN: $*"; FAILS=$((FAILS+1)); }

echo "== environment (the transcript must say which machine concluded what)"
sw_vers | sed 's/^/   /'
echo "   $(uname -rm)"
echo "   $(csrutil status 2>/dev/null || echo 'csrutil: unavailable')"
echo "   uid $(id -u) ($(id -un)); virtualization: $(sysctl -n kern.hv_vmm_present 2>/dev/null || echo unknown)"
echo "   fs_usage: $(shasum -a 256 "$(command -v fs_usage)" | cut -c1-16)... at $(command -v fs_usage)"
echo "   filesystem at /tmp: $(df -T 2>/dev/null /tmp | tail -1 || mount | grep ' / ' | head -1)"
[ "$(id -u)" -eq 0 ] || { echo "this half needs root; run it via sudo (CI) or the owner's terminal"; exit 1; }

echo ""
echo "== build (probe with cc; the shim is expected from zig build)"
/usr/bin/cc -O0 -Wall -Wextra -o "$W/probe" "$here/probe.c" || bad "probe build failed"
if [ -f "$SHIM" ]; then echo "   shim: $SHIM"
else echo "   shim: ABSENT at $SHIM (P2 trace legs will be BROKEN, deliberately loud)"; fi

# ---------------------------------------------------------------------------
# capture <leg-name> <mode> <gap_ms> <state-dir> <filter:pid|name|none|narrow>
#         <with_shim:yes|no>
#
# One probe run under one observer configuration. Everything the leg produced
# lands under $OUT/<leg-name>.*: the raw capture, the state-scoped slice, the
# probe account, and (with the shim) the binary trace.
# ---------------------------------------------------------------------------
capture() {
    leg=$1; mode=$2; gapms=$3; state=$4; filter=$5; with_shim=$6
    d="$W/$leg"; mkdir -p "$d" "$state"
    "$W/probe" --setup "$state" "$mode" 2> "$d/setup.err" || { bad "$leg: setup failed"; return 1; }

    : > "$d/ops.jsonl"
    if [ "$with_shim" = yes ]; then
        DYLD_INSERT_LIBRARIES="$SHIM" SIDEEYE_STATE_DIR="$state" \
            SIDEEYE_TRACE_PATH="$d/trace.bin" \
            "$W/probe" --run "$state" "$mode" --gap-ms "$gapms" \
            --pause-file "$d/go" > "$d/ops.jsonl" 2> "$d/probe.err" &
    else
        "$W/probe" --run "$state" "$mode" --gap-ms "$gapms" \
            --pause-file "$d/go" > "$d/ops.jsonl" 2> "$d/probe.err" &
    fi
    ppid=$!

    i=0
    while [ "$i" -lt 100 ]; do
        grep -q '"type":"hello"' "$d/ops.jsonl" 2>/dev/null && break
        sleep 0.1; i=$((i+1))
    done
    grep -q '"type":"hello"' "$d/ops.jsonl" || { bad "$leg: probe never said hello"; kill "$ppid" 2>/dev/null; return 1; }

    case "$filter" in
        all)    fs_usage -w            -t 25 "$ppid" > "$d/cap.txt" 2>&1 & ;;
        pid)    fs_usage -w -f filesys -t 25 "$ppid" > "$d/cap.txt" 2>&1 & ;;
        name)   fs_usage -w -f filesys -t 25 probe   > "$d/cap.txt" 2>&1 & ;;
        none)   fs_usage -w -f filesys -t 25         > "$d/cap.txt" 2>&1 & ;;
        narrow) fs_usage    -f filesys -t 25 "$ppid" > "$d/cap.txt" 2>&1 & ;;
    esac
    fpid=$!
    sleep 1.5                      # let the observer attach before the window opens
    : > "$d/go"
    wait "$ppid"; prc=$?
    sleep 1.0                      # drain
    kill -TERM "$fpid" 2>/dev/null
    wait "$fpid" 2>/dev/null; frc=$?
    echo "   $leg: probe rc=$prc, fs_usage rc=$frc (TERM after drain is expected), capture $(wc -l < "$d/cap.txt" | tr -d ' ') line(s)"
    [ "$prc" -eq 0 ] || bad "$leg: probe rc=$prc"

    cp "$d/cap.txt" "$OUT/$leg.cap.txt"
    grep -F "$state" "$d/cap.txt" > "$OUT/$leg.state.txt" 2>/dev/null || true
    cp "$d/ops.jsonl" "$OUT/$leg.ops.jsonl"
    [ -f "$d/trace.bin" ] && cp "$d/trace.bin" "$OUT/$leg.trace.bin"
    return 0
}

judge() { # leg-kind args...
    kind=$1; shift
    python3 "$here/classify.py" "$kind" "$@"
    jrc=$?
    if [ "$jrc" -eq 2 ]; then bad "judge $kind could not measure (rc 2)"
    elif [ "$jrc" -eq 1 ]; then DEAD=$((DEAD+1)); fi
    return "$jrc"
}

echo ""
echo "== L0: liveness — one create, pid-filtered, both sentinels must appear"
capture L0 create 0 "$W/L0-state" pid no && {
    judge liveness "$OUT/L0.cap.txt" "$OUT/L0.ops.jsonl"
    judge census   "$OUT/L0.cap.txt" "$OUT/L0.ops.jsonl"
}

echo ""
echo "== P4: do failed attempts leave a line? (the counterexample that killed FSEvents)"
for m in fail-open fail-unlink fail-rename fail-mkdir fail-rmdir fail-link fail-truncate; do
    capture "P4-$m" "$m" 0 "$W/P4-$m-state" pid no && {
        judge p4     "$OUT/P4-$m.cap.txt" "$OUT/P4-$m.ops.jsonl"
        judge census "$OUT/P4-$m.cap.txt" "$OUT/P4-$m.ops.jsonl"
    }
done

echo ""
echo "== P2: write granularity, against the shim's own trace"
for m in write writes-small writes-two-fd write-large write-zero pwrite writev stdio fsync; do
    capture "P2-$m" "$m" 30 "$W/P2-$m-state" pid yes && {
        if [ -f "$OUT/P2-$m.trace.bin" ]; then
            judge p2-counts "$OUT/P2-$m.cap.txt" "$OUT/P2-$m.ops.jsonl" "$OUT/P2-$m.trace.bin"
        else
            bad "P2-$m: no shim trace (DYLD stripped? shim absent?)"
        fi
        judge census "$OUT/P2-$m.cap.txt" "$OUT/P2-$m.ops.jsonl"
    }
done

echo ""
echo "== P2-fsync: does fsync leave a syscall line? (-f filesys, then no class filter at all)"
judge p2-fsync "$OUT/P2-fsync.cap.txt" "$OUT/P2-fsync.ops.jsonl"
capture P2SYNC-all fsync 30 "$W/P2SYNC-all-state" all yes && {
    judge p2-fsync "$OUT/P2SYNC-all.cap.txt" "$OUT/P2SYNC-all.ops.jsonl"
    judge census   "$OUT/P2SYNC-all.cap.txt" "$OUT/P2SYNC-all.ops.jsonl"
}

echo ""
echo "== P2-order: does capture order carry operation order?"
for m in write-rename write-unlink; do
    capture "P2ORD-$m" "$m" 80 "$W/P2ORD-$m-state" pid no && {
        judge p2-order "$OUT/P2ORD-$m.cap.txt" "$OUT/P2ORD-$m.ops.jsonl"
    }
done

echo ""
echo "== P1: attribution — same-named binaries, same state dir, same file names"
P1S="$W/P1-state"; mkdir -p "$P1S"
mkdir -p "$W/copyA" "$W/copyB"
cp "$W/probe" "$W/copyA/probe"; cp "$W/probe" "$W/copyB/probe"
"$W/copyA/probe" --setup "$P1S" create 2>/dev/null
: > "$W/P1-A.jsonl"; : > "$W/P1-B.jsonl"
"$W/copyA/probe" --run "$P1S" create --pause-file "$W/P1-go" > "$W/P1-A.jsonl" 2>/dev/null &
apid=$!
"$W/copyB/probe" --run "$P1S" create --pause-file "$W/P1-go" > "$W/P1-B.jsonl" 2>/dev/null &
bpid=$!
i=0; while [ "$i" -lt 100 ]; do
    grep -q hello "$W/P1-A.jsonl" 2>/dev/null && grep -q hello "$W/P1-B.jsonl" 2>/dev/null && break
    sleep 0.1; i=$((i+1))
done
echo "-- P1a: pid filter names only A ($apid); does B ($bpid) leak through?"
fs_usage -w -f filesys -t 20 "$apid" > "$W/P1a-cap.txt" 2>&1 &
fpid=$!
sleep 1.5; : > "$W/P1-go"
wait "$apid"; arc=$?; wait "$bpid"; brc=$?
sleep 1.0; kill -TERM "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
echo "   probes rc=$arc/$brc, capture $(wc -l < "$W/P1a-cap.txt" | tr -d ' ') line(s)"
cp "$W/P1a-cap.txt" "$OUT/P1a.cap.txt"; cp "$W/P1-A.jsonl" "$OUT/P1-A.ops.jsonl"; cp "$W/P1-B.jsonl" "$OUT/P1-B.ops.jsonl"
grep -F "$P1S" "$W/P1a-cap.txt" > "$OUT/P1a.state.txt" 2>/dev/null || true
judge p1-pidfilter "$OUT/P1a.cap.txt" "$OUT/P1-A.ops.jsonl" "$OUT/P1-B.ops.jsonl"

echo "-- P1b: name filter covers both; can the lines be attributed at all?"
P1BS="$W/P1b-state"; mkdir -p "$P1BS"
"$W/copyA/probe" --setup "$P1BS" create 2>/dev/null
: > "$W/P1b-A.jsonl"; : > "$W/P1b-B.jsonl"
"$W/copyA/probe" --run "$P1BS" create --pause-file "$W/P1b-go" > "$W/P1b-A.jsonl" 2>/dev/null &
apid=$!
"$W/copyB/probe" --run "$P1BS" create --pause-file "$W/P1b-go" > "$W/P1b-B.jsonl" 2>/dev/null &
bpid=$!
i=0; while [ "$i" -lt 100 ]; do
    grep -q hello "$W/P1b-A.jsonl" 2>/dev/null && grep -q hello "$W/P1b-B.jsonl" 2>/dev/null && break
    sleep 0.1; i=$((i+1))
done
fs_usage -w -f filesys -t 20 probe > "$W/P1b-cap.txt" 2>&1 &
fpid=$!
sleep 1.5; : > "$W/P1b-go"
wait "$apid"; wait "$bpid"
sleep 1.0; kill -TERM "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
cp "$W/P1b-cap.txt" "$OUT/P1b.cap.txt"; cp "$W/P1b-A.jsonl" "$OUT/P1b-A.ops.jsonl"; cp "$W/P1b-B.jsonl" "$OUT/P1b-B.ops.jsonl"
grep -F "$P1BS" "$W/P1b-cap.txt" > "$OUT/P1b.state.txt" 2>/dev/null || true
judge p1-partition "$OUT/P1b.cap.txt" "$OUT/P1b-A.ops.jsonl" "$OUT/P1b-B.ops.jsonl"

echo "-- P1c: is a forked child followed under the parent's pid filter?"
capture P1c child-write 0 "$W/P1c-state" pid no && {
    judge p1-child "$OUT/P1c.cap.txt" "$OUT/P1c.ops.jsonl"
}

echo ""
echo "== P3: path fidelity"
capture P3-rename rename 0 "$W/P3-state" pid no && {
    judge p3-rename "$OUT/P3-rename.cap.txt" "$OUT/P3-rename.ops.jsonl"
}
echo "-- P3-narrow: the same create WITHOUT -w (the 28-byte claim, seen verbatim)"
capture P3-narrow create 0 "$W/P3-narrow-state" narrow no && {
    echo "   state-scoped lines, narrow mode, verbatim:"
    sed 's/^/   | /' "$OUT/P3-narrow.state.txt" | head -6
    echo "   (empty above = the narrow path never matched the state dir string,"
    echo "    which is itself the 28-byte truncation showing)"
}
echo "-- P3-deep: a state dir nested past 180 characters, wide mode"
DEEP="$W/p3deep"
i=0; while [ "$i" -lt 12 ]; do DEEP="$DEEP/nested-component"; i=$((i+1)); done
capture P3-deep create 0 "$DEEP/state" pid no && {
    judge p3-depth "$OUT/P3-deep.cap.txt" "$OUT/P3-deep.ops.jsonl"
}
echo "-- P3-weird: a directory name holding a space and non-ASCII"
capture P3-weird create 0 "$W/wei rd-ステート/state" pid no && {
    judge liveness "$OUT/P3-weird.cap.txt" "$OUT/P3-weird.ops.jsonl"
    echo "   state-scoped lines, verbatim:"
    sed 's/^/   | /' "$OUT/P3-weird.state.txt" | head -4
}

echo ""
echo "== what this transcript does not answer"
echo "   Behaviour under load (event drop), non-APFS volumes, network mounts,"
echo "   and any macOS version other than the one self-reported above."

/bin/rm -rf "${W:?}" 2>/dev/null || true
echo ""
echo "== measured DEAD verdicts: $DEAD (a DEAD is a finding, not a failure)"
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
