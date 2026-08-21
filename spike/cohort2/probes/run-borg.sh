#!/bin/sh
# Cohort-2 probe: BorgBackup (PROTOCOL.md "Probe plans", target 1).
# Engine-free: normal executions only — no kill, no crash, no checker.
#
# Modes:
#   ./run-borg.sh          the pinned probe (--timestamp fixed) — the real verdict
#   ./run-borg.sh control  the positive control (NO --timestamp): the same
#                          determinism check must SPLIT. Exit 0 = split seen.
#   ./run-borg.sh frozen   the #200 follow-up: pinned PLUS the declared
#                          apparatus, three pieces — libfaketime via
#                          /etc/ld.so.preload with FAKETIME "@...x0" (realtime
#                          frozen; monotonic left real so sleeps/timeouts
#                          outside borg stay alive), and a sitecustomize
#                          pinning Python's time.monotonic AND os.urandom
#                          (reaches borg via PYTHONPATH; the C world is
#                          untouched). Measured leaks, each found by running:
#                          time_end = --timestamp + monotonic duration; the
#                          manifest's utcnow; and the TAM authentication
#                          tag's random salt (os.urandom, present even at
#                          encryption=none — owner-approved 2026-08-21: this
#                          is an integrity tag's salt, not encryption).
#
# Runs A and B execute IN PLACE at one canonical path, restored from a
# pristine snapshot between them — the engine's own restore semantics.
# The first frozen round taught why: borg stores the full command line in
# the archive metadata, so a harness that runs A and B in different
# directories manufactures a split no real exploration would see (the
# cmdline embeds the repo path; id and stats cascade from it). In-place
# also puts every run at the repo's init path, so no relocation prompt and
# no override env.
#
# Conditions 1-6 are machine-judged (the FAILS counter); condition 7 is the
# printed ambient evidence below. Raw strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/lib.sh"

MODE=${1:-pinned}
WS=/tmp/probe-borg-$MODE
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS"

if [ "$MODE" = frozen ]; then
    FTLIB=$(find /usr/lib -name "libfaketime.so.1" | head -1)
    [ -n "$FTLIB" ] || { echo "SETUP: libfaketime not in the image"; exit 2; }
    echo "$FTLIB" > /etc/ld.so.preload
    export FAKETIME="@2026-01-01 00:00:00 x0"
    mkdir -p "$WS/pylib"
    printf 'import time, os\ntime.monotonic = lambda: 0.0\nos.urandom = lambda n: b"\\x5a" * n\n' > "$WS/pylib/sitecustomize.py"
    export PYTHONPATH="$WS/pylib"
    note "apparatus (#200): ld.so.preload=$FTLIB FAKETIME='$FAKETIME' + sitecustomize time.monotonic=0.0, os.urandom=0x5a* via PYTHONPATH"
fi

note "borg probe ($MODE) — $(borg --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- pre-state, built once at the canonical paths --------------------------
mkdir -p "$WS/src"
printf 'alpha file, fixed bytes\n' > "$WS/src/alpha"
printf 'beta file, fixed bytes\n'  > "$WS/src/beta"
printf 'gamma file, fixed bytes\n' > "$WS/src/gamma"
touch -t 202601010000 "$WS/src/alpha" "$WS/src/beta" "$WS/src/gamma" "$WS/src"

export BORG_BASE_DIR="$WS/ambient"
mkdir -p "$WS/state"
borg init --encryption=none "$WS/state/repo" || { echo "SETUP: borg init failed"; exit 2; }
cp -a "$WS/state" "$WS/pristine-state"
cp -a "$WS/ambient" "$WS/pristine-ambient"

note "condition 7 — ambient: BORG_BASE_DIR=<WS>/ambient, restored from the post-init pristine snapshot before every run (the restore commands are printed below). Post-init ambient snapshot:"
find "$WS/ambient" -type f | sed "s|$WS|WS|" | sort

restore() {
    rm -rf "$WS/state" "$WS/ambient"
    cp -a "$WS/pristine-state" "$WS/state"
    cp -a "$WS/pristine-ambient" "$WS/ambient"
    echo "restore: state and ambient reset to the pristine snapshots (in place, canonical paths)"
}

run_once() { # result-suffix
    sfx=$1
    restore
    if [ "$MODE" = control ]; then
        borg create "$WS/state/repo::probe" "$WS/src"
    else
        borg create --timestamp 2026-01-01T00:00:00 "$WS/state/repo::probe" "$WS/src"
    fi
    rc=$?
    cp -a "$WS/state" "$WS/state$sfx"
    cp -a "$WS/ambient" "$WS/ambient$sfx"
    return $rc
}

note "run A"; run_once A; rcA=$?

# Conditions 3/4 are measured at the CANONICAL path right after run A,
# while it still holds A's result — borg would treat the stateA copy as a
# relocated repository and refuse the prompt non-interactively.
listing=$(borg list --short "$WS/state/repo" 2>/dev/null)
mkdir -p "$WS/extract" && cd "$WS/extract"
borg extract "$WS/state/repo::probe" 2>/dev/null
extract_ok=no
diff -r "$WS/extract$WS/src" "$WS/src" > /dev/null 2>&1 && extract_ok=yes
cd /

# env -u FAKETIME: with the clock frozen at speed x0, libfaketime scales
# nanosleep to infinity — the harness's own gap sleep must run on the real
# clock (measured: the first frozen round hung exactly here, borg itself
# having completed run A fine). A no-op in the other modes.
env -u FAKETIME sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pristine-state/repo" "$WS/stateA/repo" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "state tree after run A differs from pre-state"

# Exactly one archive, and nothing else: the full --short listing is the
# assertion, not a grep for the expected name.
[ "$listing" = "probe" ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "borg list --short prints exactly 'probe' (got: '$listing')"

verdict "4-round-trip" $extract_ok "extracted bytes match the source tree"

note "diff -r of the two state trees:"
diff -r "$WS/stateA/repo" "$WS/stateB/repo"; drc=$?
if [ "$MODE" = control ]; then
    [ "$drc" -ne 0 ] && ok=yes || ok=no
    verdict "5-determinism-CONTROL" $ok "unpinned create must differ across runs (diff rc=$drc; 0=identical)"
else
    [ "$drc" -eq 0 ] && ok=yes || ok=no
    verdict "5-determinism" $ok "two runs >=2s apart byte-identical (diff rc=$drc)"
fi

note "strace pass (restored in place; raw log kept as <target>.strace)"
restore
if [ "$MODE" = control ]; then
    run_strace "$WS/strace.log" borg create "$WS/state/repo::probe" "$WS/src" > /dev/null 2>&1
else
    run_strace "$WS/strace.log" borg create --timestamp 2026-01-01T00:00:00 "$WS/state/repo::probe" "$WS/src" > /dev/null 2>&1
fi
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/borg-$MODE.strace" 2>/dev/null || true
note "mutating paths (all mutating syscalls, successful only, deduped):"
mutating_paths "$WS/strace.log" | sort -u | sed "s|$WS|WS|"
closure_check "$WS/strace.log" "$WS/state" "$WS/ambient" "$WS/extract" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
